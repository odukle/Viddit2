import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:share_plus/share_plus.dart';
import '../models/post_model.dart';
import '../api/reddit_api.dart';
import '../api/video_cache_manager.dart';
import '../theme/app_theme.dart';
import 'comments_sheet.dart';
import 'pressable_scale.dart';

class VideoPlayerWidget extends StatefulWidget {
  final PostModel post;
  final bool isActive;
  final bool isGlobalMuted;
  final ValueChanged<bool> onMuteChanged;
  final Function() onSubredditTap;
  final Function() onAuthorTap;
  final Function(PostModel, void Function(double)) onDownload;
  final bool hasBottomNavBar;
  final VoidCallback? onPostReported;
  final ValueChanged<String>? onUserBlocked;
  final ValueChanged<String>? onSubredditBlocked;

  const VideoPlayerWidget({
    super.key,
    required this.post,
    required this.isActive,
    required this.isGlobalMuted,
    required this.onMuteChanged,
    required this.onSubredditTap,
    required this.onAuthorTap,
    required this.onDownload,
    this.hasBottomNavBar = false,
    this.onPostReported,
    this.onUserBlocked,
    this.onSubredditBlocked,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showPlayPauseIcon = false;
  bool _isPlaying = false;
  bool _showUpvoteHeart = false;
  bool _isNsfwBlocked = true;
  bool _isTitleExpanded = false;
  String _subredditIcon = '';
  String _authorIcon = '';
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  double _loadingProgress = 0.0;
  bool _isListeningToProgress = false;
  bool _isSwitchingToCache = false;
  bool _isAppInForeground = true;
  bool _isRevealed = false;
  bool _isFastForwarding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isAppInForeground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _isNsfwBlocked = widget.post.isNsfw;
    _loadIcons();
    RedditApi().addSafetyListener(_onSafetyChanged);
    if (widget.isActive) {
      _initializePlayer();
    }
  }

  void _onSafetyChanged() {
    if (mounted) {
      setState(() {
        if (_isSafetyBlocked && !_isRevealed) {
          _pausePlayer();
        }
      });
    }
  }

  bool get _isSafetyBlocked {
    final api = RedditApi();
    return api.isPostReported(widget.post.id) ||
        api.isUserBlocked(widget.post.author) ||
        api.isSubredditBlocked(widget.post.subreddit);
  }

  String _getSafetyBlockedReason() {
    final api = RedditApi();
    if (api.isPostReported(widget.post.id)) {
      return 'You reported this post.';
    }
    if (api.isUserBlocked(widget.post.author)) {
      return 'You blocked u/${widget.post.author}.';
    }
    if (api.isSubredditBlocked(widget.post.subreddit)) {
      return 'You blocked ${widget.post.subreddit}.';
    }
    return 'This content is blocked or reported.';
  }

  void _revealSafetyBlocked() {
    setState(() {
      _isRevealed = true;
    });
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _initializePlayer();
    } else if (!widget.isActive && oldWidget.isActive) {
      _pausePlayer();
    }

    if (_isInitialized && _controller != null) {
      if (widget.isGlobalMuted != oldWidget.isGlobalMuted) {
        _controller!.setVolume(widget.isGlobalMuted ? 0.0 : 1.0);
      }
    }
  }

  Future<void> _loadIcons() async {
    final api = RedditApi();

    // Asynchronously load subreddit icon
    api.fetchSubredditAbout(widget.post.subreddit).then((sub) {
      if (mounted && sub.iconImage.isNotEmpty) {
        setState(() {
          _subredditIcon = sub.iconImage;
        });
      }
    });

    // Asynchronously load author icon
    api.fetchUserAbout(widget.post.author).then((data) {
      if (mounted && data['icon_img'] != null) {
        setState(() {
          _authorIcon = data['icon_img'].toString().replaceAll('amp;', '');
        });
      }
    });
  }

