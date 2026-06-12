import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../models/post_model.dart';
import '../models/comment_model.dart';
import '../api/reddit_api.dart';
import '../theme/app_theme.dart';
import '../screens/login_screen.dart';
import 'pressable_scale.dart';

class CommentsSheet extends StatefulWidget {
  final PostModel post;

  const CommentsSheet({super.key, required this.post});

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final RedditApi _api = RedditApi();
  List<CommentModel> _comments = [];
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _activeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadComments();
    _api.addSafetyListener(_onSafetySettingsChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _api.removeSafetyListener(_onSafetySettingsChanged);
    super.dispose();
  }

  void _onSafetySettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _checkRateLimitPrompt() {
    if (!_api.isLoggedIn &&
        _errorMessage != null &&
        _errorMessage!.toLowerCase().contains('rate-limited')) {
      _showRateLimitSignInPrompt();
    }
  }

  void _showRateLimitSignInPrompt() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reddit Rate Limit Exceeded',
            style: TextStyle(color: Colors.white)),
        content:  Text(
          'You are currently browsing as a guest. Reddit enforces strict rate limits on guest users. Sign in to enjoy unlimited browsing!',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:  Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
              if (success == true && mounted) {
                _loadComments();
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

  Future<void> _loadComments() async {
    final comments = await _api.fetchComments(widget.post.permalink);
    if (mounted) {
      setState(() {
        _comments = comments;
        _errorMessage = _api.lastErrorMessage;
        _isLoading = false;
      });
      _checkRateLimitPrompt();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.of(context).size.height * 0.75;

    return Container(
      height: height,
      decoration:  BoxDecoration(
        color: AppTheme.surface,
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
              // Handle bar with accent color
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Comments (${widget.post.commentCount})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    PressableScale(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: AppTheme.glassDecoration(
                          opacity: 0.08,
                          borderRadius: AppTheme.radiusFull,
                        ),
                        child:  Icon(Icons.close_rounded,
                            color: AppTheme.textSecondary, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
               Divider(color: AppTheme.glassBorder, height: 1),

              // Inline Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  height: 40,
                  decoration: AppTheme.glassDecoration(
                    opacity: 0.08,
                    borderRadius: AppTheme.radiusMd,
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim();
                      });
                    },
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search comments...',
                      hintStyle:  TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      prefixIcon:  Icon(Icons.search_rounded, size: 18, color: AppTheme.textSecondary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon:  Icon(Icons.clear_rounded, size: 18, color: AppTheme.textSecondary),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
              ),

              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _buildFilterChip(label: 'All', value: 'all', icon: Icons.forum_rounded),
                    _buildFilterChip(label: 'Questions', value: 'questions', icon: Icons.help_outline_rounded),
                    _buildFilterChip(label: 'Links', value: 'links', icon: Icons.link_rounded),
                    _buildFilterChip(label: 'Popular', value: 'upvoted', icon: Icons.trending_up_rounded),
                    _buildFilterChip(label: 'Positive', value: 'positive', icon: Icons.sentiment_satisfied_alt_rounded),
                    _buildFilterChip(label: 'Negative', value: 'negative', icon: Icons.sentiment_very_dissatisfied_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 4),
               Divider(color: AppTheme.glassBorder, height: 1),

              // Comments List
              Expanded(
                child: _isLoading
                    ? _buildShimmerLoader()
                    : (_searchQuery.isNotEmpty || _activeFilter != 'all')
                        ? (_filteredComments.isEmpty
                            ? _buildNoResultsState()
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                                itemCount: _filteredComments.length,
                                itemBuilder: (context, index) {
                                  return CommentNodeWidget(
                                    comment: _filteredComments[index],
                                    forceHideReplies: true,
                                    onUserBlocked: () {
                                      setState(() {});
                                    },
                                  );
                                },
                              ))
                        : (_comments.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                                itemCount: _comments.length,
                                itemBuilder: (context, index) {
                                  return CommentNodeWidget(
                                    comment: _comments[index],
                                    onUserBlocked: () {
                                      setState(() {});
                                    },
                                  );
                                },
                              )),
              ),
            ],
          ),
        );
  }

  Widget _buildShimmerLoader() {
    return Shimmer.fromColors(
      baseColor: AppTheme.surfaceLight,
      highlightColor: AppTheme.surfaceElevated,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(radius: 14, backgroundColor: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        width: 100,
                        height: 10,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 8),
                    Container(
                        width: double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 4),
                    Container(
                        width: 160,
                        height: 12,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<CommentModel> get _filteredComments {
    final List<CommentModel> flat = [];
    void traverse(CommentModel node) {
      final isBot = node.author.toLowerCase() == 'automoderator' ||
          node.author.toLowerCase().endsWith('bot');
      if (!isBot) {
        flat.add(node);
      }
      for (final reply in node.replies) {
        traverse(reply);
      }
    }

    for (final node in _comments) {
      traverse(node);
    }

    return flat.where((comment) {
      // 1. Keyword search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesAuthor = comment.author.toLowerCase().contains(query);
        final matchesBody = comment.body.toLowerCase().contains(query);
        if (!matchesAuthor && !matchesBody) {
          return false;
        }
      }

      // 2. Tab/Filter category
      switch (_activeFilter) {
        case 'questions':
          return comment.body.contains('?');
        case 'links':
          final bodyLower = comment.body.toLowerCase();
          return bodyLower.contains('http://') ||
              bodyLower.contains('https://') ||
              bodyLower.contains('www.');
        case 'upvoted':
          return comment.score >= 20;
        case 'positive':
          final bodyLower = comment.body.toLowerCase();
          final positiveWords = [
            'love', 'great', 'awesome', 'amazing', 'cool', 'best', 'good',
            'perfect', 'beautiful', 'thank', 'nice', 'funny', 'hilarious', 'wow',
            ':)', ':-)'
          ];
          return positiveWords.any((word) => bodyLower.contains(word));
        case 'negative':
          final bodyLower = comment.body.toLowerCase();
          final negativeWords = [
            'bad', 'hate', 'worst', 'awful', 'terrible', 'annoying', 'boring',
            'suck', 'angry', 'sad', ':(', ':-('
          ];
          return negativeWords.any((word) => bodyLower.contains(word));
        case 'all':
        default:
          return true;
      }
    }).toList();
  }

  Widget _buildFilterChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _activeFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressableScale(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _activeFilter = value;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accentOrange.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: isSelected
                  ? AppTheme.accentOrange
                  : AppTheme.glassBorder,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? AppTheme.accentOrange : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration:  BoxDecoration(
              color: AppTheme.surfaceElevated,
              shape: BoxShape.circle,
            ),
            child:  Icon(Icons.search_off_rounded,
                color: AppTheme.textMuted, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            'No matching comments found',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search query or filters',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textMuted,
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration:  BoxDecoration(
              color: AppTheme.surfaceElevated,
              shape: BoxShape.circle,
            ),
            child:  Icon(Icons.forum_outlined,
                color: AppTheme.textMuted, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'No comments yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class CommentNodeWidget extends StatefulWidget {
  final CommentModel comment;
  final CommentModel? parentComment;
  final int depth;
  final VoidCallback? onUserBlocked;
  final bool forceHideReplies;

  const CommentNodeWidget({
    super.key,
    required this.comment,
    this.parentComment,
    this.depth = 0,
    this.onUserBlocked,
    this.forceHideReplies = false,
  });

  @override
  State<CommentNodeWidget> createState() => _CommentNodeWidgetState();
}

class _CommentNodeWidgetState extends State<CommentNodeWidget> {
  bool _repliesCollapsed = true; // Hidden by default initially
  String _authorIcon = '';
  final RedditApi _api = RedditApi();
  final TextEditingController _replyController = TextEditingController();
  bool _isReplying = false;
  bool _isSubmittingReply = false;
  bool _isSafetyRevealed = false;

  // 4 cycling colors for thread depth
  static  List<Color> _threadColors = [
    AppTheme.accentOrange,
    AppTheme.accentPurple,
    AppTheme.accentCyan,
    AppTheme.accentWarm,
  ];

  @override
  void initState() {
    super.initState();
    _loadUserIcon();
    _api.addSafetyListener(_onSafetyChanged);
  }

  @override
  void dispose() {
    _api.removeSafetyListener(_onSafetyChanged);
    _replyController.dispose();
    super.dispose();
  }

  void _onSafetyChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showParentCommentPreview() {
    if (widget.parentComment == null) return;
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            side:  BorderSide(color: AppTheme.glassBorder, width: 0.5),
          ),
          title: Row(
            children: [
               Icon(Icons.reply_rounded, color: AppTheme.accentOrange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Replying to u/${widget.parentComment!.author}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: AppTheme.glassBorder, width: 0.5),
            ),
            child: SingleChildScrollView(
              child: Text(
                widget.parentComment!.body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text('Close', style: TextStyle(color: AppTheme.accentOrange)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadUserIcon() async {
    if (widget.comment.author != 'unknown' &&
        widget.comment.author != '[deleted]') {
      _api.fetchUserAbout(widget.comment.author).then((data) {
        if (mounted && data['icon_img'] != null) {
          setState(() {
            _authorIcon = data['icon_img'].toString().replaceAll('amp;', '');
          });
        }
      });
    }
  }

  String _formatTimeAgo(double timeSeconds) {
    final DateTime created =
        DateTime.fromMillisecondsSinceEpoch((timeSeconds * 1000).toInt());
    final Duration diff = DateTime.now().difference(created);

    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo';
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()}w';
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }

  void _showCommentSafetyOptions() {
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
                leading:  Icon(Icons.flag_rounded,
                    color: AppTheme.accentOrange),
                title: const Text('Report Comment',
                    style: TextStyle(color: Colors.white)),
                subtitle:  Text(
                    'Report this comment for UGC violation or abuse',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _showCommentReportReasonDialog();
                },
              ),
              ListTile(
                leading:  Icon(Icons.block_rounded,
                    color: AppTheme.accentPurple),
                title: Text('Block u/${widget.comment.author}',
                    style: const TextStyle(color: Colors.white)),
                subtitle:  Text(
                    'You won\'t see posts or comments from this user again',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _blockUserConfirm();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showCommentReportReasonDialog() {
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
        title:
            const Text('Report Comment', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: reasons.map((reason) {
            return ListTile(
              title: Text(reason,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () async {
                Navigator.pop(context);
                _submitCommentReport(reason);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _submitCommentReport(String reason) async {
    await _api.reportCommentLocal(widget.comment.id);

    if (_api.isLoggedIn) {
      await _api.reportThing(widget.comment.fullName, reason);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Comment reported. Thank you for making Scroller safe!')),
      );
      if (widget.onUserBlocked != null) {
        widget.onUserBlocked!();
      }
    }
  }

  void _blockUserConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Block u/${widget.comment.author}?',
            style: const TextStyle(color: Colors.white)),
        content:  Text(
          'Are you sure you want to block this user? You will not see their posts or comments again.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
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
    await _api.blockUserLocal(widget.comment.author);

    if (_api.isLoggedIn) {
      await _api.blockUser(widget.comment.author);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Blocked u/${widget.comment.author}')),
      );
      if (widget.onUserBlocked != null) {
        widget.onUserBlocked!();
      }
    }
  }

  void _showEditDeleteSheet() {
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
                leading:  Icon(Icons.edit_rounded,
                    color: AppTheme.accentOrange),
                title: const Text('Edit Comment',
                    style: TextStyle(color: Colors.white)),
                subtitle:  Text('Modify the text of your comment',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _showEditCommentDialog();
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_rounded, color: Colors.redAccent),
                title: const Text('Delete Comment',
                    style: TextStyle(color: Colors.white)),
                subtitle:  Text('Permanently delete this comment',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmDialog();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showEditCommentDialog() {
    final controller = TextEditingController(text: widget.comment.body);
    final scaffoldContext = context;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:
            const Text('Edit Comment', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Edit your comment...',
            hintStyle:  TextStyle(color: AppTheme.textSecondary),
            filled: true,
            fillColor: AppTheme.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:  Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newText = controller.text.trim();
              if (newText.isEmpty) return;
              Navigator.pop(dialogContext);
              final updated =
                  await _api.editComment(widget.comment.fullName, newText);
              if (updated != null && scaffoldContext.mounted) {
                setState(() {
                  widget.comment.body = updated.body;
                });
                ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                  const SnackBar(content: Text('Comment updated!')),
                );
              } else if (scaffoldContext.mounted) {
                ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                  SnackBar(
                      content: Text(
                          _api.lastErrorMessage ?? 'Failed to edit comment.')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentOrange),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog() {
    final scaffoldContext = context;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Comment?',
            style: TextStyle(color: Colors.white)),
        content:  Text(
          'Are you sure you want to delete this comment? This action cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:  Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await _api.deleteComment(widget.comment.fullName);
              if (success && scaffoldContext.mounted) {
                setState(() {
                  widget.comment.body = '[deleted]';
                  widget.comment.author = '[deleted]';
                });
                ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                  const SnackBar(content: Text('Comment deleted.')),
                );
              } else if (scaffoldContext.mounted) {
                ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                  SnackBar(
                      content: Text(_api.lastErrorMessage ??
                          'Failed to delete comment.')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSignInRequired() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign In Required',
            style: TextStyle(color: Colors.white)),
        content:  Text('Please sign in to vote and reply to comments.',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // pop dialog
              Navigator.pop(context); // pop comments sheet
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Go to the Profile tab to sign in.')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  Future<void> _vote(int direction) async {
    final originalVote = widget.comment.userVote;
    final originalScore = widget.comment.score;
    final newVote = originalVote == direction ? 0 : direction;

    int scoreChange = newVote - originalVote;

    setState(() {
      widget.comment.userVote = newVote;
      widget.comment.score = originalScore + scoreChange;
    });

    final success = await _api.vote(widget.comment.fullName, newVote);
    if (!success && mounted) {
      setState(() {
        widget.comment.userVote = originalVote;
        widget.comment.score = originalScore;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to cast vote on comment.')),
      );
    }
  }

  Future<void> _submitReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSubmittingReply = true;
    });

    final newComment = await _api.postComment(widget.comment.fullName, text);

    if (mounted) {
      setState(() {
        _isSubmittingReply = false;
      });

      if (newComment != null) {
        setState(() {
          widget.comment.replies.insert(0, newComment);
          _isReplying = false;
          _repliesCollapsed = false; // Expand to show the new reply
          _replyController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reply posted!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_api.lastErrorMessage ?? 'Failed to post reply.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final isBlockedOrReported = _api.isUserBlocked(comment.author) ||
        _api.isCommentReported(comment.id);

    if (isBlockedOrReported && !_isSafetyRevealed) {
      final String hiddenReason = _api.isCommentReported(comment.id)
          ? 'reported comment'
          : 'blocked user u/${comment.author}';

      return Container(
        margin: EdgeInsets.only(left: widget.depth > 0 ? 10 : 0, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
             Icon(Icons.shield_outlined, color: AppTheme.textSecondary, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Comment hidden ($hiddenReason)',
                style:  TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            PressableScale(
              onTap: () {
                setState(() {
                  _isSafetyRevealed = true;
                });
              },
              child:  Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Show',
                  style: TextStyle(
                    color: AppTheme.accentOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isBot = comment.author.toLowerCase() == 'automoderator' ||
        comment.author.toLowerCase().endsWith('bot');

    if (isBot) return const SizedBox.shrink();

    final Color threadLineColor =
        _threadColors[widget.depth % _threadColors.length]
            .withValues(alpha: 0.25);

    final isOwnComment = _api.isLoggedIn &&
        _api.currentUsername != null &&
        comment.author.toLowerCase() == _api.currentUsername!.toLowerCase();

    return Container(
      margin:
          EdgeInsets.only(left: widget.depth > 0 ? 10 : 0, top: 8, bottom: 8),
      decoration: BoxDecoration(
        border: widget.depth > 0
            ? Border(left: BorderSide(color: threadLineColor, width: 1.5))
            : null,
      ),
      padding: EdgeInsets.only(left: widget.depth > 0 ? 12 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: isOwnComment 
                ? _showEditDeleteSheet 
                : (widget.parentComment != null ? _showParentCommentPreview : null),
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: User icon, Name, Time
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                            width: 0.5),
                      ),
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: AppTheme.surfaceLight,
                        backgroundImage: _authorIcon.isNotEmpty
                            ? CachedNetworkImageProvider(_authorIcon)
                            : null,
                        child: _authorIcon.isEmpty
                            ?  Icon(Icons.person_rounded,
                                color: AppTheme.textMuted, size: 12)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'u/${comment.author}',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontSize: 12.5),
                    ),
                    if (widget.parentComment != null) ...[
                      const SizedBox(width: 4),
                       Icon(Icons.reply_rounded, size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: _showParentCommentPreview,
                        child: Text(
                          'u/${widget.parentComment!.author}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                     Icon(Icons.circle,
                        size: 3, color: AppTheme.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      _formatTimeAgo(comment.createdUtc),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    if (isOwnComment)
                      PressableScale(
                        onTap: _showEditDeleteSheet,
                        child:  Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Icon(
                            Icons.more_vert_rounded,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                // Body text
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    comment.body,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 13.5,
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.45,
                        ),
                  ),
                ),

                // Interactive Action Row: Upvote, Score, Downvote, Reply
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
                  child: Row(
                    children: [
                      PressableScale(
                        onTap: () {
                          if (!_api.isLoggedIn) {
                            _showSignInRequired();
                          } else {
                            _vote(1);
                          }
                        },
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          size: 16,
                          color: comment.userVote == 1
                              ? AppTheme.accentOrange
                              : AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        comment.score.toString(),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: comment.userVote == 1
                              ? AppTheme.accentOrange
                              : (comment.userVote == -1
                                  ? AppTheme.accentPurple
                                  : AppTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PressableScale(
                        onTap: () {
                          if (!_api.isLoggedIn) {
                            _showSignInRequired();
                          } else {
                            _vote(-1);
                          }
                        },
                        child: Icon(
                          Icons.arrow_downward_rounded,
                          size: 16,
                          color: comment.userVote == -1
                              ? AppTheme.accentPurple
                              : AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 20),
                      PressableScale(
                        onTap: () {
                          if (!_api.isLoggedIn) {
                            _showSignInRequired();
                          } else {
                            setState(() {
                              _isReplying = !_isReplying;
                            });
                          }
                        },
                        child: Row(
                          children: [
                             Icon(Icons.reply_rounded,
                                size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              'Reply',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      PressableScale(
                        onTap: _showCommentSafetyOptions,
                        child: Row(
                          children: [
                             Icon(Icons.shield_outlined,
                                size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              'Safety',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Reply Input Field
          if (_isReplying)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.glassBorder,
                          width: 0.5,
                        ),
                      ),
                      child: TextField(
                        controller: _replyController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        maxLines: null,
                        decoration:  InputDecoration(
                          hintText: 'Write a reply...',
                          hintStyle: TextStyle(
                              color: AppTheme.textMuted, fontSize: 13),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isSubmittingReply)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.accentOrange),
                      ),
                    )
                  else ...[
                    PressableScale(
                      onTap: _submitReply,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration:  BoxDecoration(
                          color: AppTheme.accentOrange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 4),
                    PressableScale(
                      onTap: () {
                        setState(() {
                          _isReplying = false;
                          _replyController.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child:  Icon(Icons.close_rounded,
                            size: 14, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Replies with AnimatedSize
          if (comment.replies.isNotEmpty && !widget.forceHideReplies) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: PressableScale(
                onTap: () {
                  setState(() {
                    _repliesCollapsed = !_repliesCollapsed;
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _repliesCollapsed
                          ? Icons.add_circle_outline_rounded
                          : Icons.remove_circle_outline_rounded,
                      size: 14,
                      color: AppTheme.accentOrange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _repliesCollapsed
                          ? 'Show ${comment.replies.length} replies'
                          : 'Hide replies',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppTheme.accentOrange,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: _repliesCollapsed
                  ? const SizedBox.shrink()
                  : Column(
                      children: comment.replies.map((reply) {
                        return CommentNodeWidget(
                          comment: reply,
                          parentComment: widget.comment,
                          depth: widget.depth + 1,
                          onUserBlocked: widget.onUserBlocked,
                        );
                      }).toList(),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}