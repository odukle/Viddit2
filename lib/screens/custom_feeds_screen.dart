import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/reddit_api.dart';
import '../models/multireddit_model.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import '../widgets/pressable_scale.dart';

class CustomFeedsScreen extends StatefulWidget {
  final bool isLoggedIn;
  final bool isTabActive;
  const CustomFeedsScreen({
    super.key,
    required this.isLoggedIn,
    this.isTabActive = false,
  });

  @override
  State<CustomFeedsScreen> createState() => _CustomFeedsScreenState();
}

class _CustomFeedsScreenState extends State<CustomFeedsScreen> {
  final RedditApi _api = RedditApi();
  final TextEditingController _feedNameController = TextEditingController();

  List<MultiRedditModel> _feeds = [];
  bool _isLoading = true;
  bool? _wasLoggedIn;

  @override
  void initState() {
    super.initState();
    _loadFeeds();
  }

  @override
  void didUpdateWidget(covariant CustomFeedsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoggedIn != oldWidget.isLoggedIn ||
        (widget.isTabActive && !oldWidget.isTabActive)) {
      _loadFeeds();
    }
  }

  Future<void> _loadFeeds() async {
    if (!_api.isLoggedIn) {
      if (mounted) {
        setState(() {
          _feeds = [];
          _isLoading = false;
        });
      }
      return;
    }

    if (_feeds.isEmpty && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final feeds = await _api.fetchCustomFeeds();
    if (mounted) {
      setState(() {
        _feeds = feeds;
        _isLoading = false;
      });
    }
  }

  Future<void> _createNewFeed() async {
    final name = _feedNameController.text.trim();
    if (name.isEmpty) return;

    final specialChars =
        RegExp(r'''[~`!@#\$%^&*()_\-+=|\\{}\[\]:;"'<>,.?/₹]''');
    if (specialChars.hasMatch(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Special characters are not allowed.')),
      );
      return;
    }

    Navigator.pop(context);
    setState(() {
      _isLoading = true;
    });

    final newFeed = await _api.createCustomFeed(name);
    _feedNameController.clear();

    if (newFeed != null) {
      await _loadFeeds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feed created successfully! 🎉')),
        );
      }
    } else {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create feed.')),
        );
      }
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Custom Feed'),
        content: TextField(
          controller: _feedNameController,
          autofocus: true,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Feed Name (e.g. My Gifs)',
            hintStyle: TextStyle(color: AppTheme.textMuted),
            filled: true,
            fillColor: AppTheme.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              borderSide: BorderSide(color: AppTheme.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              borderSide: BorderSide(color: AppTheme.accentOrange),
            ),
          ),
          onSubmitted: (_) => _createNewFeed(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _feedNameController.clear();
              Navigator.pop(context);
            },
            child:
                Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentOrange),
            onPressed: _createNewFeed,
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFeed(MultiRedditModel feed) async {
    setState(() {
      _isLoading = true;
    });
    final success = await _api.deleteCustomFeed(feed.name);
    if (success) {
      await _loadFeeds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feed deleted successfully.')),
        );
      }
    } else {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete feed.')),
        );
      }
    }
  }

  void _confirmDeleteFeed(MultiRedditModel feed) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Custom Feed?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${feed.displayName}"? This action cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteFeed(feed);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeSubreddit(MultiRedditModel feed, String subName) async {
    final success =
        await _api.removeSubredditFromCustomFeed(feed.name, subName);
    if (success) {
      await _loadFeeds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Removed r/$subName from ${feed.displayName}')),
        );
      }
    }
  }

  void _openFeedDetails(MultiRedditModel feed) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
                border: Border(
                  top: BorderSide(color: AppTheme.glassBorder, width: 0.5),
                ),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentOrange.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.accentOrange
                                    .withValues(alpha: 0.2),
                                width: 1.5),
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: AppTheme.surfaceLight,
                            backgroundImage: feed.iconUrl.isNotEmpty
                                ? CachedNetworkImageProvider(feed.iconUrl)
                                : null,
                            child: feed.iconUrl.isEmpty
                                ? const Icon(Icons.star_rounded,
                                    color: Colors.amber, size: 20)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          feed.displayName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        PressableScale(
                          onTap: () {
                            Navigator.pop(context);
                            _confirmDeleteFeed(feed);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: Colors.redAccent, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: AppTheme.glassBorder),

                  // Subreddits list
                  Expanded(
                    child: feed.subreddits.isEmpty
                        ? Center(
                            child: Text(
                              'No subreddits added yet.\nGo to Discover to add subreddits.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : ListView.builder(
                            itemCount: feed.subreddits.length,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            itemBuilder: (context, index) {
                              final sub = feed.subreddits[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration:
                                    AppTheme.glassDecoration(opacity: 0.04),
                                child: ListTile(
                                  title: Text('r/$sub',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  trailing: PressableScale(
                                    onTap: () {
                                      setModalState(() {
                                        feed.subreddits.removeAt(index);
                                      });
                                      _removeSubreddit(feed, sub);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.06),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                          Icons.remove_circle_outline_rounded,
                                          color: AppTheme.textSecondary,
                                          size: 18),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Browse Videos button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: PressableScale(
                        onTap: feed.subreddits.isEmpty
                            ? () {}
                            : () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => HomeScreen(
                                      feedType: 'custom_feed',
                                      query:
                                          'user/${_api.currentUsername}/m/${feed.name}',
                                    ),
                                  ),
                                );
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: feed.subreddits.isEmpty
                                ? null
                                : AppTheme.warmGradient,
                            color: feed.subreddits.isEmpty
                                ? AppTheme.surfaceLight
                                : null,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMd),
                            boxShadow: feed.subreddits.isEmpty
                                ? null
                                : [
                                    BoxShadow(
                                      color: AppTheme.accentOrange
                                          .withValues(alpha: 0.3),
                                      blurRadius: 15,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                          ),
                          child: Center(
                            child: Text(
                              'Browse Videos',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: feed.subreddits.isEmpty
                                    ? AppTheme.textMuted
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_api.isLoggedIn != _wasLoggedIn) {
      _wasLoggedIn = _api.isLoggedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadFeeds();
      });
    }

    if (!_api.isLoggedIn) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  decoration: AppTheme.cardDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: AppTheme.radiusXl),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: AppTheme.warmGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppTheme.accentOrange.withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.star_half_rounded,
                            color: Colors.white, size: 48),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Unlock Custom Feeds',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sign in to your Reddit account to create personalized custom feeds aggregating your favorite video subreddits.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: PressableScale(
                          onTap: () async {
                            final success = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const LoginScreen()),
                            );
                            if (success == true) {
                              _loadFeeds();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              gradient: AppTheme.warmGradient,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentOrange
                                      .withValues(alpha: 0.35),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                'Sign in with Reddit',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 110),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Custom Feeds',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  PressableScale(
                    onTap: _showCreateDialog,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppTheme.warmGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppTheme.accentOrange.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: SpinKitRing(
                          color: AppTheme.accentOrange.withValues(alpha: 0.8),
                          size: 44.0,
                          lineWidth: 2.5,
                        ),
                      )
                    : _feeds.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            itemCount: _feeds.length,
                            padding: const EdgeInsets.only(bottom: 90),
                            itemBuilder: (context, index) {
                              final feed = _feeds[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: PressableScale(
                                  onTap: () => _openFeedDetails(feed),
                                  child: Container(
                                    decoration: AppTheme.cardDecoration(),
                                    child: IntrinsicHeight(
                                      child: Row(
                                        children: [
                                          // Gradient accent strip
                                          Container(
                                            width: 3,
                                            decoration: BoxDecoration(
                                              gradient: AppTheme.warmGradient,
                                              borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(
                                                    AppTheme.radiusLg),
                                                bottomLeft: Radius.circular(
                                                    AppTheme.radiusLg),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(16.0),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                          color: AppTheme
                                                              .accentOrange
                                                              .withValues(
                                                                  alpha: 0.15),
                                                          width: 1.5),
                                                    ),
                                                    child: CircleAvatar(
                                                      radius: 22,
                                                      backgroundColor:
                                                          AppTheme.surfaceLight,
                                                      backgroundImage: feed
                                                              .iconUrl
                                                              .isNotEmpty
                                                          ? CachedNetworkImageProvider(
                                                              feed.iconUrl)
                                                          : null,
                                                      child: feed
                                                              .iconUrl.isEmpty
                                                          ? const Icon(
                                                              Icons
                                                                  .star_rounded,
                                                              color:
                                                                  Colors.amber,
                                                              size: 22)
                                                          : null,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          feed.displayName,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleSmall
                                                                  ?.copyWith(
                                                                      fontSize:
                                                                          15),
                                                        ),
                                                        const SizedBox(
                                                            height: 4),
                                                        Text(
                                                          '${feed.subreddits.length} subreddits',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Icon(
                                                      Icons
                                                          .arrow_forward_ios_rounded,
                                                      size: 14,
                                                      color:
                                                          AppTheme.accentWarm),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
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
            child: Icon(Icons.star_border_rounded,
                color: AppTheme.textMuted, size: 48),
          ),
          const SizedBox(height: 16),
          Text(
            'You haven\'t created any custom feeds.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _showCreateDialog,
            child: const Text('Create New Feed'),
          ),
        ],
      ),
    );
  }
}