  void _onDownloadProgress(double progress) {
    if (mounted) {
      setState(() {
        _loadingProgress = progress;
      });
      if (progress >= 1.0 && !_isInitialized && !_hasError) {
        _switchToCachedPlayer();
      }
    }
  }

  void _cleanupProgressListener() {
    if (_isListeningToProgress) {
      VideoCacheManager()
          .removeProgressListener(widget.post.videoUrl, _onDownloadProgress);
      _isListeningToProgress = false;
    }
  }

  Future<void> _switchToCachedPlayer() async {
    if (_isSwitchingToCache || _isInitialized) {
      return;
    }
    _isSwitchingToCache = true;

    try {
      final cacheManager = VideoCacheManager();
      final hlsUrl = widget.post.videoUrl;

      final cachedProxyUrl = await cacheManager.getCacheOrDownload(hlsUrl);
      if (cachedProxyUrl != null) {
        debugPrint(
            '[VideoPlayerWidget] Switching to cached URL: $cachedProxyUrl');

        final oldController = _controller;
        _controller = null;
        if (oldController != null) {
          await oldController.dispose();
        }

        final api = RedditApi();
        final headers = await api.getDownloadHeaders();

        final controller = VideoPlayerController.networkUrl(
          Uri.parse(cachedProxyUrl),
          httpHeaders: headers,
        );
        _controller = controller;

        await controller.initialize();
        _cleanupProgressListener();
        if (!mounted) return;

        await controller.setLooping(true);
        await controller.setVolume(widget.isGlobalMuted ? 0.0 : 1.0);

        setState(() {
          _isInitialized = true;
          _hasError = false;
        });

        if (widget.isActive && !_isNsfwBlocked) {
          _playPlayer();
        }
      }
    } catch (e) {
      debugPrint('[VideoPlayerWidget] Error switching to cached player: $e');
    } finally {
      _isSwitchingToCache = false;
    }
  }

