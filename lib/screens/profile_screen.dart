import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/reddit_api.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import '../widgets/pressable_scale.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLoginStateChanged;

  const ProfileScreen({super.key, required this.onLoginStateChanged});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final RedditApi _api = RedditApi();

  String _userAvatar = '';
  int _postKarma = 0;
  int _commentKarma = 0;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (!_api.isLoggedIn) return;

    setState(() {
      _isLoading = true;
    });

    final data = await _api.fetchUserInfo();
    if (data != null && mounted) {
      setState(() {
        _postKarma = data['link_karma'] ?? 0;
        _commentKarma = data['comment_karma'] ?? 0;

        final icon = data['icon_img'] ?? '';
        _userAvatar = icon.toString().replaceAll('amp;', '');
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSignOut() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
            'Are you sure you want to sign out from your Reddit account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(context);
              setState(() {
                _isLoading = true;
              });
              await _api.signOut();
              widget.onLoginStateChanged();
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  String _formatKarma(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (!_api.isLoggedIn) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16.0, top: 8.0),
                  child: PressableScale(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppTheme.glassBorder, width: 0.5),
                      ),
                      child: const Icon(Icons.settings_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 32),
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
                                    color: AppTheme.accentOrange
                                        .withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.account_circle_outlined,
                                  color: Colors.white, size: 48),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Unlock Your Profile',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Sign in to sync your upvotes, comment on posts, view your karma, and manage custom feeds.',
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
                                        builder: (context) =>
                                            const LoginScreen()),
                                  );
                                  if (success == true) {
                                    widget.onLoginStateChanged();
                                    _loadUserData();
                                  }
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.warmGradient,
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.radiusMd),
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
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: SpinKitRing(
                  color: AppTheme.accentOrange,
                  size: 44.0,
                  lineWidth: 2.5,
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 95),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    // ─── Profile Header Card ───
                    Container(
                      decoration: AppTheme.cardDecoration(
                          color: AppTheme.surfaceElevated,
                          borderRadius: AppTheme.radiusXl),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            // Avatar with gradient ring
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppTheme.warmGradient,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.accentOrange
                                        .withValues(alpha: 0.25),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 36,
                                backgroundColor: AppTheme.surfaceElevated,
                                backgroundImage: _userAvatar.isNotEmpty
                                    ? CachedNetworkImageProvider(_userAvatar)
                                    : null,
                                child: _userAvatar.isEmpty
                                    ? Icon(Icons.person_rounded,
                                        color: AppTheme.accentOrange, size: 36)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'u/${_api.currentUsername}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 20),
                            // ─── Karma Stat Cards ───
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    Icons.arrow_upward_rounded,
                                    AppTheme.accentOrange,
                                    _formatKarma(_postKarma),
                                    'Post Karma',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    Icons.chat_bubble_rounded,
                                    AppTheme.accentPurple,
                                    _formatKarma(_commentKarma),
                                    'Comment Karma',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ─── Settings Group Title ───
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'SETTINGS & CONFIGURATION',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ─── Settings List ───
                    Container(
                      decoration: AppTheme.cardDecoration(),
                      child: Column(
                        children: [
                          // App Settings
                          PressableScale(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SettingsScreen(),
                                ),
                              );
                            },
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentOrange
                                      .withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(AppTheme.radiusSm),
                                ),
                                child: Icon(Icons.settings_rounded,
                                    color: AppTheme.accentOrange, size: 20),
                              ),
                              title: Text('App Settings',
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              subtitle: Text(
                                  'Theme, location, data saver, and blocks',
                                  style: Theme.of(context).textTheme.bodySmall),
                              trailing: Icon(Icons.chevron_right_rounded,
                                  color: AppTheme.textMuted, size: 20),
                            ),
                          ),
                          Divider(
                              color: AppTheme.glassBorder,
                              height: 1,
                              indent: 16,
                              endIndent: 16),

                          // Help & Support
                          Semantics(
                            identifier: 'btn_help_support',
                            label: 'Help and Support',
                            child: PressableScale(
                              onTap: _showHelpSupportBottomSheet,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentCyan
                                        .withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(AppTheme.radiusSm),
                                  ),
                                  child: Icon(Icons.help_outline_rounded,
                                      color: AppTheme.accentCyan, size: 20),
                                ),
                                title: Text('Help & Support',
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                                trailing: Icon(Icons.chevron_right_rounded,
                                    color: AppTheme.textMuted, size: 20),
                              ),
                            ),
                          ),
                          Divider(
                              color: AppTheme.glassBorder,
                              height: 1,
                              indent: 16,
                              endIndent: 16),

                          // Sign Out
                          PressableScale(
                            onTap: _handleSignOut,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.redAccent.withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(AppTheme.radiusSm),
                                ),
                                child: const Icon(Icons.logout_rounded,
                                    color: Colors.redAccent, size: 20),
                              ),
                              title: Text('Sign Out',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: Colors.redAccent,
                                      )),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatCard(
      IconData icon, Color color, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: AppTheme.glassDecoration(
          opacity: 0.06, borderRadius: AppTheme.radiusMd),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  void _showHelpSupportBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.radiusXl)),
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
                'Help & Support',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how you would like to get in touch or find help.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              
              // Email Support
              _buildSupportOption(
                icon: Icons.mail_outline_rounded,
                title: 'Email Support',
                subtitle: 'Direct contact with developer',
                color: AppTheme.accentCyan,
                onTap: () => _launchURL('mailto:sodukle@gmail.com?subject=Viddit%20Support'),
              ),
              
              // GitHub Issues
              _buildSupportOption(
                icon: Icons.bug_report_outlined,
                title: 'Report a Bug',
                subtitle: 'Submit issues or feedback on GitHub',
                color: AppTheme.accentPurple,
                onTap: () => _launchURL('https://github.com/odukle/Viddit2/issues'),
              ),
              
              // Instagram Support
              _buildSupportOption(
                icon: Icons.camera_alt_outlined,
                title: 'Instagram Profile',
                subtitle: 'Message @odukle on Instagram',
                color: AppTheme.accentOrange,
                onTap: () => _launchURL('https://instagram.com/odukle'),
              ),

              // Privacy Policy
              _buildSupportOption(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                subtitle: 'Read the app\'s privacy policy',
                color: AppTheme.accentWarm,
                onTap: () => _launchURL('https://odukle.com/scroller/privacy.html'),
              ),
              
              const SizedBox(height: 24),
              Text(
                'Version 1.0.0+2 • Made with ❤️',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSupportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      identifier: 'btn_support_${title.toLowerCase().replaceAll(' ', '_')}',
      label: title,
      child: PressableScale(
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: AppTheme.glassBorder,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      final success = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!success && mounted) {
        _showErrorSnackBar('Could not open $urlString');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error opening link: $e');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
