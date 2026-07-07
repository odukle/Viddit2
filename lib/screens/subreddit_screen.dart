import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/reddit_api.dart';
import '../models/subreddit_model.dart';
import '../models/post_model.dart';
import '../models/multireddit_model.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import '../widgets/pressable_scale.dart';

class SubredditScreen extends StatefulWidget {
  final String subredditName;
  final bool isUser;
  final bool isSaved;
  final String? customTitle;

  const SubredditScreen({
    super.key,
    required this.subredditName,
    this.isUser = false,
    this.isSaved = false,
    this.customTitle,
  });

  @override
  State<SubredditScreen> createState() => _SubredditScreenState();
}

class _SubredditScreenState extends State<SubredditScreen> {
  final RedditApi _api = RedditApi();
  final ScrollController _scrollController = ScrollController();

  SubredditModel? _subreddit;
  Map<String, dynamic>? _userAbout;
  final List<PostModel> _posts = [];

  bool _isLoadingPosts = false;
  bool _isLoadingMore = false;
  bool _allLoaded = false;
  String _afterToken = '';
  String? _postsError;
  final Set<String> _seenPostIds = {};

  String _sort = 'hot';
  String _time = 'day';
  bool _showTimeSelector = false;
  bool _isSubscribing = false;

  Future<void> _toggleSubscription() async {
    if (_subreddit == null || _isSubscribing) return;

    setState(() {
      _isSubscribing = true;
    });

    final currentSubscribed = _subreddit!.userIsSubscriber ?? false;
    final success = await _api.subscribeSubreddit(
        _subreddit!.displayNamePrefixed, !currentSubscribed);

    if (mounted) {
      if (success) {
        setState(() {
          _subreddit = SubredditModel(
            title: _subreddit!.title,
            displayNamePrefixed: _subreddit!.displayNamePrefixed,
            description: _subreddit!.description,
            headerImage: _subreddit!.headerImage,
            iconImage: _subreddit!.iconImage,
            bannerImage: _subreddit!.bannerImage,
            subscribers: _subreddit!.subscribers,
            fullDescription: _subreddit!.fullDescription,
            userIsSubscriber: !currentSubscribed,
          );
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentSubscribed
                ? 'Failed to leave subreddit.'
                : 'Failed to join subreddit.'),
          ),
        );
      }
      setState(() {
        _isSubscribing = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _loadAbout();
    _loadPosts(refresh: true);
    _api.addSafetyListener(_onSafetySettingsChanged);
    if (_api.isLoggedIn) {
      _api.fetchCustomFeeds().then((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  Future<void> _loadAbout() async {
    if (widget.isSaved) return;
    if (widget.isUser) {
      final data = await _api.fetchUserAbout(widget.subredditName);
      if (mounted) {
        setState(() {
          _userAbout = data;
        });
      }
    } else {
      final sub = await _api.fetchSubredditAbout(widget.subredditName);
      if (mounted) {
        setState(() {
          _subreddit = sub;
        });
      }
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isLoadingPosts = true;
        _posts.clear();
        _afterToken = '';
        _allLoaded = false;
        _postsError = null;
        _seenPostIds.clear();
      });
    }

    if (_allLoaded || _isLoadingMore) return;
    _isLoadingMore = true;

    final freshPosts = <PostModel>[];
    String nextAfter = _afterToken;
    String? errorMessage;
    bool exhausted = false;
    const maxPagesToScan = 12;

    for (var attempt = 0; attempt < maxPagesToScan; attempt++) {
      final previousAfter = nextAfter;
      final newPosts = await _api.fetchPosts(
        feedType:
            widget.isSaved ? 'saved' : (widget.isUser ? 'user' : 'subreddit'),
        query: widget.subredditName,
        sort: _sort,
        time: _time,
        after: nextAfter,
      );

      errorMessage = _api.lastErrorMessage;
      nextAfter = _api.lastListingAfter ?? '';

      final uniquePosts = newPosts
          .where((post) => post.id.isNotEmpty && _seenPostIds.add(post.id))
          .toList();

      if (uniquePosts.isNotEmpty) {
        freshPosts.addAll(uniquePosts);
        break;
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

    if (mounted) {
      setState(() {
        _isLoadingPosts = false;
        _isLoadingMore = false;
        _postsError = errorMessage;

        if (freshPosts.isNotEmpty) {
          _posts.addAll(freshPosts);
          _afterToken = nextAfter;
        } else if (exhausted || nextAfter.isEmpty) {
          _afterToken = nextAfter;
          _allLoaded = true;
        } else {
          _afterToken = nextAfter;
        }
      });
      _checkRateLimitPrompt();
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadPosts();
    }
  }

  void _changeSort(String sort) {
    setState(() {
      _sort = sort;
      _showTimeSelector = sort == 'top';
    });
    _loadPosts(refresh: true);
  }

  void _changeTime(String time) {
    setState(() {
      _time = time;
    });
    _loadPosts(refresh: true);
  }

  String _formatSubscribers(String subs) {
    final count = int.tryParse(subs) ?? 0;
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return subs;
  }

  void _showAddCustomFeedSheet() {
    final TextEditingController newFeedController = TextEditingController();
    bool isCreating = false;
    Future<List<MultiRedditModel>> customFeedsFuture = _api.fetchCustomFeeds();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28), topRight: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                20,
                16,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: FutureBuilder<List<MultiRedditModel>>(
                future: customFeedsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SizedBox(
                      height: 220,
                      child: Center(
                        child: SpinKitRing(
                          color: AppTheme.accentOrange.withValues(alpha: 0.8),
                          size: 40,
                          lineWidth: 2.5,
                        ),
                      ),
                    );
                  }

                  final feeds = snapshot.data ?? [];

                  Widget buildCreateForm() {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        TextField(
                          controller: newFeedController,
                          autofocus: true,
                          style: TextStyle(color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Feed Name (e.g. My Gifs)',
                            hintStyle: TextStyle(color: AppTheme.textMuted),
                            filled: true,
                            fillColor: AppTheme.surfaceLight,
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                              borderSide:
                                  BorderSide(color: AppTheme.glassBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                              borderSide:
                                  BorderSide(color: AppTheme.accentOrange),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentOrange,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                            ),
                          ),
                          onPressed: isCreating
                              ? null
                              : () async {
                                  final name = newFeedController.text.trim();
                                  if (name.isEmpty) return;

                                  final specialChars = RegExp(
                                      r'''[~`!@#\$%^&*()_\-+=|\\{}\[\]:;"'<>,.?/₹]''');
                                  if (specialChars.hasMatch(name)) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Special characters are not allowed.')),
                                    );
                                    return;
                                  }

                                  setModalState(() {
                                    isCreating = true;
                                  });

                                  final newFeed =
                                      await _api.createCustomFeed(name);
                                  if (newFeed != null) {
                                    final success =
                                        await _api.addSubredditToCustomFeed(
                                            newFeed.name, widget.subredditName);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            success
                                                ? 'Feed "$name" created & r/${widget.subredditName} added! 🎉'
                                                : 'Feed created but failed to add subreddit.',
                                          ),
                                        ),
                                      );
                                    }
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                    }
                                    if (mounted) {
                                      setState(() {});
                                    }
                                  } else {
                                    setModalState(() {
                                      isCreating = false;
                                    });
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Failed to create feed.')),
                                      );
                                    }
                                  }
                                },
                          child: isCreating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text('Create and Add Subreddit',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ],
                    );
                  }

                  if (feeds.isEmpty) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.accentOrange.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Text(
                          'Create a Custom Feed',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You do not have any custom feeds yet. Create one inline to add this subreddit.',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12.5),
                        ),
                        const SizedBox(height: 16),
                        buildCreateForm(),
                      ],
                    );
                  }

                  return SizedBox(
                    height: MediaQuery.of(context).size.height * 0.55,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.accentOrange.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Add to Custom Feed',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            TextButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Create Custom Feed'),
                                    content: TextField(
                                      controller: newFeedController,
                                      autofocus: true,
                                      style: TextStyle(
                                          color: AppTheme.textPrimary),
                                      decoration: InputDecoration(
                                        hintText: 'Feed Name (e.g. My Gifs)',
                                        hintStyle: TextStyle(
                                            color: AppTheme.textMuted),
                                        filled: true,
                                        fillColor: AppTheme.surfaceLight,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppTheme.radiusMd),
                                          borderSide: BorderSide(
                                              color: AppTheme.glassBorder),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppTheme.radiusMd),
                                          borderSide: BorderSide(
                                              color: AppTheme.accentOrange),
                                        ),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          newFeedController.clear();
                                          Navigator.pop(ctx);
                                        },
                                        child: Text('Cancel',
                                            style: TextStyle(
                                                color: AppTheme.textSecondary)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                AppTheme.accentOrange),
                                        onPressed: () async {
                                          final name =
                                              newFeedController.text.trim();
                                          if (name.isEmpty) return;

                                          Navigator.pop(ctx);
                                          setModalState(() {
                                            customFeedsFuture =
                                                _api.fetchCustomFeeds();
                                          });

                                          final newFeed =
                                              await _api.createCustomFeed(name);
                                          newFeedController.clear();

                                          if (newFeed != null) {
                                            await _api.addSubredditToCustomFeed(
                                                newFeed.name,
                                                widget.subredditName);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Feed "$name" created & r/${widget.subredditName} added! 🎉',
                                                  ),
                                                ),
                                              );
                                            }
                                            if (context.mounted) {
                                              Navigator.pop(context);
                                            }
                                            if (mounted) {
                                              setState(() {});
                                            }
                                          } else {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        'Failed to create feed.')),
                                              );
                                            }
                                          }
                                        },
                                        child: const Text('Create & Add'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              icon: Icon(Icons.add_rounded,
                                  size: 16, color: AppTheme.accentOrange),
                              label: Text(
                                'Create New',
                                style: TextStyle(
                                    color: AppTheme.accentOrange,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.builder(
                            itemCount: feeds.length,
                            itemBuilder: (context, index) {
                              final feed = feeds[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: PressableScale(
                                  onTap: () async {
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    Navigator.pop(context);
                                    final success =
                                        await _api.addSubredditToCustomFeed(
                                            feed.name, widget.subredditName);
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            success
                                                ? 'Added to ${feed.displayName} successfully! 🎉'
                                                : 'Failed to add to feed.',
                                          ),
                                        ),
                                      );
                                      setState(() {});
                                    }
                                  },
                                  child: Container(
                                    decoration:
                                        AppTheme.glassDecoration(opacity: 0.04),
                                    child: ListTile(
                                      title: Text(feed.displayName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall),
                                      leading: const Icon(Icons.star_rounded,
                                          color: Colors.amber, size: 22),
                                      trailing: Icon(
                                          Icons.add_circle_outline_rounded,
                                          color: AppTheme.accentOrange,
                                          size: 22),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _api.removeSafetyListener(_onSafetySettingsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSafetySettingsChanged() {
    if (!mounted) return;
    setState(() {
      _posts.removeWhere((post) =>
          _api.isPostReported(post.id) ||
          _api.isUserBlocked(post.author) ||
          _api.isSubredditBlocked(post.subreddit));
    });
  }

  void _checkRateLimitPrompt() {
    if (!_api.isLoggedIn &&
        _postsError != null &&
        _postsError!.toLowerCase().contains('rate-limited')) {
      _showRateLimitSignInPrompt();
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
                _loadPosts(refresh: true);
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
    final title = widget.customTitle ??
        (widget.isSaved
            ? 'Saved Posts'
            : (widget.isUser
                ? 'u/${widget.subredditName}'
                : 'r/${widget.subredditName}'));
    final String subIcon = widget.isSaved
        ? ''
        : (widget.isUser
            ? (_userAbout?['icon_img'] ?? '').replaceAll('amp;', '')
            : (_subreddit?.iconImage ?? ''));
    final String banner = (widget.isUser || widget.isSaved)
        ? ''
        : (_subreddit?.bannerImage ?? '');
    final String subscribers = (widget.isUser || widget.isSaved)
        ? ''
        : _formatSubscribers(_subreddit?.subscribers ?? '0');
    final String description = widget.isSaved
        ? 'View all video posts you saved'
        : (widget.customTitle != null
            ? 'Curated category feed for ${widget.customTitle}'
            : (widget.isUser
                ? 'User submissions feed'
                : (_subreddit?.description ?? '')));

    return Scaffold(
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // Sliver Header
            SliverAppBar(
              expandedHeight: (widget.isUser || widget.isSaved) ? 180 : 260,
              floating: false,
              pinned: true,
              backgroundColor: AppTheme.surface,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    shadows: [
                      Shadow(
                          color: Colors.black87,
                          blurRadius: 8,
                          offset: Offset(0, 2))
                    ],
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Banner Image
                    banner.isNotEmpty && banner != 'null'
                        ? CachedNetworkImage(
                            imageUrl: banner,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                Container(color: AppTheme.surfaceLight),
                          )
                        : Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF1F1C2C), Color(0xFF928DAB)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                    // 3-stop gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.25),
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),

                    // About details overlay
                    Positioned(
                      bottom: 48,
                      left: 16,
                      right: 16,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Avatar with gradient ring
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppTheme.warmGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentOrange
                                      .withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 34,
                              backgroundColor: AppTheme.surface,
                              backgroundImage: widget.isSaved
                                  ? null
                                  : (subIcon.isNotEmpty && subIcon != 'null'
                                      ? CachedNetworkImageProvider(subIcon)
                                      : null),
                              child: widget.isSaved
                                  ? const Icon(Icons.star_rounded,
                                      color: Colors.amber, size: 36)
                                  : (subIcon.isEmpty || subIcon == 'null'
                                      ? Icon(Icons.reddit,
                                          color: AppTheme.accentOrange,
                                          size: 36)
                                      : null),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (subscribers.isNotEmpty &&
                                    subscribers != '0')
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: AppTheme.glassDecoration(
                                      opacity: 0.1,
                                      borderRadius: AppTheme.radiusFull,
                                    ),
                                    child: Text(
                                      '$subscribers subscribers',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.75),
                                      fontSize: 12,
                                      height: 1.3),
                                ),
                              ],
                            ),
                          ),
                          if (!widget.isUser &&
                              _api.isLoggedIn &&
                              _subreddit != null) ...[
                            const SizedBox(width: 12),
                            PressableScale(
                              onTap: _toggleSubscription,
                              child: _isSubscribing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 7),
                                      decoration: (_subreddit!
                                                  .userIsSubscriber ??
                                              false)
                                          ? BoxDecoration(
                                              color: Colors.white12,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppTheme.radiusFull),
                                              border: Border.all(
                                                  color: Colors.white24,
                                                  width: 0.5),
                                            )
                                          : BoxDecoration(
                                              gradient: AppTheme.brandGradient,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppTheme.radiusFull),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppTheme.accentOrange
                                                      .withValues(alpha: 0.25),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_subreddit!.userIsSubscriber ??
                                              false) ...[
                                            const Icon(Icons.check_rounded,
                                                color: Colors.white, size: 14),
                                            const SizedBox(width: 4),
                                          ],
                                          Text(
                                            (_subreddit!.userIsSubscriber ??
                                                    false)
                                                ? 'Joined'
                                                : 'Join',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (!widget.isUser &&
                    !widget.isSaved &&
                    _api.isLoggedIn &&
                    !widget.subredditName.contains('+'))
                  IconButton(
                    icon: Icon(
                      _api.isSubredditInAnyCustomFeed(widget.subredditName)
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color:
                          _api.isSubredditInAnyCustomFeed(widget.subredditName)
                              ? Colors.amber
                              : null,
                    ),
                    onPressed: _showAddCustomFeedSheet,
                  ),
              ],
            ),

            // Sliver Sticky Filters
            SliverToBoxAdapter(
              child: Container(
                color: AppTheme.background,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Primary sorting chips
                    Row(
                      children: [
                        _buildSortChip(
                            'Hot', 'hot', Icons.local_fire_department_rounded),
                        const SizedBox(width: 8),
                        _buildSortChip('New', 'new', Icons.fiber_new_rounded),
                        const SizedBox(width: 8),
                        _buildSortChip('Top', 'top', Icons.trending_up_rounded),
                        const SizedBox(width: 8),
                        _buildSortChip(
                            'Rising', 'rising', Icons.trending_up_outlined),
                      ],
                    ),

                    // Time filter chips
                    if (_showTimeSelector) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _buildTimeChip('Hour', 'hour'),
                            const SizedBox(width: 6),
                            _buildTimeChip('Today', 'day'),
                            const SizedBox(width: 6),
                            _buildTimeChip('Week', 'week'),
                            const SizedBox(width: 6),
                            _buildTimeChip('Month', 'month'),
                            const SizedBox(width: 6),
                            _buildTimeChip('Year', 'year'),
                            const SizedBox(width: 6),
                            _buildTimeChip('All Time', 'all'),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ];
        },
        body: _isLoadingPosts
            ? _buildShimmerGrid()
            : _posts.isEmpty
                ? _buildEmptyState()
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 90),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: _posts.length,
                    itemBuilder: (context, index) {
                      final post = _posts[index];
                      return PressableScale(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => HomeScreen(
                                feedType: widget.isSaved
                                    ? 'saved'
                                    : (widget.isUser ? 'user' : 'subreddit'),
                                query: widget.subredditName,
                                initialPosts: _posts,
                                initialIndex: index,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusLg),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06),
                                width: 0.5),
                          ),
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusLg),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Thumbnail
                                CachedNetworkImage(
                                  imageUrl: post.thumbnail,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      Container(color: AppTheme.surfaceLight),
                                  errorWidget: (context, url, error) =>
                                      Container(
                                    color: AppTheme.surfaceLight,
                                    child: Icon(Icons.image_rounded,
                                        color: AppTheme.textMuted),
                                  ),
                                ),
                                // Cinematic gradient overlay
                                Container(
                                  decoration: const BoxDecoration(
                                    gradient: AppTheme.cinematicScrim,
                                  ),
                                ),
                                // Score with glass pill
                                Positioned(
                                  left: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(
                                          AppTheme.radiusFull),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.arrow_upward_rounded,
                                            size: 10,
                                            color: AppTheme.accentOrange),
                                        const SizedBox(width: 2),
                                        Text(
                                          post.score.toString(),
                                          style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Play overlay
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.35),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.1),
                                          width: 0.5),
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                // NSFW marker
                                if (post.isNsfw)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        borderRadius: BorderRadius.circular(
                                            AppTheme.radiusSm),
                                      ),
                                      child: const Text(
                                        '18+',
                                        style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildSortChip(String label, String sortVal, IconData icon) {
    final isSelected = _sort == sortVal;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: PressableScale(
          onTap: () => _changeSort(sortVal),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              gradient: isSelected ? AppTheme.warmGradient : null,
              color: isSelected ? null : AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              border: Border.all(
                color: isSelected ? Colors.transparent : AppTheme.glassBorder,
                width: 0.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppTheme.accentOrange.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 13,
                    color: isSelected ? Colors.white : AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeChip(String label, String timeVal) {
    final isSelected = _time == timeVal;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: PressableScale(
        onTap: () => _changeTime(timeVal),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accentPurple.withValues(alpha: 0.15)
                : AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            border: Border.all(
              color: isSelected
                  ? AppTheme.accentPurple.withValues(alpha: 0.3)
                  : AppTheme.glassBorder,
              width: 0.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color:
                    isSelected ? AppTheme.accentPurple : AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: 9,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: AppTheme.surface,
          highlightColor: AppTheme.surfaceLight,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.movie_creation_outlined,
                color: AppTheme.textMuted, size: 44),
          ),
          const SizedBox(height: 16),
          Text(
            _postsError ?? 'No video posts found in this feed.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _loadPosts(refresh: true),
            child: Text(_postsError == null ? 'Refresh' : 'Retry Request'),
          ),
        ],
      ),
    );
  }
}