  Future<void> _initializePlayer() async {
    if (_isInitialized) {
      _playPlayer();
      return;
    }

    try {
      final cacheManager = VideoCacheManager();
      final hlsUrl = widget.post.videoUrl;

      setState(() {
        _loadingProgress = 0.0;
      });

      if (hlsUrl.contains('v.redd.it/')) {
        _isListeningToProgress = true;
        cacheManager.addProgressListener(hlsUrl, _onDownloadProgress);
      }

      // Try to get a cached (local-proxy) URL; falls back to network HLS.
      final cachedProxyUrl = await cacheManager.getCacheOrDownload(hlsUrl);
      final playUrl = cachedProxyUrl ?? hlsUrl;

      final api = RedditApi();
      final headers = await api.getDownloadHeaders();

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(playUrl),
        httpHeaders: headers,
      );
      _controller = controller;

      await controller.initialize();
      _cleanupProgressListener();
      if (!mounted) return;

      await controller.setLooping(true);
      await controller.setVolume(widget.isGlobalMuted ? 0.0 : 1.0);

      setState(() {
        _isInitialized = true;
        _hasError = false;
      });

      if (widget.isActive && !_isNsfwBlocked && _isAppInForeground) {
        _playPlayer();
      }
    } catch (e) {
      _cleanupProgressListener();
      debugPrint('Video Initialize Error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
        });
      }
    }
  }

  void _playPlayer() {
    if (_controller != null && !_isPlaying) {
      if (_isSafetyBlocked && !_isRevealed) return;
      _controller!.play();
      setState(() {
        _isPlaying = true;
      });
    }
  }

  void _pausePlayer() {
    if (_controller != null && _isPlaying) {
      _controller!.pause();
      setState(() {
        _isPlaying = false;
      });
    }
  }

  void _togglePlayPause() {
    if (!_isInitialized || _controller == null) return;

    if (_isPlaying) {
      _pausePlayer();
    } else {
      _playPlayer();
    }

    setState(() {
      _showPlayPauseIcon = true;
    });

    Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _showPlayPauseIcon = false;
        });
      }
    });
  }

  void _onDoubleTap() {
    if (widget.post.userVote != 1) {
      _vote(1);
    }
    setState(() {
      _showUpvoteHeart = true;
    });

    Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _showUpvoteHeart = false;
        });
      }
    });
  }

  Future<void> _vote(int direction) async {
    final api = RedditApi();
    if (!api.isLoggedIn) {
      _showSignInRequired();
      return;
    }

    final originalVote = widget.post.userVote;
    final newVote = originalVote == direction ? 0 : direction;

    setState(() {
      widget.post.userVote = newVote;
    });

    final success = await api.vote(widget.post.fullName, newVote);
    if (!success && mounted) {
      setState(() {
        widget.post.userVote = originalVote;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to cast vote.')),
      );
    }
  }

  void _showSafetyOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.flag_rounded, color: AppTheme.accentOrange),
                title: const Text('Report Post',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(
                    'Report this post for UGC violation, spam, or abuse',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _showReportReasonDialog();
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.block_rounded, color: AppTheme.accentPurple),
                title: Text('Block u/${widget.post.author}',
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                    'You won\'t see posts or comments from this user again',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _blockUserConfirm();
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.no_accounts_rounded, color: AppTheme.accentWarm),
                title: Text('Block ${widget.post.subreddit}',
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text('You won\'t see posts from this subreddit again',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _blockSubredditConfirm();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showReportReasonDialog() {
    final reasons = [
      'Spam',
      'Harassment or Abuse',
      'Inappropriate/Explicit Content',
      'Misinformation',
      'Other'
    ];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Report Post', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: reasons.map((reason) {
            return ListTile(
              title: Text(reason,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () async {
                Navigator.pop(context);
                _submitReport(reason);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _submitReport(String reason) async {
    final api = RedditApi();
    await api.reportPostLocal(widget.post.id);

    if (api.isLoggedIn) {
      await api.reportThing(widget.post.fullName, reason);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Post reported. Thank you for making Scroller safe!')),
      );
      if (widget.onPostReported != null) {
        widget.onPostReported!();
      }
    }
  }

  void _blockUserConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Block u/${widget.post.author}?',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to block this user? You will not see their posts or comments again.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _submitBlock();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPurple),
            child: const Text('Block', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitBlock() async {
    final api = RedditApi();
    await api.blockUserLocal(widget.post.author);

    if (api.isLoggedIn) {
      await api.blockUser(widget.post.author);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Blocked u/${widget.post.author}')),
      );
      if (widget.onUserBlocked != null) {
        widget.onUserBlocked!(widget.post.author);
      }
    }
  }

  void _blockSubredditConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Block ${widget.post.subreddit}?',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to block this subreddit? You will not see posts from this subreddit again.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _submitSubredditBlock();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentOrange),
            child: const Text('Block', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitSubredditBlock() async {
    final api = RedditApi();
    await api.blockSubredditLocal(widget.post.subreddit);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Blocked ${widget.post.subreddit}')),
      );
      if (widget.onSubredditBlocked != null) {
        widget.onSubredditBlocked!(widget.post.subreddit);
      }
    }
  }

  void _showSignInRequired() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign In Required'),
        content: const Text('Please sign in to vote and interact with posts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Handle login navigation
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  void _openComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentsSheet(post: widget.post),
    );
  }

  void _startDownload() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      await widget.onDownload(widget.post, (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
          });
        }
      });
    } catch (e) {
      debugPrint('Error starting download: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  void _onLongPressStart(LongPressStartDetails details) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final posX = details.localPosition.dx;

    if (posX < screenWidth * 0.35 || posX > screenWidth * 0.65) {
      // Fast-forward zone (Left or Right 35%)
      if (_controller != null && _isInitialized) {
        HapticFeedback.selectionClick();
        await _controller!.setPlaybackSpeed(2.0);
        setState(() {
          _isFastForwarding = true;
        });
      }
    } else {
      // Middle 30% -> Quick Actions Menu
      _showQuickActionsMenu();
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) async {
    if (_isFastForwarding) {
      if (_controller != null && _isInitialized) {
        await _controller!.setPlaybackSpeed(1.0);
      }
      setState(() {
        _isFastForwarding = false;
      });
    }
  }

  void _showQuickActionsMenu() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) {
        final api = RedditApi();
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
            border: Border(
                top: BorderSide(color: AppTheme.glassBorder, width: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Quick Actions',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 16),

              // 1. Save/Unsave Post
              _buildQuickActionTile(
                icon: widget.post.isSaved
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                label: widget.post.isSaved ? 'Unsave Post' : 'Save Post',
                color: widget.post.isSaved ? Colors.amber : Colors.white,
                onTap: () async {
                  Navigator.pop(context);
                  if (!api.isLoggedIn) {
                    _showSignInRequired();
                    return;
                  }
                  final bool newSavedState = !widget.post.isSaved;
                  setState(() {
                    widget.post.isSaved = newSavedState;
                  });
                  final success =
                      await api.savePost(widget.post.fullName, newSavedState);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success
                            ? (newSavedState
                                ? 'Saved post successfully! ⭐'
                                : 'Unsaved post! ⭐')
                            : 'Failed to update save state.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),

              // 2. Copy Link
              _buildQuickActionTile(
                icon: Icons.link_rounded,
                label: 'Copy Post Link',
                color: Colors.white,
                onTap: () async {
                  Navigator.pop(context);
                  await Clipboard.setData(ClipboardData(
                      text: 'https://www.reddit.com${widget.post.permalink}'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied link to clipboard! 🔗'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),

              // 3. Download Video
              _buildQuickActionTile(
                icon: Icons.download_rounded,
                label: 'Download Video',
                color: Colors.white,
                onTap: () {
                  Navigator.pop(context);
                  _startDownload();
                },
              ),

              // Divider
              Divider(color: AppTheme.glassBorder, height: 16),

              // 4. Report Post
              _buildQuickActionTile(
                icon: Icons.flag_outlined,
                label: 'Report Post',
                color: Colors.redAccent,
                onTap: () {
                  Navigator.pop(context);
                  _showReportReasonDialog();
                },
              ),

              // 5. Block User
              _buildQuickActionTile(
                icon: Icons.person_off_outlined,
                label: 'Block u/${widget.post.author}',
                color: Colors.redAccent,
                onTap: () {
                  Navigator.pop(context);
                  _blockUserConfirm();
                },
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.glassBorder, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 16),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                color: AppTheme.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    RedditApi().removeSafetyListener(_onSafetyChanged);
    WidgetsBinding.instance.removeObserver(this);
    _cleanupProgressListener();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _isAppInForeground = false;
      _pausePlayer();
    } else if (state == AppLifecycleState.resumed) {
      _isAppInForeground = true;
      if (widget.isActive && _isInitialized && !_isNsfwBlocked) {
        _playPlayer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    // Bottom nav bar is full-width: height is 60.0 + bottomInset
    final double actualBottomPadding = bottomInset;

    return GestureDetector(
      onTap: _togglePlayPause,
      onDoubleTap: _onDoubleTap,
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Media Container
          Container(
            color: Colors.black,
            child: _isInitialized && _controller != null
                ? Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                : _hasError
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.redAccent, size: 48),
                            SizedBox(height: 12),
                            Text('Error playing video',
                                style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SpinKitRing(
                              color:
                                  AppTheme.accentOrange.withValues(alpha: 0.8),
                              size: 44.0,
                              lineWidth: 2.5,
                            ),
                            if (widget.post.videoUrl
                                .contains('v.redd.it/')) ...[
                              const SizedBox(height: 12),
                              Text(
                                '${(_loadingProgress * 100).toInt()}%',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
          ),

          // 2. Play/Pause Overlay Animation Indicator
          if (_showPlayPauseIcon)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 1.3, end: 1.0),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              builder: (context, scale, child) {
                return AnimatedOpacity(
                  opacity: _showPlayPauseIcon ? 0.9 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 0.5),
                      ),
                      child: Icon(
                        _isPlaying
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
                );
              },
            ),

          // 3. Double-tap upvote heart animation
          if (_showUpvoteHeart)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1.2),
              duration: const Duration(milliseconds: 350),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentOrange.withValues(alpha: 0.4),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.favorite_rounded,
                      color: AppTheme.accentOrange,
                      size: 120,
                    ),
                  ),
                );
              },
            ),

          // 4. Muted Indicator Overlay
          if (widget.isGlobalMuted)
            Positioned(
              top: 44,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volume_off_rounded,
                        color: Colors.white.withValues(alpha: 0.8), size: 12),
                    const SizedBox(width: 3),
                    Text('MUTED',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.8),
                            letterSpacing: 0.5)),
                  ],
                ),
              ),
            ),

          // 5. NSFW Adult Block Filter
          if (_isNsfwBlocked)
            Positioned.fill(
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.5),
                                width: 1.5),
                          ),
                          child: const Icon(Icons.warning_amber_rounded,
                              color: Colors.redAccent, size: 48),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'NSFW CONTENT',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'This video contains sensitive or adult materials.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 36),
                        if (RedditApi.showNsfwSwitch) ...[
                          PressableScale(
                            onTap: () {
                              setState(() {
                                _isNsfwBlocked = false;
                              });
                              _initializePlayer();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 36, vertical: 14),
                              decoration: BoxDecoration(
                                gradient: AppTheme.brandGradient,
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.accentOrange
                                        .withValues(alpha: 0.3),
                                    blurRadius: 15,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Watch Anyway',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                            ),
                          ),
                        ] else ...[
                          const Text(
                            'NSFW content is restricted on this device.',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 5.5 Safety Block Filter
          if (_isSafetyBlocked && !_isRevealed)
            Positioned.fill(
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.65),
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.accentOrange.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.accentOrange
                                    .withValues(alpha: 0.5),
                                width: 1.5),
                          ),
                          child: Icon(Icons.shield_rounded,
                              color: AppTheme.accentOrange, size: 48),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'CONTENT HIDDEN',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _getSafetyBlockedReason(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 36),
                        PressableScale(
                          onTap: _revealSafetyBlocked,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 36, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: AppTheme.brandGradient,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentOrange
                                      .withValues(alpha: 0.3),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Text(
                              'Show Post',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 6. Left side Details overlay (Title, Subreddit, user)
          if (!_isNsfwBlocked && !(_isSafetyBlocked && !_isRevealed))
            Positioned(
              left: 0,
              bottom: actualBottomPadding,
              right: 0, // Leave space for side tray buttons
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.6, 1.0],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Subreddit Capsule
                    GestureDetector(
                      onTap: () async {
                        _pausePlayer();
                        final res = widget.onSubredditTap();
                        if (res is Future) {
                          await res;
                        }
                        if (mounted && widget.isActive) {
                          _playPlayer();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusFull),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06),
                              width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.white10,
                              backgroundImage: _subredditIcon.isNotEmpty
                                  ? CachedNetworkImageProvider(_subredditIcon)
                                  : null,
                              child: _subredditIcon.isEmpty
                                  ? Icon(Icons.reddit,
                                      color: AppTheme.accentOrange, size: 14)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'r/${widget.post.subreddit}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Author Details Row
                    GestureDetector(
                      onTap: () async {
                        _pausePlayer();
                        final res = widget.onAuthorTap();
                        if (res is Future) {
                          await res;
                        }
                        if (mounted && widget.isActive) {
                          _playPlayer();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 8,
                              backgroundColor: Colors.white10,
                              backgroundImage: _authorIcon.isNotEmpty
                                  ? CachedNetworkImageProvider(_authorIcon)
                                  : null,
                              child: _authorIcon.isEmpty
                                  ? const Icon(Icons.person,
                                      color: Colors.white70, size: 8)
                                  : null,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'u/${widget.post.author}',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Collapsible Post Title
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isTitleExpanded = !_isTitleExpanded;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(
                            left: 4, right: 60), // Leave space for side buttons
                        child: AnimatedCrossFade(
                          firstChild: Text(
                            widget.post.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Colors.white.withValues(alpha: 0.95),
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          secondChild: Text(
                            widget.post.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Colors.white.withValues(alpha: 0.95),
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          crossFadeState: _isTitleExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 200),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 7. Right side controls tray (Upvote, comment, download, share, mute)
          if (!_isNsfwBlocked && !(_isSafetyBlocked && !_isRevealed))
            Positioned(
              right: 12,
              bottom: 8 + actualBottomPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Upvote button
                  _buildSideButton(
                    icon: widget.post.userVote == 1
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_upward_outlined,
                    label: widget.post.score.toString(),
                    color: widget.post.userVote == 1
                        ? AppTheme.accentOrange
                        : Colors.white,
                    onTap: () => _vote(1),
                  ),
                  const SizedBox(height: 16),

                  // Comments button
                  _buildSideButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: widget.post.commentCount.toString(),
                    color: Colors.white,
                    onTap: _openComments,
                  ),
                  const SizedBox(height: 16),

                  // Download button
                  _buildSideButton(
                    icon: Icons.download_rounded,
                    label: _isDownloading
                        ? '${(_downloadProgress * 100).toInt()}%'
                        : 'Save',
                    color: Colors.white,
                    iconWidget: _isDownloading
                        ? Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: CircularProgressIndicator(
                              value: _downloadProgress,
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.accentOrange),
                              backgroundColor: Colors.white24,
                            ),
                          )
                        : null,
                    onTap: _startDownload,
                  ),
                  const SizedBox(height: 16),

                  // Share button
                  _buildSideButton(
                    icon: Icons.share_rounded,
                    label: 'Share',
                    color: Colors.white,
                    onTap: () {
                      final url =
                          'https://www.reddit.com${widget.post.permalink}';
                      const extra = '\n\nShared via Scroller';
                      Share.share('$url$extra');
                    },
                  ),
                  const SizedBox(height: 16),

                  // Safety button (Report / Block)
                  _buildSideButton(
                    icon: Icons.shield_outlined,
                    label: 'Safety',
                    color: Colors.white,
                    onTap: _showSafetyOptions,
                  ),
                  const SizedBox(height: 16),

                  // Mute Toggle Button
                  _buildSideButton(
                    icon: widget.isGlobalMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    label: widget.isGlobalMuted ? 'Muted' : 'Sound',
                    color: widget.isGlobalMuted
                        ? AppTheme.accentOrange
                        : Colors.white,
                    onTap: () {
                      widget.onMuteChanged(!widget.isGlobalMuted);
                    },
                  ),
                ],
              ),
            ),

          // 8. Progress Seeking Bar overlay at the bottom
          if (_isInitialized &&
              _controller != null &&
              !_isNsfwBlocked &&
              !(_isSafetyBlocked && !_isRevealed))
            Positioned(
              bottom: actualBottomPadding,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: AppTheme.accentOrange,
                  bufferedColor: Colors.white.withValues(alpha: 0.18),
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),

          // 9. Fast Forwarding indicator overlay at the top center
          if (_isFastForwarding)
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  border: Border.all(color: AppTheme.glassBorder, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fast_forward_rounded,
                        color: AppTheme.accentOrange, size: 18),
                    SizedBox(width: 8),
                    Text(
                      '2x Speed',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSideButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    Widget? iconWidget,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Column(
        children: [
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: iconWidget ?? Icon(icon, color: color, size: 22),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.9),
                letterSpacing: 0.1),
          ),
        ],
      ),
    );
  }
}
