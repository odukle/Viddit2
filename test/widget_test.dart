import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viddit/main.dart';
import 'package:viddit/theme/app_theme.dart';
import 'package:viddit/api/reddit_api.dart';
import 'package:viddit/models/post_model.dart';
import 'package:viddit/widgets/comments_sheet.dart';

void main() {
  setUpAll(() {
    RedditApi.isTesting = true;
  });

  testWidgets('navigation shell renders core tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const NavigationContainer(),
      ),
    );

    await tester.pump();

    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(find.byIcon(Icons.explore_rounded), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(find.byIcon(Icons.account_circle_rounded), findsOneWidget);

    // Let any asynchronous feed loading timers complete
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('profile settings navigation and rendering',
      (WidgetTester tester) async {
    // Initialize SharedPreferences mock
    SharedPreferences.setMockInitialValues({
      'viddit_eula_accepted': true,
    });

    final api = RedditApi();
    await api.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const NavigationContainer(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Navigate to profile tab
    await tester.tap(find.byIcon(Icons.account_circle_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Check settings button presence and tap it
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify SettingsScreen content
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('CONTENT SAFETY'), findsOneWidget);
    expect(find.text('BLOCKED USERS (0)'), findsOneWidget);
    expect(find.text('BLOCKED SUBREDDITS (0)'), findsOneWidget);
  });

  test('safety event notification system filters posts instantly', () async {
    final api = RedditApi();

    // Create dummy posts using correct constructor fields
    final post1 = PostModel(
      id: 'p1',
      fullName: 't3_p1',
      title: 'Post 1',
      author: 'spammer_user',
      subreddit: 'r/funny',
      thumbnail: '',
      isNsfw: false,
      isGif: false,
      score: 100,
      commentCount: 10,
      createdUtc: DateTime.now().millisecondsSinceEpoch / 1000.0,
      permalink: '/r/funny/comments/p1/post_1/',
      videoUrl: 'https://example.com/video1.mp4',
      fallbackVideoUrl: '',
    );
    final post2 = PostModel(
      id: 'p2',
      fullName: 't3_p2',
      title: 'Post 2',
      author: 'good_user',
      subreddit: 'r/annoying_sub',
      thumbnail: '',
      isNsfw: false,
      isGif: false,
      score: 200,
      commentCount: 20,
      createdUtc: DateTime.now().millisecondsSinceEpoch / 1000.0,
      permalink: '/r/annoying_sub/comments/p2/post_2/',
      videoUrl: 'https://example.com/video2.mp4',
      fallbackVideoUrl: '',
    );
    final post3 = PostModel(
      id: 'p3',
      fullName: 't3_p3',
      title: 'Post 3',
      author: 'good_user',
      subreddit: 'r/funny',
      thumbnail: '',
      isNsfw: false,
      isGif: false,
      score: 300,
      commentCount: 30,
      createdUtc: DateTime.now().millisecondsSinceEpoch / 1000.0,
      permalink: '/r/funny/comments/p3/post_3/',
      videoUrl: 'https://example.com/video3.mp4',
      fallbackVideoUrl: '',
    );

    final List<PostModel> posts = [post1, post2, post3];

    // Mock safety settings listener callback
    var callbackTriggered = false;
    api.addSafetyListener(() {
      callbackTriggered = true;
      posts.removeWhere((post) =>
          api.isPostReported(post.id) ||
          api.isUserBlocked(post.author) ||
          api.isSubredditBlocked(post.subreddit));
    });

    // 1. Block spammer_user
    await api.blockUserLocal('spammer_user');
    expect(callbackTriggered, isTrue);
    expect(posts.length, 2);
    expect(posts.contains(post1), isFalse);

    // Reset flag
    callbackTriggered = false;

    // 2. Block r/annoying_sub
    await api.blockSubredditLocal('r/annoying_sub');
    expect(callbackTriggered, isTrue);
    expect(posts.length, 1);
    expect(posts.contains(post2), isFalse);

    // Reset flag
    callbackTriggered = false;

    // 3. Report post3
    await api.reportPostLocal('p3');
    expect(callbackTriggered, isTrue);
    expect(posts.isEmpty, isTrue);
  });

  test('geolocation change triggers safety listeners', () async {
    final api = RedditApi();
    var callbackTriggered = false;
    api.addSafetyListener(() {
      callbackTriggered = true;
    });

    await api.setGeolocation('IN');
    expect(callbackTriggered, isTrue);
    expect(api.geolocation, 'IN');
  });

  testWidgets('popular feed region bottom sheet and search',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'viddit_eula_accepted': true,
    });

    final api = RedditApi();
    await api.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const NavigationContainer(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Navigate to profile tab
    await tester.tap(find.byIcon(Icons.account_circle_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Tap settings
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify Popular Feed Region tile exists and tap it
    expect(find.text('Popular Feed Region'), findsOneWidget);
    await tester.tap(find.text('Popular Feed Region'));
    await tester.pumpAndSettle();

    // Bottom sheet is now open
    expect(find.text('Select Feed Region'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Search for Canada
    await tester.enterText(find.byType(TextField), 'Canada');
    await tester.pumpAndSettle();

    // Canada should be visible in the list, others should be filtered.
    // Note: entering 'Canada' in search text field matches both the input field text and the list item text.
    final canadaListItem = find.descendant(
      of: find.byType(ListView),
      matching: find.text('Canada'),
    );
    expect(canadaListItem, findsOneWidget);
    expect(find.text('Germany'), findsNothing);

    // Select Canada
    await tester.tap(canadaListItem);
    await tester.pumpAndSettle();

    // Bottom sheet should be closed and selected region label should be 'Canada'
    expect(find.text('Select Feed Region'), findsNothing);
    expect(find.text('Canada'), findsOneWidget);
    expect(api.geolocation, 'CA');

    // Let any asynchronous feed loading timers complete
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  group('RedditApi Listing Geolocation URI Builder Tests', () {
    late RedditApi api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      api = RedditApi();
      await api.init();
      api.setDiscoveredSubredditsForTesting(
        'IN',
        'india+indiasocial+indiadiscussion+delhi+mumbai+bangalore+kerala+tamilnadu+hyderabad+pune+kolkata',
      );
    });

    test(
        'AUTO geolocation with detected US defaults to popular feed with US filters',
        () async {
      await api.setGeolocation('AUTO');
      api.detectedCountryCodeForTesting = 'US';
      final uri = api.buildListingUriForTesting(
        feedType: 'popular',
        query: '',
        sort: 'hot',
        params: {'limit': '50'},
      );

      expect(uri.path, contains('/r/popular/hot.json'));
      expect(uri.queryParameters['g'], equals('US'));
      expect(uri.queryParameters['geo_filter'], equals('US'));
    });

    test('AUTO geolocation with detected IN uses curated regional search',
        () async {
      await api.setGeolocation('AUTO');
      api.detectedCountryCodeForTesting = 'IN';
      final uri = api.buildListingUriForTesting(
        feedType: 'popular',
        query: '',
        sort: 'hot',
        params: {'limit': '50'},
      );

      expect(uri.path, contains('/r/india%2Bindiasocial'));
      expect(uri.path, contains('/search.json'));
      expect(uri.queryParameters['restrict_sr'], equals('1'));
      expect(uri.queryParameters['q'], contains('site:v.redd.it'));
    });

    test(
        'GLOBAL geolocation appends g=GLOBAL and geo_filter=GLOBAL parameters to popular feed',
        () async {
      await api.setGeolocation('GLOBAL');
      final uri = api.buildListingUriForTesting(
        feedType: 'popular',
        query: '',
        sort: 'hot',
        params: {'limit': '50'},
      );

      expect(uri.path, contains('/r/popular/hot.json'));
      expect(uri.queryParameters['g'], equals('GLOBAL'));
      expect(uri.queryParameters['geo_filter'], equals('GLOBAL'));
    });

    test('IN geolocation uses curated regional search for popular feed',
        () async {
      await api.setGeolocation('IN');
      final uri = api.buildListingUriForTesting(
        feedType: 'popular',
        query: '',
        sort: 'hot',
        params: {'limit': '50'},
      );

      expect(uri.path, contains('/r/india%2Bindiasocial'));
      expect(uri.path, contains('/search.json'));
      expect(uri.queryParameters['restrict_sr'], equals('1'));
      expect(uri.queryParameters['q'], contains('site:v.redd.it'));
    });

    test(
        'front_page with empty query uses popular feed or curated search depending on country',
        () async {
      await api.setGeolocation('IN');
      final uri = api.buildListingUriForTesting(
        feedType: 'front_page',
        query: '',
        sort: 'new',
        params: {'limit': '50'},
      );

      expect(uri.path, contains('/r/india%2Bindiasocial'));
      expect(uri.path, contains('/search.json'));
      expect(uri.queryParameters['sort'], equals('new'));
    });

    test(
        'front_page with non-empty query uses search endpoint and handles country parameter',
        () async {
      await api.setGeolocation('IN');
      final uri = api.buildListingUriForTesting(
        feedType: 'front_page',
        query: 'flutter+dart',
        sort: 'hot',
        params: {'limit': '50'},
      );

      expect(uri.path, contains('/r/flutter%2Bdart/search.json'));
      expect(uri.queryParameters['g'], equals('IN'));
      expect(uri.queryParameters.containsKey('geo_filter'), isFalse);
    });

    test(
        'unsupported country with dynamically discovered subreddits uses curated search',
        () async {
      await api.setGeolocation('AF');
      api.setDiscoveredSubredditsForTesting('AF', 'afghanistan+kabul');
      final uri = api.buildListingUriForTesting(
        feedType: 'popular',
        query: '',
        sort: 'hot',
        params: {'limit': '50'},
      );

      expect(uri.path, contains('/r/afghanistan%2Bkabul'));
      expect(uri.path, contains('/search.json'));
      expect(uri.queryParameters['restrict_sr'], equals('1'));
      expect(uri.queryParameters['q'], contains('site:v.redd.it'));
    });

    test(
        'AUTO geolocation with detected state/region name uses state/region search',
        () async {
      await api.setGeolocation('AUTO');
      api.detectedCountryCodeForTesting = 'IN';
      api.detectedRegionNameForTesting = 'Karnataka';
      api.setDiscoveredSubredditsForTesting('IN', 'karnataka+bangalore');

      final uri = api.buildListingUriForTesting(
        feedType: 'popular',
        query: '',
        sort: 'hot',
        params: {'limit': '50'},
      );

      expect(uri.path, contains('/r/karnataka%2Bbangalore'));
      expect(uri.path, contains('/search.json'));
      expect(uri.queryParameters['restrict_sr'], equals('1'));
      expect(uri.queryParameters['q'], contains('site:v.redd.it'));
    });
  });

  testWidgets('comments sheet renders search bar and filter chips',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'viddit_eula_accepted': true,
    });

    final api = RedditApi();
    await api.init();

    final post = PostModel(
      id: 'p_test',
      fullName: 't3_p_test',
      title: 'Test Post',
      author: 'test_user',
      subreddit: 'r/test',
      thumbnail: '',
      isNsfw: false,
      isGif: false,
      score: 100,
      commentCount: 5,
      createdUtc: DateTime.now().millisecondsSinceEpoch / 1000.0,
      permalink: '/r/test/comments/p_test/',
      videoUrl: 'https://example.com/video.mp4',
      fallbackVideoUrl: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: CommentsSheet(post: post),
        ),
      ),
    );

    await tester.pump();

    // Verify search bar is visible
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search comments...'), findsOneWidget);

    // Verify filter chips exist
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Questions'), findsOneWidget);
    expect(find.text('Links'), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
    expect(find.text('Positive'), findsOneWidget);
    expect(find.text('Negative'), findsOneWidget);
  });
}
