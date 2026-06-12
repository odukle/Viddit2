class PostModel {
  final String id;
  final String fullName;
  final String title;
  final String subreddit;
  final String author;
  final double createdUtc;
  final int score;
  final int commentCount;
  final String permalink;
  final bool isNsfw;
  final bool isGif;
  final String thumbnail;
  final String videoUrl;
  final String fallbackVideoUrl;
  final String? audioUrl;
  int userVote; // 1 = Upvote, -1 = Downvote, 0 = No Vote
  bool isSaved;

  bool get isPlayableVideo {
    final url = videoUrl.split('?').first.toLowerCase();
    return url.contains('v.redd.it/') ||
        url.endsWith('.m3u8') ||
        url.endsWith('.mp4') ||
        url.contains('/hls/') ||
        url.contains('/dash_') ||
        isGif;
  }

  PostModel({
    required this.id,
    required this.fullName,
    required this.title,
    required this.subreddit,
    required this.author,
    required this.createdUtc,
    required this.score,
    required this.commentCount,
    required this.permalink,
    required this.isNsfw,
    required this.isGif,
    required this.thumbnail,
    required this.videoUrl,
    required this.fallbackVideoUrl,
    this.audioUrl,
    this.userVote = 0,
    this.isSaved = false,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    final crossPost = ((data['crosspost_parent_list'] as List?)?.isNotEmpty ??
            false)
        ? (data['crosspost_parent_list'] as List).first as Map<String, dynamic>
        : null;
    final source = crossPost ?? data;
    final id = data['id'] ?? '';
    final fullName = data['name'] ?? 't3_$id';
    final title = data['title'] ?? '';
    final subreddit = data['subreddit'] ?? '';
    final author = data['author'] ?? '';
    final createdUtc = (data['created_utc'] as num?)?.toDouble() ?? 0.0;
    final score = data['score'] as int? ?? 0;
    final commentCount = data['num_comments'] as int? ?? 0;
    final permalink = data['permalink'] ?? '';
    final isNsfw = data['over_18'] as bool? ?? false;
    String thumbnail =
        (data['thumbnail'] ?? '').toString().replaceAll('amp;', '');
    if (thumbnail.isEmpty ||
        thumbnail == 'self' ||
        thumbnail == 'default' ||
        thumbnail == 'nsfw') {
      final previewImage = source['preview']?['images'] as List?;
      if (previewImage != null && previewImage.isNotEmpty) {
        thumbnail = (previewImage.first['source']?['url'] ?? '')
            .toString()
            .replaceAll('amp;', '');
      }
    }

    // Parse video URL
    String videoUrl = '';
    String fallbackVideoUrl = '';
    String? audioUrl;
    bool isGif = false;

    // 1. Check hosted reddit video
    final secureMedia = source['secure_media'] ?? source['media'];
    if (secureMedia != null && secureMedia['reddit_video'] != null) {
      final redditVideo = secureMedia['reddit_video'];
      final hls = redditVideo['hls_url'] ?? '';
      final fallback = redditVideo['fallback_url'] ?? '';
      final dashUrl = redditVideo['dash_url'] ?? '';

      videoUrl =
          hls.isNotEmpty ? hls : (fallback.isNotEmpty ? fallback : dashUrl);
      videoUrl = videoUrl.replaceAll('amp;', '');
      fallbackVideoUrl = fallback.replaceAll('amp;', '');

      // Attempt to extract fallback audio URL if it's a DASH or CMAF video
      final cleanFallback = fallback.replaceAll('amp;', '');
      final cleanDash = dashUrl.toString().replaceAll('amp;', '');
      final cleanHls = hls.replaceAll('amp;', '');

      if (cleanFallback.contains('CMAF_')) {
        final index = cleanFallback.indexOf('CMAF_');
        audioUrl = '${cleanFallback.substring(0, index)}CMAF_AUDIO_128.mp4';
      } else if (cleanFallback.contains('DASH_')) {
        final index = cleanFallback.indexOf('DASH_');
        audioUrl = '${cleanFallback.substring(0, index)}DASH_audio.mp4';
      } else if (cleanDash.contains('CMAF_')) {
        final index = cleanDash.indexOf('CMAF_');
        audioUrl = '${cleanDash.substring(0, index)}CMAF_AUDIO_128.mp4';
      } else if (cleanDash.contains('DASH_')) {
        final index = cleanDash.indexOf('DASH_');
        audioUrl = '${cleanDash.substring(0, index)}DASH_audio.mp4';
      } else if (cleanHls.isNotEmpty && cleanHls.contains('v.redd.it/')) {
        final hlsBase = cleanHls.substring(0, cleanHls.lastIndexOf('/') + 1);
        if (cleanFallback.contains('CMAF')) {
          audioUrl = '${hlsBase}CMAF_AUDIO_128.mp4';
        } else {
          audioUrl = '${hlsBase}DASH_audio.mp4';
        }
      }
      isGif = redditVideo['is_gif'] as bool? ?? false;
    }

    // 2. Check preview variants (e.g. mp4, gif) if no direct video found
    if (videoUrl.isEmpty && source['preview'] != null) {
      final preview = source['preview'];
      final redditVideoPreview = preview['reddit_video_preview'];
      if (redditVideoPreview != null) {
        final hls = redditVideoPreview['hls_url'] ?? '';
        final fallback = redditVideoPreview['fallback_url'] ?? '';
        videoUrl =
            (hls.isNotEmpty ? hls : fallback).toString().replaceAll('amp;', '');
        fallbackVideoUrl = fallback.toString().replaceAll('amp;', '');
        isGif = redditVideoPreview['is_gif'] as bool? ?? false;
      }

      if (preview['images'] != null && preview['images'].isNotEmpty) {
        final image = preview['images'][0];

        // Try getting GIF URL
        final urlStr = image['source']?['url'] ?? '';
        if (urlStr.contains('.gif?') || urlStr.endsWith('.gif')) {
          isGif = true;
        }

        // Try getting MP4 variant
        if (image['variants'] != null) {
          final variants = image['variants'];
          if (variants['mp4'] != null) {
            videoUrl = variants['mp4']['source']?['url'] ?? '';
          } else if (variants['gif'] != null) {
            videoUrl = variants['gif']['source']?['url'] ?? '';
          }
        }
      }
    }

    // 3. Fallback to image url if nothing else is available
    if (videoUrl.isEmpty && source['media_metadata'] is Map<String, dynamic>) {
      final mediaMetadata = source['media_metadata'] as Map<String, dynamic>;
      for (final entry in mediaMetadata.values) {
        if (entry is! Map<String, dynamic>) continue;
        final sourceMap = entry['s'] as Map<String, dynamic>?;
        final gif = sourceMap?['gif'];
        final mp4 = sourceMap?['mp4'];
        if (mp4 != null || gif != null) {
          videoUrl = (mp4 ?? gif).toString().replaceAll('amp;', '');
          isGif = gif != null;
          break;
        }
      }
    }

    if (videoUrl.isEmpty) {
      videoUrl =
          (source['url_overridden_by_dest'] ?? source['url'] ?? '').toString();
    }
    videoUrl = videoUrl.replaceAll('amp;', '');

    // Reset isGif if the resolved url is a static image format
    final cleanUrl = videoUrl.split('?').first.toLowerCase();
    if (cleanUrl.endsWith('.jpg') ||
        cleanUrl.endsWith('.jpeg') ||
        cleanUrl.endsWith('.png') ||
        cleanUrl.endsWith('.webp')) {
      isGif = false;
    }

    // Determine user vote from API if present
    int vote = 0;
    if (data['likes'] != null) {
      vote = (data['likes'] as bool) ? 1 : -1;
    }

    final isSaved = data['saved'] as bool? ?? false;

    if (fallbackVideoUrl.isEmpty) {
      fallbackVideoUrl = videoUrl;
    }

    return PostModel(
      id: id,
      fullName: fullName,
      title: title,
      subreddit: subreddit,
      author: author,
      createdUtc: createdUtc,
      score: score,
      commentCount: commentCount,
      permalink: permalink,
      isNsfw: isNsfw,
      isGif: isGif,
      thumbnail: thumbnail,
      videoUrl: videoUrl,
      fallbackVideoUrl: fallbackVideoUrl,
      audioUrl: audioUrl,
      userVote: vote,
      isSaved: isSaved,
    );
  }
}
