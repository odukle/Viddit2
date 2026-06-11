import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../api/reddit_api.dart';
import '../theme/app_theme.dart';
import '../models/multireddit_model.dart';
import 'subreddit_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/pressable_scale.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final RedditApi _api = RedditApi();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Map<String, String>> _trendingSubreddits = [];
  List<Map<String, String>> _searchResults = [];

  bool _isLoadingTrending = true;
  bool _isSearching = false;
  bool _nsfwAllowed = false;
  bool _searchFocused = false;
  String _selectedCategory = 'videos';
  List<String> _searchHistory = [];
  static const String _searchHistoryKey = 'viddit_search_history';

  final List<String> _categories = [
    'videos',
    'memes',
    'funny',
    'aww',
    'wholesome',
    'gifs',
    'dank',
    'news',
    'sports'
  ];

  @override
  void initState() {
    super.initState();
    _nsfwAllowed = _api.isNsfwAllowed;
    _api.addSafetyListener(_onSafetyOrGeolocationChanged);
    _loadTrending();
    _loadSearchHistory();
    _searchFocusNode.addListener(() {
      setState(() {
        _searchFocused = _searchFocusNode.hasFocus;
      });
    });
    if (_api.isLoggedIn) {
      _api.fetchCustomFeeds().then((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_searchHistoryKey) ?? [];
      if (mounted) {
        setState(() {
          _searchHistory = list;
        });
      }
    } catch (e) {
      debugPrint('Error loading search history: $e');
    }
  }

  Future<void> _addToHistory(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_searchHistoryKey) ?? [];

      list.remove(cleanQuery); // Move to front
      list.insert(0, cleanQuery);

      if (list.length > 15) {
        list.removeLast();
      }

      await prefs.setStringList(_searchHistoryKey, list);
      if (mounted) {
        setState(() {
          _searchHistory = list;
        });
      }
    } catch (e) {
      debugPrint('Error adding to search history: $e');
    }
  }

  Future<void> _removeFromHistory(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_searchHistoryKey) ?? [];

      list.remove(query);
      await prefs.setStringList(_searchHistoryKey, list);
      if (mounted) {
        setState(() {
          _searchHistory = list;
        });
      }
    } catch (e) {
      debugPrint('Error removing from search history: $e');
    }
  }

  Future<void> _clearSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_searchHistoryKey);
      if (mounted) {
        setState(() {
          _searchHistory.clear();
        });
      }
    } catch (e) {
      debugPrint('Error clearing search history: $e');
    }
  }

  Future<void> _loadTrending() async {
    setState(() {
      _isLoadingTrending = true;
      _searchResults.clear();
      _searchController.clear();
    });

    final subreddits = await _api.fetchTrendingSubreddits();
    if (mounted) {
      setState(() {
        _trendingSubreddits = subreddits;
        _isLoadingTrending = false;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      _loadTrending();
      return;
    }

    _addToHistory(query);

    setState(() {
      _isSearching = true;
    });

    final results =
        await _api.searchSubreddits(query, _nsfwAllowed && _api.isNsfwAllowed);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  @override
  void dispose() {
    _api.removeSafetyListener(_onSafetyOrGeolocationChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSafetyOrGeolocationChanged() {
    if (mounted) {
      setState(() {
        _nsfwAllowed = _api.isNsfwAllowed;
      });
      _loadTrending();
    }
  }

  void _showAddCustomFeedSheetForSub(String subredditName) {
    final cleanSub = subredditName.replaceAll('r/', '').trim();
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
                          style: const TextStyle(color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Feed Name (e.g. My Gifs)',
                            hintStyle:
                                const TextStyle(color: AppTheme.textMuted),
                            filled: true,
                            fillColor: AppTheme.surfaceLight,
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                              borderSide:
                                  const BorderSide(color: AppTheme.glassBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                              borderSide: const BorderSide(
                                  color: AppTheme.accentOrange),
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
                                            newFeed.name, cleanSub);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            success
                                                ? 'Feed "$name" created & r/$cleanSub added! 🎉'
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
                        const Text(
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
                                      style: const TextStyle(
                                          color: AppTheme.textPrimary),
                                      decoration: InputDecoration(
                                        hintText: 'Feed Name (e.g. My Gifs)',
                                        hintStyle: const TextStyle(
                                            color: AppTheme.textMuted),
                                        filled: true,
                                        fillColor: AppTheme.surfaceLight,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppTheme.radiusMd),
                                          borderSide: const BorderSide(
                                              color: AppTheme.glassBorder),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppTheme.radiusMd),
                                          borderSide: const BorderSide(
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
                                        child: const Text('Cancel',
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
                                                newFeed.name, cleanSub);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Feed "$name" created & r/$cleanSub added! 🎉',
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
                              icon: const Icon(Icons.add_rounded,
                                  size: 16, color: AppTheme.accentOrange),
                              label: const Text(
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
                                            feed.name, cleanSub);
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
                                      trailing: const Icon(
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
  Widget build(BuildContext context) {
    final bool showingResults =
        _searchController.text.isNotEmpty || _searchResults.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ─── Collapsible Header (Title + Search + Categories) ───
            SliverAppBar(
              floating: true,
              snap: true,
              pinned: false,
              elevation: 0,
              backgroundColor: AppTheme.surface,
              expandedHeight: 220,
              flexibleSpace: FlexibleSpaceBar(
                background: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingLg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppTheme.spacingLg),

                      // ─── Screen Title with gradient shader ───
                      ShaderMask(
                        shaderCallback: (bounds) =>
                            (AppTheme.warmGradient as LinearGradient)
                                .createShader(bounds),
                        blendMode: BlendMode.srcIn,
                        child: Text(
                          'Discover',
                          style: Theme.of(context)
                              .textTheme
                              .displayMedium
                              ?.copyWith(letterSpacing: -0.8),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingXl),

                      // ─── Search Bar Row ───
                      Row(
                        children: [
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceElevated,
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusXl),
                                border: Border.all(
                                  color: _searchFocused
                                      ? AppTheme.accentOrange
                                          .withValues(alpha: 0.3)
                                      : AppTheme.glassBorder,
                                  width: _searchFocused ? 1.0 : 0.8,
                                ),
                                boxShadow: [
                                  if (_searchFocused)
                                    BoxShadow(
                                      color: AppTheme.accentOrange
                                          .withValues(alpha: 0.15),
                                      blurRadius: 20,
                                      spreadRadius: 0,
                                    ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                style: Theme.of(context).textTheme.bodyLarge,
                                decoration: InputDecoration(
                                  hintText: 'Search subreddits...',
                                  hintStyle: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: AppTheme.textMuted,
                                        fontSize: 14,
                                      ),
                                  prefixIcon: const Icon(Icons.search_rounded,
                                      color: AppTheme.textSecondary, size: 20),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_api.isNsfwAllowed)
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _nsfwAllowed = !_nsfwAllowed;
                                            });
                                            if (_searchController
                                                .text.isNotEmpty) {
                                              _performSearch(
                                                  _searchController.text);
                                            }
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            padding: const EdgeInsets.all(6),
                                            margin: const EdgeInsets.only(
                                                right: 2),
                                            decoration: BoxDecoration(
                                              color: _nsfwAllowed
                                                  ? AppTheme.accentOrange
                                                      .withValues(alpha: 0.15)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppTheme.radiusSm),
                                            ),
                                            child: Icon(
                                              Icons.eighteen_up_rating_rounded,
                                              size: 18,
                                              color: _nsfwAllowed
                                                  ? AppTheme.accentOrange
                                                  : AppTheme.textMuted,
                                            ),
                                          ),
                                        ),
                                      if (_searchController.text.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.clear_rounded,
                                              color: AppTheme.textSecondary,
                                              size: 18),
                                          onPressed: () {
                                            setState(() {
                                              _searchController.clear();
                                              _searchResults.clear();
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                ),
                                onSubmitted: _performSearch,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacingMd),

                          // ─── Search Action Button ───
                          PressableScale(
                            onTap: () =>
                                _performSearch(_searchController.text),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: AppTheme.warmGradient,
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusLg),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.accentOrange
                                        .withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.arrow_forward_rounded,
                                  color: Colors.white, size: 22),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingLg),

                      // ─── Categories Chips Horizontal List ───
                      SizedBox(
                        height: 40,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final cat = _categories[index];
                            final bool isSelected =
                                _selectedCategory == cat &&
                                    _searchController.text
                                            .trim()
                                            .toLowerCase() ==
                                        cat.toLowerCase();
                            return Padding(
                              padding: const EdgeInsets.only(
                                  right: AppTheme.spacingSm),
                              child: PressableScale(
                                onTap: () {
                                  setState(() {
                                    _selectedCategory = cat;
                                    _searchController.text = cat;
                                  });
                                  _performSearch(cat);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 8),
                                  decoration: BoxDecoration(
                                    gradient: isSelected
                                        ? AppTheme.warmGradient
                                        : null,
                                    color: isSelected
                                        ? null
                                        : AppTheme.surfaceElevated,
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.radiusFull),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.transparent
                                          : AppTheme.glassBorder,
                                      width: 0.8,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: AppTheme.accentOrange
                                                  .withValues(alpha: 0.2),
                                              blurRadius: 10,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Center(
                                    child: AnimatedDefaultTextStyle(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : AppTheme.textSecondary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5,
                                      ),
                                      child: Text('r/$cat'),
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
            ),

            // ─── Recent Searches (part of scroll view) ───
            if (_searchController.text.isEmpty &&
                _searchHistory.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingLg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Searches',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          TextButton(
                            onPressed: _clearSearchHistory,
                            child: const Text(
                              'Clear All',
                              style: TextStyle(
                                color: AppTheme.accentOrange,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingXs),
                      SizedBox(
                        height: 38,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _searchHistory.length,
                          itemBuilder: (context, index) {
                            final query = _searchHistory[index];
                            return Padding(
                              padding: const EdgeInsets.only(
                                  right: AppTheme.spacingSm),
                              child: PressableScale(
                                onTap: () {
                                  _searchController.text = query;
                                  _performSearch(query);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceElevated,
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.radiusFull),
                                    border: Border.all(
                                        color: AppTheme.glassBorder,
                                        width: 0.8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.history_rounded,
                                          size: 14,
                                          color: AppTheme.textSecondary),
                                      const SizedBox(width: 6),
                                      Text(
                                        query,
                                        style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: () =>
                                            _removeFromHistory(query),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 14,
                                          color: AppTheme.textMuted,
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
                      const SizedBox(height: AppTheme.spacingXl),
                    ],
                  ),
                ),
              ),
            ],

            // ─── Section Header ───
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showingResults
                          ? 'Search Results'
                          : 'Trending Subreddits',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppTheme.spacingMd),
                  ],
                ),
              ),
            ),

            // ─── Results List ───
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingLg),
              sliver: _isSearching || _isLoadingTrending
                  ? _buildShimmerSliver()
                  : showingResults
                      ? _buildSubredditSliver(_searchResults)
                      : _buildSubredditSliver(_trendingSubreddits),
            ),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildShimmerSliver() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacingMd),
          child: Shimmer.fromColors(
            baseColor: AppTheme.surface,
            highlightColor: AppTheme.surfaceLight,
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
            ),
          ),
        ),
        childCount: 6,
      ),
    );
  }

  Widget _buildSubredditSliver(List<Map<String, String>> list) {
    if (list.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.search_off_rounded,
                    color: AppTheme.textMuted, size: 40),
              ),
              const SizedBox(height: AppTheme.spacingLg),
              Text(
                'No subreddits found.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: AppTheme.spacingXl),
              ElevatedButton(
                onPressed: _loadTrending,
                child: const Text('Back to Trending'),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final sub = list[index];
          final name = sub['name'] ?? 'r/unknown';
          final icon = sub['icon'] ?? '';
          final subscribers = sub['subscribers'] ?? '';

          return Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingMd),
            child: PressableScale(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SubredditScreen(
                      subredditName: name.replaceAll('r/', ''),
                    ),
                  ),
                );
              },
              child: Container(
                decoration: AppTheme.cardDecoration(),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingLg,
                    vertical: AppTheme.spacingSm,
                  ),
                  leading: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.accentOrange.withValues(alpha: 0.15),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentOrange.withValues(alpha: 0.08),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: AppTheme.surfaceElevated,
                      backgroundImage: icon.isNotEmpty
                          ? CachedNetworkImageProvider(icon)
                          : null,
                      child: icon.isEmpty
                          ? const Icon(Icons.reddit,
                              color: AppTheme.accentOrange, size: 24)
                          : null,
                    ),
                  ),
                  title: Text(
                    name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  subtitle: Text(
                    subscribers.isNotEmpty
                        ? '$subscribers subscribers'
                        : 'Tap to view feed grid',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: _api.isLoggedIn
                      ? IconButton(
                          icon: Icon(
                            _api.isSubredditInAnyCustomFeed(name)
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: _api.isSubredditInAnyCustomFeed(name)
                                ? Colors.amber
                                : AppTheme.textSecondary,
                            size: 24,
                          ),
                          onPressed: () =>
                              _showAddCustomFeedSheetForSub(name),
                        )
                      : const Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.accentWarm,
                          size: 22,
                        ),
                ),
              ),
            ),
          );
        },
        childCount: list.length,
      ),
    );
  }
}
