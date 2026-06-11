import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// Lightweight in-memory HTTP server that serves cached HLS segments
/// from the local filesystem, falling back to the network for anything
/// not yet cached.
class _HlsProxyServer {
  HttpServer? _server;
  final Map<String, String> _urlToCacheDir = {};

  /// Starts the server on a random ephemeral port.
  Future<int> start() async {
    if (_server != null) return _server!.port;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
    return _server!.port;
  }

  void register(String originalUrl, String cacheDirectory) {
    _urlToCacheDir[originalUrl] = cacheDirectory;
  }

  void unregister(String originalUrl) {
    _urlToCacheDir.remove(originalUrl);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      // Path format: /proxy/<base64_original_url>/<segment_path>
      final segments = request.uri.pathSegments;
      if (segments.length < 3 || segments[0] != 'proxy') {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final originalUrl = utf8.decode(base64Url.decode(segments[1]));
      final relativePath = segments.sublist(2).join('/');
      final cacheDir = _urlToCacheDir[originalUrl];

      if (cacheDir == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final localFile = File('$cacheDir/$relativePath');
      if (await localFile.exists()) {
        final bytes = await localFile.readAsBytes();
        _setContentType(request.response, relativePath);
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
        return;
      }

      // Not cached yet — proxy from origin
      final originUri = Uri.parse(originalUrl);
      final originPath = originUri.path;
      final originDir =
          originPath.substring(0, originPath.lastIndexOf('/') + 1);
      final networkUrl =
          '${originUri.scheme}://${originUri.host}$originDir$relativePath';

      try {
        final response = await http
            .get(Uri.parse(networkUrl))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode == 200) {
          await localFile.parent.create(recursive: true);
          await localFile.writeAsBytes(response.bodyBytes);
          _setContentType(request.response, relativePath);
          request.response.contentLength = response.bodyBytes.length;
          request.response.add(response.bodyBytes);
        } else {
          request.response.statusCode = response.statusCode;
        }
      } catch (_) {
        request.response.statusCode = HttpStatus.badGateway;
      }
      await request.response.close();
    } catch (e) {
      debugPrint('HLS proxy error: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  void _setContentType(HttpResponse response, String path) {
    if (path.endsWith('.m3u8')) {
      response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl');
    } else if (path.endsWith('.ts')) {
      response.headers.contentType = ContentType('video', 'mp2t');
    } else if (path.endsWith('.mp4')) {
      response.headers.contentType = ContentType('video', 'mp4');
    }
  }
}

/// Manages caching of Reddit HLS video streams.
///
/// - Streams are served directly from the network URL.
/// - When a stream is requested, a background download of the HLS playlist
///   and its segments begins.
/// - Once fully cached, [getCacheOrDownload] returns a local proxy URL
///   that the video_player can play with full audio.
class VideoCacheManager {
  static final VideoCacheManager _instance = VideoCacheManager._internal();
  factory VideoCacheManager() => _instance;
  VideoCacheManager._internal();

  static const String _cacheDirName = 'viddit_video_cache';
  static const int _maxCacheSize = 250 * 1024 * 1024; // 250 MB
  static const Duration _maxCacheAge = Duration(days: 3);

  final _HlsProxyServer _proxy = _HlsProxyServer();
  Directory? _cacheDir;
  final Set<String> _activeDownloads = {};
  final List<String> _preloadQueue = [];
  final Map<String, CancelToken> _cancelTokens = {};
  static const int _maxConcurrentDownloads = 2;
  String? _activeVideoKey;
  bool _isProcessingQueue = false;
  final Map<String, double> _downloadProgress = {};
  final Map<String, List<void Function(double)>> _progressListeners = {};

  double? getDownloadProgress(String url) {
    final key = _getCacheKey(url);
    return _downloadProgress[key];
  }

  void addProgressListener(String url, void Function(double) listener) {
    final key = _getCacheKey(url);
    _progressListeners.putIfAbsent(key, () => []).add(listener);
    if (_downloadProgress.containsKey(key)) {
      listener(_downloadProgress[key]!);
    }
  }

  void removeProgressListener(String url, void Function(double) listener) {
    final key = _getCacheKey(url);
    _progressListeners[key]?.remove(listener);
  }

  void _notifyProgress(String key, double progress) {
    _downloadProgress[key] = progress;
    final listeners = _progressListeners[key];
    if (listeners != null) {
      for (final listener in List<void Function(double)>.from(listeners)) {
        listener(progress);
      }
    }
  }

  int? _proxyPort;

  Future<int> _ensureProxy() async {
    _proxyPort ??= await _proxy.start();
    return _proxyPort!;
  }

  Future<Directory> _getCacheDirectory() async {
    if (_cacheDir != null) return _cacheDir!;
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/$_cacheDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return _cacheDir!;
  }

  String _getCacheKey(String url) {
    final cleanUrl = url.split('?').first;
    return cleanUrl.replaceAll(RegExp(r'[^\w\s\-]'), '_');
  }

  /// Returns a local proxy URL if the HLS stream is fully cached,
  /// otherwise returns `null` so the caller can stream from the network.
  Future<String?> getCacheOrDownload(String hlsUrl) async {
    if (hlsUrl.isEmpty) return null;

    try {
      // Only handle Reddit HLS URLs
      if (!hlsUrl.contains('v.redd.it/')) return null;

      final cacheDir = await _getCacheDirectory();
      final key = _getCacheKey(hlsUrl);
      _activeVideoKey = key;
      final hlsCacheDir = Directory('${cacheDir.path}/$key');

      // Check if fully cached
      final playlistFile = File('${hlsCacheDir.path}/playlist.m3u8');
      if (await playlistFile.exists()) {
        final content = await playlistFile.readAsString();
        final isCached = await _isHlsFullyCached(hlsCacheDir, content);
        if (isCached) {
          final port = await _ensureProxy();
          _proxy.register(hlsUrl, hlsCacheDir.path);
          final encoded = base64Url.encode(utf8.encode(hlsUrl));
          return 'http://127.0.0.1:$port/proxy/$encoded/playlist.m3u8';
        }
      }

      // Not fully cached — start background download
      if (!_activeDownloads.contains(key)) {
        // Cancel one running preload if at limit to prioritize this active video download
        if (_cancelTokens.length >= _maxConcurrentDownloads) {
          final preloadKeys =
              _cancelTokens.keys.where((k) => k != key).toList();
          if (preloadKeys.isNotEmpty) {
            final keyToCancel = preloadKeys.first;
            _cancelTokens[keyToCancel]
                ?.cancel('Cancelled to prioritize active video');
            _cancelTokens.remove(keyToCancel);
            _activeDownloads.remove(keyToCancel);
          }
        }

        _activeDownloads.add(key);
        final cancelToken = CancelToken();
        _cancelTokens[key] = cancelToken;

        // ignore: unawaited_futures
        _downloadHlsInBackground(hlsUrl, hlsCacheDir, key,
            cancelToken: cancelToken);
      }
    } catch (e) {
      debugPrint('Error checking HLS cache: $e');
    }
    return null;
  }

  /// Parses a local M3U8 playlist and returns the relative segment paths.
  Future<List<String>> _listSegments(File playlistFile) async {
    final lines = await playlistFile.readAsLines();
    final segments = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      segments.add(trimmed.split('?').first);
    }
    return segments;
  }

  Future<bool> _isHlsFullyCached(
      Directory hlsCacheDir, String masterPlaylistContent) async {
    final lines = const LineSplitter().convert(masterPlaylistContent);

    // Check video variant
    String? videoVariantFile;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('#EXT-X-STREAM-INF')) {
        if (i + 1 < lines.length) {
          final url = lines[i + 1].trim();
          videoVariantFile = url.split('/').last.split('?').first;
          break;
        }
      }
    }

