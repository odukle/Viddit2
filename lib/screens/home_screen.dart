import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post_model.dart';
import '../api/reddit_api.dart';
import '../api/video_cache_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/video_player_widget.dart';
import 'subreddit_screen.dart';
import 'login_screen.dart';
import '../widgets/pressable_scale.dart';

class HomeScreen extends StatefulWidget {
  final String feedType; // front_page, popular, subreddit, custom_feed, user
  final String query;
  final List<PostModel>? initialPosts;
  final int initialIndex;
  final bool hasBottomNavBar;
  final bool isTabActive;

  const HomeScreen({
    super.key,
    this.feedType = 'front_page',
    this.query = '',
    this.initialPosts,
    this.initialIndex = 0,
    this.hasBottomNavBar = false,
    this.isTabActive = true,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late PageController _horizontalPageController;
  int _horizontalIndex = 0;
  double _pageOffset = 0.0;
  String _currentFrontPageSort = 'hot';

  final GlobalKey<VerticalFeedWidgetState> _frontPageKey =
      GlobalKey<VerticalFeedWidgetState>();
  final GlobalKey<VerticalFeedWidgetState> _popularKey =
      GlobalKey<VerticalFeedWidgetState>();
  final GlobalKey<VerticalFeedWidgetState> _singleFeedKey =
      GlobalKey<VerticalFeedWidgetState>();

  bool get _isDualFeed =>
      widget.initialPosts == null &&
      (widget.feedType == 'front_page' || widget.feedType == 'popular');

  @override
  void initState() {
    super.initState();
    _horizontalIndex = widget.feedType == 'popular' ? 1 : 0;
    _pageOffset = _horizontalIndex.toDouble();
    _horizontalPageController = PageController(initialPage: _horizontalIndex);
    _horizontalPageController.addListener(_pageScrollListener);
  }

  void _pageScrollListener() {
    if (_horizontalPageController.hasClients) {
      setState(() {
        _pageOffset = _horizontalPageController.page ?? 0.0;
      });
    }
  }

  @override
  void dispose() {
    _horizontalPageController.removeListener(_pageScrollListener);
    _horizontalPageController.dispose();
    super.dispose();
  }

  Future<void> refreshFeed() async {
    if (_isDualFeed) {
      if (_horizontalIndex == 0) {
        await _frontPageKey.currentState?.refresh();
      } else {
        await _popularKey.currentState?.refresh();
      }
    } else {
      await _singleFeedKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDualFeed) {
      return VerticalFeedWidget(
        key: _singleFeedKey,
        feedType: widget.feedType,
        query: widget.query,
        initialPosts: widget.initialPosts,
        initialIndex: widget.initialIndex,
        hasBottomNavBar: widget.hasBottomNavBar,
        isFeedActive: widget.isTabActive,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView(
            controller: _horizontalPageController,
            onPageChanged: (index) {
              setState(() {
                _horizontalIndex = index;
              });
            },
            children: [
              VerticalFeedWidget(
                key: _frontPageKey,
                feedType: 'front_page',
                query: widget.query,
                hasBottomNavBar: widget.hasBottomNavBar,
                isFeedActive: widget.isTabActive && _horizontalIndex == 0,
              ),
              VerticalFeedWidget(
                key: _popularKey,
                feedType: 'popular',
                query: widget.query,
                hasBottomNavBar: widget.hasBottomNavBar,
                isFeedActive: widget.isTabActive && _horizontalIndex == 1,
              ),
            ],
          ),

          // Custom header layout (Tabs: Front Page / Popular)
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 240,
                height: 40,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12), width: 0.8),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Sliding background indicator
                    Positioned(
                      left: 1 + _pageOffset.clamp(0.0, 1.0) * (232 - 114 - 2),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 114,
                        decoration: BoxDecoration(
                          gradient: AppTheme.brandGradient,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppTheme.accentOrange.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Tabs text overlay
                    Row(
                      children: [
                        _buildFeedTab('Front Page', 0),
                        _buildFeedTab('Popular', 1),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSortMenu(BuildContext context) async {
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final width = MediaQuery.of(context).size.width;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(width / 2 - 110, 90, 110, 40),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<String>(
      context: context,
      position: position,
      initialValue: _currentFrontPageSort,
      color: AppTheme.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'best',
          child: Text(
            'Best',
            style: TextStyle(
              color: _currentFrontPageSort == 'best'
                  ? AppTheme.accentOrange
                  : Colors.white,
              fontWeight: _currentFrontPageSort == 'best'
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ),
        PopupMenuItem(
          value: 'hot',
          child: Text(
            'Hot',
            style: TextStyle(
              color: _currentFrontPageSort == 'hot'
                  ? AppTheme.accentOrange
                  : Colors.white,
              fontWeight: _currentFrontPageSort == 'hot'
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ),
        PopupMenuItem(
          value: 'new',
          child: Text(
            'New',
            style: TextStyle(
              color: _currentFrontPageSort == 'new'
                  ? AppTheme.accentOrange
                  : Colors.white,
              fontWeight: _currentFrontPageSort == 'new'
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ),
        PopupMenuItem(
          value: 'top',
          child: Text(
            'Top',
            style: TextStyle(
              color: _currentFrontPageSort == 'top'
                  ? AppTheme.accentOrange
                  : Colors.white,
              fontWeight: _currentFrontPageSort == 'top'
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ),
      ],
    );

    if (selected != null && mounted) {
      _frontPageKey.currentState?.changeSort(selected);
      setState(() {
        _currentFrontPageSort = selected;
      });
    }
  }

  Widget _buildFeedTab(String label, int index) {
    final double distance = (_pageOffset.clamp(0.0, 1.0) - index).abs();
    final double textOpacity = (1.0 - distance).clamp(0.0, 1.0);
    final Color textColor =
        Color.lerp(AppTheme.textSecondary, Colors.white, textOpacity) ??
            Colors.white;

    return Expanded(
      child: PressableScale(
        onTap: () {
          if (index == _horizontalIndex) {
            if (index == 0) {
              _showSortMenu(context);
            }
          } else {
            _horizontalPageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
            );
          }
        },
        child: Container(
          color: Colors.transparent, // make entire area tappable
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                if (index == 0) ...[
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 14,
                    color: textColor.withValues(alpha: 0.8),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VerticalFeedWidget extends StatefulWidget {
  final String feedType;
  final String query;
  final List<PostModel>? initialPosts;
  final int initialIndex;
  final bool hasBottomNavBar;
  final bool isFeedActive;

  const VerticalFeedWidget({
    super.key,
    required this.feedType,
    this.query = '',
    this.initialPosts,
    this.initialIndex = 0,
    this.hasBottomNavBar = false,
    required this.isFeedActive,
  });

  @override
  State<VerticalFeedWidget> createState() => VerticalFeedWidgetState();
}

class VerticalFeedWidgetState extends State<VerticalFeedWidget>
    with AutomaticKeepAliveClientMixin {
  final RedditApi _api = RedditApi();
  final List<PostModel> _posts = [];
  late PageController _pageController;
  int _currentIndex = 0;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  String _afterToken = '';
  bool _allLoaded = false;
  static bool _isGlobalMuted = true;
  late String _activeFeedType;
  String _activeSort = 'hot';

  void changeSort(String newSort) {
    if (_activeSort == newSort) return;
    setState(() {
      _activeSort = newSort;
    });
    refresh();
  }

  String? _feedError;
  final Set<String> _seenPostIds = {};
  final Set<String> _seenVideoUrls = {};
  String _lastGeolocation = 'AUTO';
  String? _lastRegionOverride;
  String _loadingStatus = 'Initializing feed...';

  Set<String> _viewedPostIds = {};
  Timer? _viewTimer;
  Set<String> _lastSubscribedSubreddits = {};
  int _loadSession = 0;

  static const String _viewedHistoryKey = 'viddit_viewed_post_ids';
  static const int _maxViewedHistory = 500;

  @override
  void initState() {
    super.initState();
    _activeFeedType = widget.feedType;
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _lastGeolocation = _api.geolocation;
    _lastRegionOverride = _api.regionOverride;

    _initHomeScreen();
    _api.addSafetyListener(_onSafetySettingsChanged);
  }

  @override
  void didUpdateWidget(covariant VerticalFeedWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFeedActive && !oldWidget.isFeedActive) {
      _startViewTimer(_currentIndex);
      _syncFeedOnSubscriptionChange();
    } else if (!widget.isFeedActive && oldWidget.isFeedActive) {
      _viewTimer?.cancel();
    }
  }

  void _syncFeedOnSubscriptionChange() {
    if (widget.feedType == 'front_page' && _api.isLoggedIn) {
      final currentSubsList = _api.cachedSubscribedSubreddits;
      if (currentSubsList != null) {
        final currentSubs = currentSubsList.map((s) => s.toLowerCase()).toSet();

        // Find newly subscribed subreddits (in currentSubs but not in _lastSubscribedSubreddits)
        final addedSubs = currentSubs.difference(_lastSubscribedSubreddits);

        // Find unsubscribed subreddits (in _lastSubscribedSubreddits but not in currentSubs)
        final removedSubs = _lastSubscribedSubreddits.difference(currentSubs);

        if (addedSubs.isNotEmpty) {
          debugPrint(
              'Detected newly subscribed subreddits: $addedSubs. Refreshing feed.');
          _lastSubscribedSubreddits = currentSubs;
          refresh();
        } else if (removedSubs.isNotEmpty) {
          debugPrint(
              'Detected unsubscribed subreddits: $removedSubs. Filtering locally.');
          setState(() {
            _posts.removeWhere((post) {
              final cleanSub =
                  post.subreddit.replaceAll('r/', '').trim().toLowerCase();
              return removedSubs.contains(cleanSub);
            });
            _lastSubscribedSubreddits = currentSubs;
          });
        }
      }
    }
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> refresh() async {
    await _loadFeed(refresh: true);
  }

  Future<void> _initHomeScreen() async {
    await _loadViewedHistory();
    if (widget.initialPosts != null && widget.initialPosts!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _posts.addAll(widget.initialPosts!);
          _seenPostIds.addAll(widget.initialPosts!.map((post) => post.id));
          _seenVideoUrls.addAll(
            widget.initialPosts!.map((post) => post.videoUrl.split('?').first),
          );
        });
      }
      if (widget.isFeedActive) {
        _startViewTimer(_currentIndex);
      }
      final cacheManager = VideoCacheManager();
      final nextUrls = <String>[];
      for (int i = 1; i <= 6; i++) {
        if (_currentIndex + i < _posts.length) {
          nextUrls.add(_posts[_currentIndex + i].videoUrl);
        }
      }
      if (_currentIndex < _posts.length) {
        cacheManager.preloadVideos(nextUrls,
            activeUrl: _posts[_currentIndex].videoUrl);
      }
    } else {
      _loadFeed(refresh: true);
    }
  }

  Future<void> _loadViewedHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_viewedHistoryKey) ?? [];
      if (mounted) {
        setState(() {
          _viewedPostIds = list.toSet();
        });
      }
    } catch (e) {
      debugPrint('Error loading viewed history: $e');
    }
  }

  Future<void> _recordPostViewed(String postId) async {
    if (postId.isEmpty || _viewedPostIds.contains(postId)) return;

    try {
      if (mounted) {
        setState(() {
          _viewedPostIds.add(postId);
        });
      }

      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_viewedHistoryKey) ?? [];

      list.add(postId);
      if (list.length > _maxViewedHistory) {
        final removeCount = list.length - _maxViewedHistory;
        list.removeRange(0, removeCount);
      }

      await prefs.setStringList(_viewedHistoryKey, list);
    } catch (e) {
      debugPrint('Error saving viewed history: $e');
    }
  }

  void _startViewTimer(int index) {
    _viewTimer?.cancel();
    if (!widget.isFeedActive) return;
    if (index < 0 || index >= _posts.length) return;

    _viewTimer = Timer(const Duration(seconds: 1), () {
      if (index < _posts.length) {
        final postId = _posts[index].id;
        _recordPostViewed(postId);
      }
    });
  }

  String _getFeedDisplayName() {
    switch (_activeFeedType) {
      case 'front_page':
        return 'Home Feed';
      case 'popular':
        return 'Popular Feed';
      case 'subreddit':
        return 'r/${widget.query}';
      case 'custom_feed':
        return 'Custom Feed';
      case 'user':
        return 'u/${widget.query}';
      case 'saved':
        return 'Saved Posts';
      default:
        return 'Feed';
    }
  }

  Future<void> _loadFeed({bool refresh = false}) async {
    if (refresh) {
      _isLoadingMore = false;
      if (mounted) {
        setState(() {
          _isLoading = true;
          _afterToken = '';
          _allLoaded = false;
          _feedError = null;
          _posts.clear();
          _seenPostIds.clear();
          _seenVideoUrls.clear();
          _lastSubscribedSubreddits.clear();
          _currentIndex = 0;
          _loadingStatus = 'Scanning ${_getFeedDisplayName()} (page 1) — 0%...';
        });
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        });
      }
    }

    if (_allLoaded || _isLoadingMore) return;
    _isLoadingMore = true;
    final currentSession = ++_loadSession;

    final freshPosts = <PostModel>[];
    String nextAfter = _afterToken;
    String? errorMessage;
    bool exhausted = false;
    int emptyBatches = 0;
    const maxPagesToScan = 12;
    const targetPostCount = 24;
    const maxEmptyBatches = 3;

    final Map<String, int> subredditCounts = {};

    while (freshPosts.isEmpty && !exhausted && emptyBatches < maxEmptyBatches) {
      for (var attempt = 0;
          attempt < maxPagesToScan && freshPosts.length < targetPostCount;
          attempt++) {
        if (mounted && refresh) {
          final double progress =
              (freshPosts.length / targetPostCount).clamp(0.0, 1.0);
          final int percentage = (progress * 100).toInt();
          setState(() {
            _loadingStatus =
                'Scanning ${_getFeedDisplayName()} (page ${attempt + 1}) — $percentage%...';
          });
        }
        final previousAfter = nextAfter;
        final newPosts = await _api.fetchPosts(
          feedType: _activeFeedType,
          query: widget.query,
          after: nextAfter,
          sort: _activeSort,
        );

        if (currentSession != _loadSession) return;

        errorMessage = _api.lastErrorMessage;
        nextAfter = _api.lastListingAfter ?? '';

        final int maxLimitPerSubreddit =
            (targetPostCount * 0.15).round().clamp(2, 6);

        final uniquePosts = newPosts.where((post) {
          if (post.id.isEmpty) return false;
          if (_activeFeedType != 'saved' && _viewedPostIds.contains(post.id)) {
            return false;
          }

          final bool shouldApplyDiversityFilter = !_api.isLoggedIn &&
              (_activeFeedType == 'front_page' || _activeFeedType == 'popular');
          if (shouldApplyDiversityFilter) {
            final sub = post.subreddit.toLowerCase();
            final count = subredditCounts[sub] ?? 0;
            if (count >= maxLimitPerSubreddit) {
              return false;
            }
          }

          if (!_seenPostIds.add(post.id)) return false;
          final urlKey = post.videoUrl.split('?').first;
          if (!_seenVideoUrls.add(urlKey)) return false;

          if (shouldApplyDiversityFilter) {
            final sub = post.subreddit.toLowerCase();
            subredditCounts[sub] = (subredditCounts[sub] ?? 0) + 1;
          }
          return true;
        }).toList();

        freshPosts.addAll(uniquePosts);

        if (mounted && refresh) {
          final double progress =
              (freshPosts.length / targetPostCount).clamp(0.0, 1.0);
          final int percentage = (progress * 100).toInt();
          setState(() {
            _loadingStatus =
                'Found ${freshPosts.length} videos from ${_getFeedDisplayName()} — $percentage%...';
          });
        }

        if (errorMessage != null) {
          break;
        }
        if (nextAfter.isEmpty) {
          exhausted = true;
          break;
        }
        if (nextAfter == previousAfter) {
          exhausted = true;
          break;
        }
      }

      if (freshPosts.isEmpty) {
        emptyBatches++;
        if (!exhausted && emptyBatches < maxEmptyBatches) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (currentSession != _loadSession) return;
        }
      }
    }

    if (refresh && freshPosts.isNotEmpty) {
      freshPosts.shuffle();
    }

    if (currentSession != _loadSession) return;

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _feedError = errorMessage;

        if (freshPosts.isNotEmpty) {
          final wasEmpty = _posts.isEmpty;
          _posts.addAll(freshPosts);
          _afterToken = nextAfter;
          if (refresh && widget.isFeedActive) {
            _startViewTimer(0);
          }
          if (wasEmpty || refresh) {
            final cacheManager = VideoCacheManager();
            final nextUrls = <String>[];
            for (int i = 1; i <= 6; i++) {
              if (_currentIndex + i < _posts.length) {
                nextUrls.add(_posts[_currentIndex + i].videoUrl);
              }
            }
            if (_currentIndex < _posts.length) {
              cacheManager.preloadVideos(nextUrls,
                  activeUrl: _posts[_currentIndex].videoUrl);
            }
          }
        } else if (exhausted) {
          _afterToken = nextAfter;
          _allLoaded = true;
        } else {
          _afterToken = nextAfter;
        }

        if (widget.feedType == 'front_page' && _api.isLoggedIn) {
          final currentSubs = _api.cachedSubscribedSubreddits;
          if (currentSubs != null) {
            _lastSubscribedSubreddits =
                currentSubs.map((s) => s.toLowerCase()).toSet();
          }
        }
      });
      _checkRateLimitPrompt();
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    if (widget.isFeedActive) {
      _startViewTimer(index);
    }

    final cacheManager = VideoCacheManager();
    final nextUrls = <String>[];
    for (int i = 1; i <= 6; i++) {
      if (index + i < _posts.length) {
        nextUrls.add(_posts[index + i].videoUrl);
      }
    }
    if (index < _posts.length) {
      cacheManager.preloadVideos(nextUrls, activeUrl: _posts[index].videoUrl);
    }

    if (index >= _posts.length - 4) {
      _loadFeed();
    }
  }

  void _onMuteChanged(bool muted) {
    setState(() {
      _isGlobalMuted = muted;
    });
  }

  Future<void> _downloadToFile(
    String url,
    File file,
    Map<String, String> headers, {
    required void Function(int bytesDownloaded, int totalBytes)
        onProgressUpdate,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(headers);
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final sink = file.openWrite();
      int bytesDownloaded = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        bytesDownloaded += chunk.length;
        onProgressUpdate(bytesDownloaded, contentLength);
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  Future<void> _handleDownload(
      PostModel post, void Function(double) onProgress) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Starting download...')),
      );
    }

    File? tempVideoFile;
    File? tempAudioFile;
    try {
      final String cleanTitle =
          post.title.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');

      String downloadUrl = post.videoUrl;
      if (downloadUrl.contains('.m3u8') || downloadUrl.contains('/hls/')) {
        downloadUrl = post.fallbackVideoUrl;
      }

      // Append fallback parameter if it is a Reddit CDN link
      if (downloadUrl.contains('v.redd.it/') && !downloadUrl.contains('?')) {
        downloadUrl = '$downloadUrl?source=fallback';
      }

      String? audioUrl = post.audioUrl;
      if (audioUrl != null &&
          audioUrl.contains('v.redd.it/') &&
          !audioUrl.contains('?')) {
        audioUrl = '$audioUrl?source=fallback';
      }

      debugPrint('[VidditDownload] title: ${post.title}');
      debugPrint('[VidditDownload] downloadUrl: $downloadUrl');
      debugPrint('[VidditDownload] derived audioUrl: $audioUrl');

      final headers = {
        'User-Agent': RedditApi.userAgent,
      };
      bool hasAudio = false;

      if (!post.isGif && audioUrl != null && audioUrl.isNotEmpty) {
        try {
          final client = http.Client();
          final request = http.Request('GET', Uri.parse(audioUrl));
          request.headers.addAll(headers);
          final response = await client.send(request);
          debugPrint(
              '[VidditDownload] audio response code: ${response.statusCode}');
          if (response.statusCode == 200) {
            hasAudio = true;
          } else if (audioUrl.contains('CMAF_AUDIO_128.mp4')) {
            final fallbackUrl =
                audioUrl.replaceAll('CMAF_AUDIO_128.mp4', 'CMAF_AUDIO_64.mp4');
            debugPrint(
                '[VidditDownload] Trying fallback audio URL: $fallbackUrl');
            final fallbackRequest = http.Request('GET', Uri.parse(fallbackUrl));
            fallbackRequest.headers.addAll(headers);
            final fallbackResponse = await client.send(fallbackRequest);
            debugPrint(
                '[VidditDownload] fallback audio response code: ${fallbackResponse.statusCode}');
            if (fallbackResponse.statusCode == 200) {
              hasAudio = true;
              audioUrl = fallbackUrl;
            }
          }
          client.close();
        } catch (e) {
          debugPrint('[VidditDownload] Error verifying audio URL: $e');
        }
      }
      debugPrint('[VidditDownload] final hasAudio: $hasAudio');

      final tempDir = await getTemporaryDirectory();
      tempVideoFile = File('${tempDir.path}/temp_video_${post.id}.mp4');
      if (await tempVideoFile.exists()) {
        try {
          await tempVideoFile.delete();
        } catch (_) {}
      }

      if (hasAudio && audioUrl != null) {
        tempAudioFile = File('${tempDir.path}/temp_audio_${post.id}.mp4');
        if (await tempAudioFile.exists()) {
          try {
            await tempAudioFile.delete();
          } catch (_) {}
        }
      }

      int totalVideoBytes = 0;
      int totalAudioBytes = 0;
      int downloadedVideoBytes = 0;
      int downloadedAudioBytes = 0;

      void updateOverallProgress() {
        final total = totalVideoBytes + totalAudioBytes;
        if (total > 0) {
          final current = downloadedVideoBytes + downloadedAudioBytes;
          onProgress((current / total).clamp(0.0, 1.0));
        } else {
          onProgress(0.0);
        }
      }

      // 1. Download Video
      await _downloadToFile(
        downloadUrl,
        tempVideoFile,
        headers,
        onProgressUpdate: (downloaded, total) {
          downloadedVideoBytes = downloaded;
          totalVideoBytes = total;
          updateOverallProgress();
        },
      );

      // 2. Download Audio
      if (hasAudio && tempAudioFile != null && audioUrl != null) {
        await _downloadToFile(
          audioUrl,
          tempAudioFile,
          headers,
          onProgressUpdate: (downloaded, total) {
            downloadedAudioBytes = downloaded;
            totalAudioBytes = total;
            updateOverallProgress();
          },
        );
      }

      // 3. Determine save directory
      Directory? targetDirectory;
      bool wroteToPublic = false;

      if (Platform.isAndroid) {
        try {
          final publicDir = Directory('/storage/emulated/0/Download');
          if (await publicDir.exists()) {
            targetDirectory = publicDir;
            wroteToPublic = true;
          }
        } catch (_) {}
      }

      if (targetDirectory == null) {
        if (Platform.isAndroid) {
          targetDirectory = await getExternalStorageDirectory();
        } else {
          targetDirectory = await getApplicationDocumentsDirectory();
        }
      }

      if (targetDirectory == null) {
        throw Exception('Could not determine save directory');
      }

      final String finalFilePath =
          '${targetDirectory.path}/viddit_$cleanTitle.mp4';
      final File finalFile = File(finalFilePath);
      if (await finalFile.exists()) {
        try {
          await finalFile.delete();
        } catch (_) {}
      }

      bool muxedSuccessfully = false;
      if (hasAudio && tempAudioFile != null) {
        try {
          final muxedPath = await _muxVideoAudio(
            videoPath: tempVideoFile.path,
            audioPath: tempAudioFile.path,
            outputPath: finalFilePath,
          );
          if (muxedPath != null) {
            muxedSuccessfully = true;
          }
        } catch (e) {
          debugPrint('Native muxing failed: $e');
        }
      }

      if (!muxedSuccessfully) {
        // Fallback to video-only copy
        await tempVideoFile.copy(finalFilePath);
      }

      // Ensure modification date is updated to current time so it shows up at top of gallery
      try {
        await finalFile.setLastModified(DateTime.now());
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wroteToPublic
                ? 'Saved to Downloads: viddit_$cleanTitle.mp4'
                : 'Saved to App Storage: viddit_$cleanTitle.mp4'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Download Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error downloading video.')),
        );
      }
    } finally {
      // Clean up temp files
      try {
        if (tempVideoFile != null && await tempVideoFile.exists()) {
          await tempVideoFile.delete();
        }
      } catch (_) {}
      try {
        if (tempAudioFile != null && await tempAudioFile.exists()) {
          await tempAudioFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Calls the native platform to mux video and audio into a single MP4.
  Future<String?> _muxVideoAudio({
    required String videoPath,
    required String? audioPath,
    required String outputPath,
  }) async {
    const platform = MethodChannel('com.odukle.scroller/media');
    try {
      final result = await platform.invokeMethod<String>('muxVideoAudio', {
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': outputPath,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Native mux error: ${e.code} — ${e.message}');
      return null;
    }
  }

  @override
  void dispose() {
    _api.removeSafetyListener(_onSafetySettingsChanged);
    _viewTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onSafetySettingsChanged() {
    if (!mounted) return;
    if (_lastGeolocation != _api.geolocation ||
        _lastRegionOverride != _api.regionOverride) {
      _lastGeolocation = _api.geolocation;
      _lastRegionOverride = _api.regionOverride;
      _loadFeed(refresh: true);
      return;
    }
    setState(() {
      _posts.removeWhere((post) =>
          _api.isPostReported(post.id) ||
          _api.isUserBlocked(post.author) ||
          _api.isSubredditBlocked(post.subreddit));
      if (_currentIndex >= _posts.length && _posts.isNotEmpty) {
        _currentIndex = _posts.length - 1;
      }
    });
  }

  void _checkRateLimitPrompt() {
    if (!_api.isLoggedIn && _feedError != null) {
      final err = _feedError!.toLowerCase();
      if (err.contains('rate-limited') ||
          err.contains('rate limit') ||
          err.contains('429') ||
          err.contains('too many requests')) {
        _showRateLimitSignInPrompt();
      }
    }
  }

  void _showRateLimitSignInPrompt() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Guest Rate Limit Exceeded',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'You are currently browsing as a guest. Sign in to reduce guest browsing limits.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
              if (success == true && mounted) {
                _loadFeed(refresh: true);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentOrange),
            child: const Text('Sign In', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SpinKitRing(
                        color: AppTheme.accentOrange,
                        size: 60.0,
                        lineWidth: 4,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _loadingStatus,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Inter',
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                )
              : _posts.isEmpty
                  ? _buildEmptyState()
                  : Semantics(
                      identifier: 'home_video_feed',
                      child: PageView.builder(
                        scrollDirection: Axis.vertical,
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        itemCount: _posts.length,
                        itemBuilder: (context, index) {
                          return VideoPlayerWidget(
                            post: _posts[index],
                            isActive:
                                index == _currentIndex && widget.isFeedActive,
                            isGlobalMuted: _isGlobalMuted,
                            onMuteChanged: _onMuteChanged,
                            onDownload: _handleDownload,
                            hasBottomNavBar: widget.hasBottomNavBar,
                            onPostReported: () {
                              setState(() {
                                _posts.removeAt(index);
                                if (_currentIndex >= _posts.length &&
                                    _posts.isNotEmpty) {
                                  _currentIndex = _posts.length - 1;
                                }
                              });
                            },
                            onUserBlocked: (username) {
                              setState(() {
                                _posts.removeWhere((post) =>
                                    post.author.toLowerCase() ==
                                    username.toLowerCase());
                                if (_currentIndex >= _posts.length &&
                                    _posts.isNotEmpty) {
                                  _currentIndex = _posts.length - 1;
                                }
                              });
                            },
                            onSubredditBlocked: (subName) {
                              setState(() {
                                _posts.removeWhere((post) =>
                                    post.subreddit
                                        .replaceAll('r/', '')
                                        .trim()
                                        .toLowerCase() ==
                                    subName
                                        .replaceAll('r/', '')
                                        .trim()
                                        .toLowerCase());
                                if (_currentIndex >= _posts.length &&
                                    _posts.isNotEmpty) {
                                  _currentIndex = _posts.length - 1;
                                }
                              });
                            },
                            onSubredditTap: () async {
                              final res = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SubredditScreen(
                                    subredditName: _posts[index].subreddit,
                                  ),
                                ),
                              );
                              _syncFeedOnSubscriptionChange();
                              return res;
                            },
                            onAuthorTap: () async {
                              final res = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SubredditScreen(
                                    subredditName: _posts[index].author,
                                    isUser: true,
                                  ),
                                ),
                              );
                              _syncFeedOnSubscriptionChange();
                              return res;
                            },
                          );
                        },
                      ),
                    ),
          if (widget.initialPosts != null ||
              widget.feedType == 'subreddit' ||
              widget.feedType == 'custom_feed')
            Positioned(
              top: 50,
              left: 16,
              child: PressableScale(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12, width: 0.8),
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          if (_isLoadingMore)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SpinKitRing(
                        color: AppTheme.accentOrange,
                        size: 16,
                        lineWidth: 2,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Loading more...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _feedError == null
                ? Icons.movie_filter_outlined
                : Icons.cloud_off_rounded,
            color: Colors.white24,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            _feedError ?? 'No videos found in this feed.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentOrange),
            onPressed: () => _loadFeed(refresh: true),
            child: Text(_feedError == null ? 'Refresh Feed' : 'Retry Request'),
          ),
        ],
      ),
    );
  }
}
