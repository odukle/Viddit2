import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/reddit_api.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/custom_feeds_screen.dart';
import 'screens/profile_screen.dart';
import 'widgets/pressable_scale.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Reddit API client and tokens
  final api = RedditApi();
  await api.init();

  // Load app theme from SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('viddit_theme') ?? 'obsidian';
  AppTheme.selectTheme(savedTheme);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppTheme.themeNotifier,
      builder: (context, themeName, _) {
        return MaterialApp(
          title: 'Scroller',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: const NavigationContainer(),
        );
      },
    );
  }
}

class NavigationContainer extends StatefulWidget {
  const NavigationContainer({super.key});

  @override
  State<NavigationContainer> createState() => _NavigationContainerState();
}

class _NavigationContainerState extends State<NavigationContainer> {
  int _selectedTab = 0;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkEula();
    });
  }

  Future<void> _checkEula() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('viddit_eula_accepted') ?? false;
    if (!accepted) {
      _showEulaDialog();
    }
  }

  void _showEulaDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppTheme.surfaceElevated,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('End User License Agreement',
                style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to Scroller. By using this app, you agree to the following terms regarding User Generated Content (UGC):',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '1. Absolute Moderation:\nPosting, sharing, or encouraging abusive, harassing, threatening, spammy, or illegally explicit content is prohibited.',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '2. Reporting & Blocking:\nScroller provides tools for all users to instantly report objectionable content and block abusive creators. Reported content and posts from blocked users will be hidden from your feed immediately.',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '3. NSFW & Age Restrictions:\nAdult (NSFW) content is filtered and hidden by default. If sensitive or NSFW content appears, you must confirm you are 18+ years of age and explicitly agree to view it via a two-click confirmation prompt.',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Do you accept these terms and conditions?',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  exit(0);
                },
                child: const Text('Decline',
                    style: TextStyle(color: Colors.redAccent)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('viddit_eula_accepted', true);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentOrange),
                child:
                    const Text('Accept', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onTabTapped(int index) {
    if (index == 0 && _selectedTab == 0) {
      _homeKey.currentState?.refreshFeed();
    } else {
      setState(() {
        _selectedTab = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _selectedTab,
        children: [
          HomeScreen(
            key: _homeKey,
            hasBottomNavBar: true,
            isTabActive: _selectedTab == 0,
          ),
          const DiscoverScreen(),
          CustomFeedsScreen(
            isLoggedIn: RedditApi().isLoggedIn,
            isTabActive: _selectedTab == 2,
          ),
          ProfileScreen(onLoginStateChanged: () {
            // Force reload CustomFeeds and Profile when login changes
            setState(() {});
            _homeKey.currentState?.refreshFeed();
          }),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            top: BorderSide(
              color: AppTheme.glassBorder,
              width: 0.5,
            ),
          ),
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              color: AppTheme.surface.withValues(alpha: 0.85),
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                bottom: true,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0, top: 8),
                  child: SizedBox(
                    height: 60,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNavItem(
                            0, Icons.play_circle_fill_rounded, 'Home'),
                        _buildNavItem(1, Icons.explore_rounded, 'Discover'),
                        _buildNavItem(2, Icons.star_rounded, 'Feeds'),
                        _buildNavItem(
                            3, Icons.account_circle_rounded, 'Profile'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedTab == index;
    final activeColor = AppTheme.accentOrange;
    final inactiveColor = AppTheme.textSecondary;

    return Expanded(
      child: PressableScale(
        onTap: () => _onTabTapped(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing gradient pill behind active icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: isSelected ? 18 : 14,
                  vertical: isSelected ? 6 : 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.12),
                            blurRadius: 12,
                            spreadRadius: 0,
                          ),
                        ]
                      : [],
                ),
                // Animated icon size transition
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    icon,
                    color: isSelected ? activeColor : inactiveColor,
                    size: isSelected ? 26 : 22,
                  ),
                ),
              ),
              // Label: visible only for active tab with smooth transition
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isSelected ? 1.0 : 0.0,
                  child: isSelected
                      ? Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              letterSpacing: 0.2,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