    if (videoVariantFile == null) {
      // Not a master playlist, treat playlist.m3u8 as media playlist
      return _areSegmentsCached(
          hlsCacheDir, File('${hlsCacheDir.path}/playlist.m3u8'));
    }

    // Check if the video variant playlist itself exists
    final videoPlaylistFile = File('${hlsCacheDir.path}/$videoVariantFile');
    if (!await videoPlaylistFile.exists()) return false;
    if (!await _areSegmentsCached(hlsCacheDir, videoPlaylistFile)) return false;

    // Check audio variant if present
    String? audioVariantFile;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#EXT-X-MEDIA:') &&
          trimmed.contains('TYPE=AUDIO')) {
        final match = RegExp(r'URI="([^"]+)"').firstMatch(trimmed);
        if (match != null) {
          audioVariantFile = match.group(1)!.split('/').last.split('?').first;
          break;
        }
      }
    }

    if (audioVariantFile != null) {
      final audioPlaylistFile = File('${hlsCacheDir.path}/$audioVariantFile');
      if (!await audioPlaylistFile.exists()) return false;
      if (!await _areSegmentsCached(hlsCacheDir, audioPlaylistFile)) {
        return false;
      }
    }

    return true;
  }

  Future<bool> _areSegmentsCached(
      Directory hlsCacheDir, File mediaPlaylistFile) async {
    final segments = await _listSegments(mediaPlaylistFile);
    if (segments.isEmpty) return false;
    for (final seg in segments) {
      final segFile = File('${hlsCacheDir.path}/$seg');
      if (!await segFile.exists()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _downloadHlsInBackground(
      String hlsUrl, Directory hlsCacheDir, String key,
      {CancelToken? cancelToken}) async {
    try {
      _notifyProgress(key, 0.0);
      await hlsCacheDir.create(recursive: true);
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      // 1. Download master / playlist
      final playlistResponse =
          await dio.get<String>(hlsUrl, cancelToken: cancelToken);
      if (playlistResponse.statusCode != 200 || playlistResponse.data == null) {
        return;
      }

      final masterPlaylistContent = playlistResponse.data!;
      final playlistUri = Uri.parse(hlsUrl);
      final basePath =
          '${playlistUri.scheme}://${playlistUri.host}${playlistUri.path}';
      final baseDir = basePath.substring(0, basePath.lastIndexOf('/') + 1);

      // Write the local playlist (always master/playlist)
      final localPlaylist = File('${hlsCacheDir.path}/playlist.m3u8');
      if (!await localPlaylist.parent.exists()) {
        await localPlaylist.parent.create(recursive: true);
      }
      await localPlaylist.writeAsString(masterPlaylistContent);

      if (masterPlaylistContent.contains('#EXT-X-STREAM-INF')) {
        // It is a master playlist — download first video variant and audio variant

        // A. Video variant
        final videoVariantUrl =
            _extractFirstVariant(masterPlaylistContent, baseDir);
        if (videoVariantUrl != null) {
          final videoVariantResponse =
              await dio.get<String>(videoVariantUrl, cancelToken: cancelToken);
          if (videoVariantResponse.statusCode == 200 &&
              videoVariantResponse.data != null) {
            final videoPlaylistContent = videoVariantResponse.data!;
            final videoVariantFilename =
                videoVariantUrl.split('/').last.split('?').first;

            final videoUri = Uri.parse(videoVariantUrl);
            final videoBase =
                '${videoUri.scheme}://${videoUri.host}${videoUri.path}';
            final videoDir =
                videoBase.substring(0, videoBase.lastIndexOf('/') + 1);

            final rewrittenVideoPlaylist = await _downloadSegments(
                dio, videoPlaylistContent, videoDir, hlsCacheDir,
                cancelToken: cancelToken,
                onProgress: (p) => _notifyProgress(key, p));

            final localVideoPlaylist =
                File('${hlsCacheDir.path}/$videoVariantFilename');
            await localVideoPlaylist.writeAsString(rewrittenVideoPlaylist);
          }
        }

        // B. Audio variant
        final audioVariantUrl =
            _extractAudioVariant(masterPlaylistContent, baseDir);
        if (audioVariantUrl != null) {
          final audioVariantResponse =
              await dio.get<String>(audioVariantUrl, cancelToken: cancelToken);
          if (audioVariantResponse.statusCode == 200 &&
              audioVariantResponse.data != null) {
            final audioPlaylistContent = audioVariantResponse.data!;
            final audioVariantFilename =
                audioVariantUrl.split('/').last.split('?').first;

            final audioUri = Uri.parse(audioVariantUrl);
            final audioBase =
                '${audioUri.scheme}://${audioUri.host}${audioUri.path}';
            final audioDir =
                audioBase.substring(0, audioBase.lastIndexOf('/') + 1);

            final rewrittenAudioPlaylist = await _downloadSegments(
                dio, audioPlaylistContent, audioDir, hlsCacheDir,
                cancelToken: cancelToken);

            final localAudioPlaylist =
                File('${hlsCacheDir.path}/$audioVariantFilename');
            await localAudioPlaylist.writeAsString(rewrittenAudioPlaylist);
          }
        }
      } else {
        // Already a media playlist (e.g. no master, direct video stream)
        final rewrittenPlaylist = await _downloadSegments(
            dio, masterPlaylistContent, baseDir, hlsCacheDir,
            cancelToken: cancelToken,
            onProgress: (p) => _notifyProgress(key, p));
        await localPlaylist.writeAsString(rewrittenPlaylist);
      }

      // Register with proxy so future calls return the local URL
      await _ensureProxy();
      _proxy.register(hlsUrl, hlsCacheDir.path);

      _cleanupCacheInBackground();
    } catch (e) {
      debugPrint('Background HLS download failed for $hlsUrl: $e');
    } finally {
      _activeDownloads.remove(key);
      _cancelTokens.remove(key);
      _processPreloadQueue();
    }
  }

  String? _extractFirstVariant(String masterPlaylist, String baseDir) {
    final lines = const LineSplitter().convert(masterPlaylist);
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('#EXT-X-STREAM-INF')) {
        if (i + 1 < lines.length) {
          final url = lines[i + 1].trim();
          if (url.startsWith('http')) return url;
          return '$baseDir$url';
        }
      }
    }
    return null;
  }

  String? _extractAudioVariant(String masterPlaylist, String baseDir) {
    final lines = const LineSplitter().convert(masterPlaylist);
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#EXT-X-MEDIA:') &&
          trimmed.contains('TYPE=AUDIO')) {
        final match = RegExp(r'URI="([^"]+)"').firstMatch(trimmed);
        if (match != null) {
          final url = match.group(1)!;
          if (url.startsWith('http')) return url;
          return '$baseDir$url';
        }
      }
    }
    return null;
  }

  Future<String> _downloadSegments(
    Dio dio,
    String playlistContent,
    String baseDir,
    Directory hlsCacheDir, {
    CancelToken? cancelToken,
    void Function(double)? onProgress,
  }) async {
    final lines = const LineSplitter().convert(playlistContent);
    final newLines = <String>[];

    final segments = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      segments.add(trimmed);
    }
    final totalSegments = segments.length;
    var downloadedCount = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        newLines.add(line);
        continue;
      }

      if (cancelToken?.isCancelled == true) {
        throw DioException(
          requestOptions: RequestOptions(path: trimmed),
          type: DioExceptionType.cancel,
          error: 'Download cancelled',
        );
      }

      final segmentUrl =
          trimmed.startsWith('http') ? trimmed : '$baseDir$trimmed';
      final segmentName = trimmed.split('/').last.split('?').first;
      final localFile = File('${hlsCacheDir.path}/$segmentName');

      if (!await localFile.exists()) {
        try {
          final response = await dio.get<List<int>>(
            segmentUrl,
            options: Options(responseType: ResponseType.bytes),
            cancelToken: cancelToken,
            onReceiveProgress: (received, total) {
              if (total > 0 && totalSegments > 0) {
                final segmentProgress = received / total;
                final overallProgress =
                    (downloadedCount + segmentProgress) / totalSegments;
                onProgress?.call(overallProgress);
              }
            },
          );
          if (response.statusCode == 200 && response.data != null) {
            if (!await localFile.parent.exists()) {
              await localFile.parent.create(recursive: true);
            }
            await localFile.writeAsBytes(response.data!);
          }
        } catch (e) {
          if (cancelToken?.isCancelled == true) {
            rethrow;
          }
          debugPrint('Segment download failed: $segmentUrl — $e');
        }
      }

      downloadedCount++;
      if (totalSegments > 0) {
        onProgress?.call(downloadedCount / totalSegments);
      }
      newLines.add(segmentName);
    }
    return newLines.join('\n');
  }

  /// Synchronously downloads the full HLS stream (playlist + all segments),
  /// concatenates the segments into a single `.ts` file, and returns its path.
  /// The `.ts` container preserves audio because segments are already muxed.
  Future<File?> downloadHlsAsSingleFile(
    String hlsUrl, {
    required void Function(double progress) onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (hlsUrl.isEmpty || !hlsUrl.contains('v.redd.it/')) return null;

    final cacheDir = await _getCacheDirectory();
    final key = _getCacheKey(hlsUrl);
    final hlsCacheDir = Directory('${cacheDir.path}/$key');
    await hlsCacheDir.create(recursive: true);

    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 30);

    try {
      // 1. Fetch playlist
      final playlistResponse = await dio.get<String>(hlsUrl);
      if (playlistResponse.statusCode != 200 || playlistResponse.data == null) {
        return null;
      }

      var playlistContent = playlistResponse.data!;
      final playlistUri = Uri.parse(hlsUrl);
      final basePath =
          '${playlistUri.scheme}://${playlistUri.host}${playlistUri.path}';
      var baseDir = basePath.substring(0, basePath.lastIndexOf('/') + 1);

      // 2. Resolve master playlist → media playlist
      if (playlistContent.contains('#EXT-X-STREAM-INF')) {
        final variantUrl = _extractFirstVariant(playlistContent, baseDir);
        if (variantUrl != null) {
          final variantResponse = await dio.get<String>(variantUrl);
          if (variantResponse.statusCode == 200 &&
              variantResponse.data != null) {
            playlistContent = variantResponse.data!;
            final variantUri = Uri.parse(variantUrl);
            final variantBase =
                '${variantUri.scheme}://${variantUri.host}${variantUri.path}';
            baseDir =
                variantBase.substring(0, variantBase.lastIndexOf('/') + 1);
          }
        }
      }

      // 3. Parse segment URLs
      final segmentUrls = <String>[];
      final segmentNames = <String>[];
      final lines = const LineSplitter().convert(playlistContent);
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final url = trimmed.startsWith('http') ? trimmed : '$baseDir$trimmed';
        segmentUrls.add(url);
        segmentNames.add(trimmed.split('/').last);
      }

      if (segmentUrls.isEmpty) return null;

      // 4. Download all segments with progress
      final totalSegments = segmentUrls.length;
      for (var i = 0; i < totalSegments; i++) {
        final segUrl = segmentUrls[i];
        final segName = segmentNames[i];
        final localFile = File('${hlsCacheDir.path}/$segName');

        if (!await localFile.exists()) {
          final response = await dio.get<List<int>>(
            segUrl,
            options: Options(responseType: ResponseType.bytes),
          );
          if (response.statusCode == 200 && response.data != null) {
            if (!await localFile.parent.exists()) {
              await localFile.parent.create(recursive: true);
            }
            await localFile.writeAsBytes(response.data!);
          }
        }
        onProgress((i + 1) / totalSegments);
      }

      // 5. Concatenate segments into a single .ts file
      final outputFile = File('${hlsCacheDir.path}/merged.ts');
      final sink = outputFile.openWrite();
      for (var i = 0; i < totalSegments; i++) {
        final segFile = File('${hlsCacheDir.path}/${segmentNames[i]}');
        if (await segFile.exists()) {
          await sink.addStream(segFile.openRead());
        }
      }
      await sink.close();

      return outputFile;
    } catch (e) {
      debugPrint('HLS single-file download failed: $e');
      return null;
    }
  }

  Future<void> _cleanupCacheInBackground() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final entries = cacheDir.listSync();
      final now = DateTime.now();

      for (final entry in entries) {
        if (entry is Directory) {
          // Check age of the directory by its newest file
          final files = entry.listSync().whereType<File>().toList();
          if (files.isEmpty) {
            final dirName = entry.path.split('/').last;
            if (!_activeDownloads.contains(dirName)) {
              await entry.delete(recursive: true);
            }
            continue;
          }
          DateTime? newest;
          for (final f in files) {
            final mod = await f.lastModified();
            if (newest == null || mod.isAfter(newest)) newest = mod;
          }
          if (newest != null && now.difference(newest) > _maxCacheAge) {
            await entry.delete(recursive: true);
          }
        } else if (entry is File && entry.path.endsWith('.tmp')) {
          final mod = await entry.lastModified();
          if (now.difference(mod) > const Duration(hours: 3)) {
            await entry.delete();
          }
        }
      }

      // Size-based eviction
      int totalSize = 0;
      final dirSizes = <Directory, int>{};
      final dirAges = <Directory, DateTime>{};

      for (final entry in cacheDir.listSync().whereType<Directory>()) {
        int size = 0;
        DateTime? newest;
        for (final f in entry.listSync().whereType<File>()) {
          size += await f.length();
          final mod = await f.lastModified();
          if (newest == null || mod.isAfter(newest)) newest = mod;
        }
        totalSize += size;
        dirSizes[entry] = size;
        if (newest != null) dirAges[entry] = newest;
      }

      if (totalSize > _maxCacheSize) {
        final sorted = dirAges.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (final entry in sorted) {
          if (totalSize <= _maxCacheSize * 0.7) break;
          final size = dirSizes[entry.key] ?? 0;
          await entry.key.delete(recursive: true);
          totalSize -= size;
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up video cache: $e');
    }
  }

  /// Preloads a list of HLS URLs in the background.
  /// Cancels any active preloads that are not in the new list and not the active video.
  Future<void> preloadVideos(List<String> urls,
      {required String activeUrl}) async {
    final activeKey = _getCacheKey(activeUrl);
    _activeVideoKey = activeKey;

    final targetKeys = urls.map((url) => _getCacheKey(url)).toList();

    // Cancel active downloads that are NOT in the target keys list and NOT the active video
    final keysToCancel = _cancelTokens.keys
        .where((k) => !targetKeys.contains(k) && k != _activeVideoKey)
        .toList();

    for (final key in keysToCancel) {
      _cancelTokens[key]?.cancel('Preload cancelled');
      _cancelTokens.remove(key);
      _activeDownloads.remove(key);
    }

    // Clear and update queue
    _preloadQueue.clear();
    _preloadQueue.addAll(urls);

    await _processPreloadQueue();
  }

  Future<void> _processPreloadQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_preloadQueue.isNotEmpty &&
          _cancelTokens.length < _maxConcurrentDownloads) {
        String? nextUrl;
        for (final url in _preloadQueue) {
          final key = _getCacheKey(url);
          if (_activeDownloads.contains(key)) continue;

          // Check if already fully cached
          final cacheDir = await _getCacheDirectory();
          final hlsCacheDir = Directory('${cacheDir.path}/$key');
          final playlistFile = File('${hlsCacheDir.path}/playlist.m3u8');
          bool isCached = false;
          if (await playlistFile.exists()) {
            final content = await playlistFile.readAsString();
            isCached = await _isHlsFullyCached(hlsCacheDir, content);
          }

          if (isCached) {
            await _ensureProxy();
            _proxy.register(url, hlsCacheDir.path);
            continue;
          }

          nextUrl = url;
          break;
        }

        if (nextUrl == null) {
          break;
        }

        final key = _getCacheKey(nextUrl);
        final cacheDir = await _getCacheDirectory();
        final hlsCacheDir = Directory('${cacheDir.path}/$key');

        _activeDownloads.add(key);
        final cancelToken = CancelToken();
        _cancelTokens[key] = cancelToken;

        // ignore: unawaited_futures
        _downloadHlsInBackground(nextUrl, hlsCacheDir, key,
            cancelToken: cancelToken);
      }
    } catch (e) {
      debugPrint('Error in _processPreloadQueue: $e');
    } finally {
      _isProcessingQueue = false;
    }
  }
}
