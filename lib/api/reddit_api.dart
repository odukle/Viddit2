import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/comment_model.dart';
import '../models/multireddit_model.dart';
import '../models/post_model.dart';
import '../models/subreddit_model.dart';

class RedditApi {
  static const String clientId = 'dpM8BKY1nsPNYYwhwpeYIg';
  static const String redirectUri = 'https://odukle.github.io/';
  static const String userAgent = 'Android:com.odukle.scroller:3.2 (by u/odukle)';

  static const String _oauthHost = 'oauth.reddit.com';
  static const String _curatedVideoFeed =
      'videos+funny+gifs+nextfuckinglevel+interestingasfuck+oddlysatisfying+maybemaybemaybe';

  static final RedditApi _instance = RedditApi._internal();
  factory RedditApi() => _instance;
  RedditApi._internal();

  String? _accessToken;
  String? _refreshToken;
  String? _username;
  int? _tokenExpiration;

  String? _guestAccessToken;
  int? _guestTokenExpiration;
  String? _pendingAuthState;
  String? _deviceId;

  String? _lastErrorMessage;
  String? _lastListingAfter;
  List<String>? _subscribedSubreddits;
  List<MultiRedditModel>? _cachedCustomFeeds;

  final Set<String> _blockedUsers = {};
  final Set<String> _blockedSubreddits = {};
  final Set<String> _reportedPostIds = {};
  final Set<String> _reportedCommentIds = {};
  bool _nsfwAllowed = false;
  String _geolocation = 'AUTO';
  String? _detectedCountryCode;

  final List<VoidCallback> _safetyListeners = [];

  void addSafetyListener(VoidCallback listener) {
    _safetyListeners.add(listener);
  }

  void removeSafetyListener(VoidCallback listener) {
    _safetyListeners.remove(listener);
  }

  void _notifySafetyListeners() {
    for (final listener in List<VoidCallback>.from(_safetyListeners)) {
      listener();
    }
  }

  bool get isNsfwAllowed => _nsfwAllowed;
  String get geolocation => _geolocation;
  String? get detectedCountryCode => _detectedCountryCode;

  bool get isLoggedIn =>
      _accessToken != null && _username != null && _username != '<userless>';
  String? get currentUsername => _username;
  String? get lastErrorMessage => _lastErrorMessage;
  String? get lastListingAfter => _lastListingAfter;
  List<String>? get cachedSubscribedSubreddits => _subscribedSubreddits;
  List<MultiRedditModel>? get cachedCustomFeeds => _cachedCustomFeeds;

  bool isSubredditInAnyCustomFeed(String subredditName) {
    if (_cachedCustomFeeds == null) return false;
    final cleanSub = subredditName.replaceAll('r/', '').trim().toLowerCase();
    for (final feed in _cachedCustomFeeds!) {
      for (final sub in feed.subreddits) {
        if (sub.toLowerCase() == cleanSub) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> setGeolocation(String value) async {
    _geolocation = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('geolocation', value);
    _notifySafetyListeners();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
    _username = prefs.getString('username') ?? '<userless>';
    _tokenExpiration = prefs.getInt('token_expiration');
    _pendingAuthState = prefs.getString('oauth_state');

    _deviceId = prefs.getString('device_id');
    if (_deviceId == null || _deviceId!.length < 20) {
      _deviceId = _generateRandomString(24);
      await prefs.setString('device_id', _deviceId!);
    }

    final blocked = prefs.getStringList('viddit_blocked_users') ?? [];
    _blockedUsers.clear();
    _blockedUsers.addAll(blocked.map((u) => u.toLowerCase()));

    final blockedSubs = prefs.getStringList('viddit_blocked_subreddits') ?? [];
    _blockedSubreddits.clear();
    _blockedSubreddits.addAll(blockedSubs.map((s) => s.toLowerCase()));

    final reportedPosts = prefs.getStringList('viddit_reported_posts') ?? [];
    _reportedPostIds.clear();
    _reportedPostIds.addAll(reportedPosts);

    final reportedComments =
        prefs.getStringList('viddit_reported_comments') ?? [];
    _reportedCommentIds.clear();
    _reportedCommentIds.addAll(reportedComments);

    _nsfwAllowed = prefs.getBool('NSFW') ?? false;
    _geolocation = prefs.getString('geolocation') ?? 'AUTO';
    _detectedCountryCode = await _detectUserCountry();

    if (isLoggedIn) {
      await _checkAndRefreshToken();
    }
  }

  String getAuthorizationUrl() {
    _pendingAuthState = _generateRandomString(16);
    _saveOAuthState();

    return 'https://www.reddit.com/api/v1/authorize.compact'
        '?client_id=$clientId'
        '&response_type=code'
        '&state=$_pendingAuthState'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&duration=permanent'
        '&scope=identity,edit,history,read,save,submit,subscribe,vote,mysubreddits';
  }

  Future<bool> handleAuthCallback(String url) async {
    try {
      final uri = Uri.parse(url);
      final error = uri.queryParameters['error'];
      if (error != null) {
        _setError('Reddit sign-in failed: $error');
        return false;
      }

      final code = uri.queryParameters['code'];
      final state = uri.queryParameters['state'];
      if (code == null || state == null || state != _pendingAuthState) {
        _setError('Reddit sign-in returned an invalid authorization response.');
        return false;
      }

      final success = await _exchangeCodeForToken(code);
      if (success) {
        await _clearOAuthState();
        await fetchUserInfo();
      }
      return success;
    } catch (e) {
      _setError('OAuth callback error: $e');
      return false;
    }
  }

  Future<List<PostModel>> fetchPosts({
    required String feedType,
    String query = '',
    String sort = 'hot',
    String time = 'day',
    String after = '',
  }) async {
    _clearRequestState();

    if (feedType == 'front_page' && isLoggedIn) {
      String subAfter = '';
      String popAfter = '';
      if (after.isNotEmpty && after.contains('|')) {
        final parts = after.split('|');
        if (parts.length >= 2) {
          subAfter = parts[0];
          popAfter = parts[1];
        }
      } else if (after.isNotEmpty) {
        subAfter = after;
      }

      final subs = await getSubscribedSubreddits();
      List<PostModel> subPosts = [];
      String nextSubAfter = '';

      if (subs.isNotEmpty) {
        final subListing = await _fetchListing(
          _buildListingUri(
            feedType: 'front_page',
            query: subs.join('+'),
            sort: sort,
            params: {
              'limit': '50',
              'raw_json': '1',
              if (subAfter.isNotEmpty) 'after': subAfter,
              if (sort == 'top') 't': time,
            },
          ),
          requiresAuth: true,
        );
        subPosts = _parsePostsFromListing(subListing);
        nextSubAfter = _lastListingAfter ?? '';
      }

      final popListing = await _fetchListing(
        _buildListingUri(
          feedType: 'popular',
          query: '',
          sort: sort,
          params: {
            'limit': '25',
            'raw_json': '1',
            if (popAfter.isNotEmpty) 'after': popAfter,
            if (sort == 'top') 't': time,
          },
        ),
        requiresAuth: true,
      );
      final popPosts = _parsePostsFromListing(popListing);
      final nextPopAfter = _lastListingAfter ?? '';

      _lastListingAfter = '$nextSubAfter|$nextPopAfter';

      return _blendFeeds(subPosts, popPosts, 3, 1);
    }

    final params = <String, String>{
      'limit': '50',
      'raw_json': '1',
      if (after.isNotEmpty) 'after': after,
      if (sort == 'top') 't': time,
    };

    String activeQuery = query;
    if (feedType == 'front_page' && isLoggedIn) {
      final subs = await getSubscribedSubreddits();
      if (subs.isNotEmpty) {
        activeQuery = subs.join('+');
      }
    }

    final listing = await _fetchListing(
      _buildListingUri(
        feedType: feedType,
        query: activeQuery,
        sort: sort,
        params: params,
      ),
      requiresAuth: isLoggedIn,
    );

    final posts = _parsePostsFromListing(listing);
    if (posts.isNotEmpty || _lastErrorMessage != null || after.isNotEmpty) {
      return posts;
    }

    if (feedType == 'front_page' || feedType == 'popular') {
      final fallbackListing = await _fetchListing(
        _buildCuratedFallbackUri(sort: sort, time: time),
        requiresAuth: isLoggedIn,
      );
      final fallbackPosts = _parsePostsFromListing(fallbackListing);
      if (fallbackPosts.isNotEmpty) {
        _lastErrorMessage = null;
        return fallbackPosts;
      }
    }

    return posts;
  }

  List<PostModel> _blendFeeds(
    List<PostModel> primary,
    List<PostModel> secondary,
    int primaryRatio,
    int secondaryRatio,
  ) {
    final result = <PostModel>[];
    int pIdx = 0;
    int sIdx = 0;

    while (pIdx < primary.length || sIdx < secondary.length) {
      for (int i = 0; i < primaryRatio && pIdx < primary.length; i++) {
        result.add(primary[pIdx++]);
      }
      for (int i = 0; i < secondaryRatio && sIdx < secondary.length; i++) {
        result.add(secondary[sIdx++]);
      }
    }
    return result;
  }

  Future<SubredditModel> fetchSubredditAbout(String subredditName) async {
    _clearRequestState();
    final cleanName = subredditName.replaceAll('r/', '').trim();
    final uri = Uri.https(
      _oauthHost,
      '/r/$cleanName/about.json',
      {'raw_json': '1'},
    );

    final data = await _sendJsonRequest(
      uri,
      requiresAuth: false,
    );
    if (data is Map<String, dynamic>) {
      return SubredditModel.fromJson(data);
    }
    return SubredditModel.empty();
  }

  Future<Map<String, dynamic>> fetchUserAbout(String userName) async {
    _clearRequestState();
    final cleanName = userName.replaceAll('u/', '').trim();
    final uri = Uri.https(
      _oauthHost,
      '/user/$cleanName/about.json',
      {'raw_json': '1'},
    );

    final data = await _sendJsonRequest(
      uri,
      requiresAuth: false,
    );
    if (data is Map<String, dynamic>) {
      return data['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    }
    return {};
  }

  Future<List<CommentModel>> fetchComments(String permalink) async {
    _clearRequestState();
    final cleanPermalink = permalink.endsWith('/')
        ? permalink.substring(0, permalink.length - 1)
        : permalink;
    final baseUri = Uri.parse(
      'https://$_oauthHost$cleanPermalink.json?raw_json=1',
    );

    final data = await _sendJsonRequest(baseUri, requiresAuth: false);
    if (data is List && data.length > 1) {
      final children = data[1]['data']?['children'] as List? ?? [];
      final comments = <CommentModel>[];
      for (final child in children) {
        if (child['kind'] == 't1') {
          final comment = CommentModel.fromJson(child);
          comments.add(comment);
        }
      }
      return comments;
    }
    return [];
  }

  Future<bool> vote(String postFullName, int direction) async {
    if (!isLoggedIn) return false;
    _clearRequestState();

    final response = await _sendRequest(
      'POST',
      Uri.parse('https://$_oauthHost/api/vote'),
      requiresAuth: true,
      body: {
        'id': postFullName,
        'dir': direction.toString(),
      },
    );

    return response?.statusCode == 200;
  }

  Future<List<Map<String, String>>> searchSubreddits(
      String query, bool nsfw) async {
    _clearRequestState();
    final params = <String, String>{
      'q': query,
      'include_over_18': nsfw ? 'on' : 'off',
      'raw_json': '1',
      'limit': '25',
    };
    final countryCode = _getEffectiveCountryCode();
    if (countryCode != null && countryCode != 'GLOBAL') {
      params['g'] = countryCode;
    }

    final uri = Uri.https(
      _oauthHost,
      '/subreddits/search.json',
      params,
    );

    final data = await _sendJsonRequest(uri, requiresAuth: false);
    if (data is! Map<String, dynamic>) return [];

    final children = data['data']?['children'] as List? ?? [];
    return children
        .map((child) => child['data'] as Map<String, dynamic>? ?? {})
        .where((sub) {
          if (!nsfw) {
            final isNsfw = sub['over18'] == true ||
                sub['over_18'] == true ||
                sub['subreddit_type'] == 'nsfw';
            if (isNsfw) return false;
          }
          return true;
        })
        .map((sub) {
          var icon = (sub['icon_img'] ?? '').toString();
          if (icon.isEmpty || icon == 'null') {
            icon = (sub['community_icon'] ?? '').toString();
          }
          icon = icon.replaceAll('amp;', '');
          final name = (sub['display_name_prefixed'] ?? '').toString();
          if (name.isEmpty) return null;

          var subscribersStr = '';
          final subscribers = sub['subscribers'];
          if (subscribers is num) {
            if (subscribers >= 1000000) {
              subscribersStr = '${(subscribers / 1000000).toStringAsFixed(1)}M';
            } else if (subscribers >= 1000) {
              subscribersStr = '${(subscribers / 1000).toStringAsFixed(1)}K';
            } else {
              subscribersStr = subscribers.toString();
            }
          }

          return {
            'name': name,
            'icon': icon,
            'subscribers': subscribersStr,
          };
        })
        .whereType<Map<String, String>>()
        .toList();
  }

  Future<List<Map<String, String>>> fetchTrendingSubreddits() async {
    final countryCode = _getEffectiveCountryCode();
    if (countryCode != null &&
        countryCode != 'GLOBAL' &&
        _curatedRegionalSubreddits.containsKey(countryCode)) {
      try {
        final subredditsStr = _curatedRegionalSubreddits[countryCode]!;
        final srNames = subredditsStr.replaceAll('+', ',');

        final uri = Uri.https(
          _oauthHost,
          '/api/info.json',
          {'sr_name': srNames, 'raw_json': '1'},
        );

        final data = await _sendJsonRequest(uri, requiresAuth: false);
        if (data is Map<String, dynamic>) {
          final children = data['data']?['children'] as List? ?? [];
          final list = <Map<String, String>>[];
          for (final child in children) {
            final sub = child['data'] as Map<String, dynamic>? ?? {};
            var icon = (sub['icon_img'] ?? '').toString();
            if (icon.isEmpty || icon == 'null') {
              icon = (sub['community_icon'] ?? '').toString();
            }
            icon = icon.replaceAll('amp;', '');
            final name = (sub['display_name_prefixed'] ?? '').toString();

            var subscribersStr = '';
            final subscribers = sub['subscribers'];
            if (subscribers is num) {
              if (subscribers >= 1000000) {
                subscribersStr =
                    '${(subscribers / 1000000).toStringAsFixed(1)}M';
              } else if (subscribers >= 1000) {
                subscribersStr = '${(subscribers / 1000).toStringAsFixed(1)}K';
              } else {
                subscribersStr = subscribers.toString();
              }
            }

            if (name.isNotEmpty) {
              list.add({
                'name': name,
                'icon': icon,
                'subscribers': subscribersStr,
              });
            }
          }
          if (list.isNotEmpty) return list;
        }
      } catch (e) {
        debugPrint('Failed to fetch regional trending subreddits: $e');
      }
    }

    final url = Uri.parse(
      'https://parsehub.com/api/v2/projects/tFUsBtX0e0CL/last_ready_run/data?api_key=t0GcPvB4jaai&format=json',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final subreddits = data['growing'] as List? ?? [];
        final list = <Map<String, String>>[];
        for (final sub in subreddits) {
          final image = (sub['image'] ?? '').toString().replaceAll('amp;', '');
          final urlStr = (sub['url'] ?? '').toString();
          final name = urlStr
              .replaceFirst('https://www.reddit.com/', '')
              .replaceAll('/', '');

          if (name.isNotEmpty) {
            list.add({'name': 'r/$name', 'icon': image});
          }
        }
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    return [
      {'name': 'r/videos', 'icon': ''},
      {'name': 'r/gifs', 'icon': ''},
      {'name': 'r/nextfuckinglevel', 'icon': ''},
      {'name': 'r/interestingasfuck', 'icon': ''},
      {'name': 'r/aww', 'icon': ''},
      {'name': 'r/unexpected', 'icon': ''},
      {'name': 'r/oddlysatisfying', 'icon': ''},
      {'name': 'r/maybemaybemaybe', 'icon': ''},
      {'name': 'r/funny', 'icon': ''},
      {'name': 'r/dankmemes', 'icon': ''},
    ];
  }

  Future<List<MultiRedditModel>> fetchCustomFeeds() async {
    if (!isLoggedIn) return [];
    _clearRequestState();

    final data = await _sendJsonRequest(
      Uri.parse('https://$_oauthHost/api/multi/mine?raw_json=1'),
      requiresAuth: true,
    );

    if (data is List) {
      final list = data.map((item) => MultiRedditModel.fromJson(item)).toList();
      _cachedCustomFeeds = list;
      return list;
    }
    return [];
  }

  Future<MultiRedditModel?> createCustomFeed(String displayName) async {
    if (!isLoggedIn) return null;
    _clearRequestState();

    final name = displayName.replaceAll(' ', '').trim();
    final response = await _sendRequest(
      'POST',
      Uri.parse('https://$_oauthHost/api/multi/user/$_username/m/$name'),
      requiresAuth: true,
      body: {
        'model': jsonEncode({
          'display_name': displayName,
          'description_md': 'Custom feed created in Scroller',
          'icon_name': 'png',
          'visibility': 'private',
        }),
      },
    );

    if (response == null ||
        (response.statusCode != 200 && response.statusCode != 201)) {
      return null;
    }

    final data = _decodeJsonBody(response.body);
    if (data is Map<String, dynamic>) {
      final newFeed = MultiRedditModel.fromJson(data);
      if (_cachedCustomFeeds != null) {
        _cachedCustomFeeds!.add(newFeed);
      }
      return newFeed;
    }
    return null;
  }

  Future<bool> deleteCustomFeed(String feedName) async {
    if (!isLoggedIn) return false;
    _clearRequestState();

    final response = await _sendRequest(
      'DELETE',
      Uri.parse('https://$_oauthHost/api/multi/user/$_username/m/$feedName'),
      requiresAuth: true,
    );
    final success = response?.statusCode == 200;
    if (success && _cachedCustomFeeds != null) {
      _cachedCustomFeeds!.removeWhere((feed) => feed.name == feedName);
    }
    return success;
  }

  Future<bool> addSubredditToCustomFeed(
      String feedName, String subredditName) async {
    if (!isLoggedIn) return false;
    _clearRequestState();

    final cleanSub = subredditName.replaceAll('r/', '').trim();
    final response = await _sendRequest(
      'PUT',
      Uri.parse(
          'https://$_oauthHost/api/multi/user/$_username/m/$feedName/r/$cleanSub'),
      requiresAuth: true,
      body: {
        'model': jsonEncode({'name': cleanSub})
      },
    );

    final success = response?.statusCode == 200 || response?.statusCode == 201;
    if (success && _cachedCustomFeeds != null) {
      for (var i = 0; i < _cachedCustomFeeds!.length; i++) {
        final feed = _cachedCustomFeeds![i];
        if (feed.name == feedName) {
          if (!feed.subreddits.contains(cleanSub)) {
            final updatedSubs = List<String>.from(feed.subreddits)
              ..add(cleanSub);
            _cachedCustomFeeds![i] = MultiRedditModel(
              name: feed.name,
              displayName: feed.displayName,
              iconUrl: feed.iconUrl,
              subreddits: updatedSubs,
            );
          }
          break;
        }
      }
    }
    return success;
  }

  Future<bool> removeSubredditFromCustomFeed(
      String feedName, String subredditName) async {
    if (!isLoggedIn) return false;
    _clearRequestState();

    final cleanSub = subredditName.replaceAll('r/', '').trim();
    final response = await _sendRequest(
      'DELETE',
      Uri.parse(
          'https://$_oauthHost/api/multi/user/$_username/m/$feedName/r/$cleanSub'),
      requiresAuth: true,
    );

    final success = response?.statusCode == 200;
    if (success && _cachedCustomFeeds != null) {
      for (var i = 0; i < _cachedCustomFeeds!.length; i++) {
        final feed = _cachedCustomFeeds![i];
        if (feed.name == feedName) {
          if (feed.subreddits.contains(cleanSub)) {
            final updatedSubs = List<String>.from(feed.subreddits)
              ..remove(cleanSub);
            _cachedCustomFeeds![i] = MultiRedditModel(
              name: feed.name,
              displayName: feed.displayName,
              iconUrl: feed.iconUrl,
              subreddits: updatedSubs,
            );
          }
          break;
        }
      }
    }
    return success;
  }

  Future<bool> subscribeSubreddit(String subredditName, bool subscribe) async {
    if (!isLoggedIn) return false;
    _clearRequestState();

    final cleanSub = subredditName.replaceAll('r/', '').trim();
    final response = await _sendRequest(
      'POST',
      Uri.parse('https://$_oauthHost/api/subscribe'),
      requiresAuth: true,
      body: {
        'action': subscribe ? 'sub' : 'unsub',
        'sr_name': cleanSub,
      },
    );

    if (response?.statusCode == 200) {
      if (subscribe) {
        _subscribedSubreddits?.add(cleanSub);
      } else {
        _subscribedSubreddits?.remove(cleanSub);
      }
      return true;
    }
    return false;
  }

  Future<CommentModel?> postComment(String parentFullName, String text) async {
    if (!isLoggedIn) return null;
    _clearRequestState();

    final response = await _sendRequest(
      'POST',
      Uri.parse('https://$_oauthHost/api/comment'),
      requiresAuth: true,
      body: {
        'thing_id': parentFullName,
        'text': text,
        'api_type': 'json',
      },
    );

    if (response?.statusCode == 200 && response?.body != null) {
      final decoded = _decodeJsonBody(response!.body);
      if (decoded is Map<String, dynamic>) {
        final jsonNode = decoded['json'];
        final errors = jsonNode?['errors'] as List? ?? [];
        if (errors.isNotEmpty) {
          final firstError = errors.first;
          if (firstError is List && firstError.length > 1) {
            _setError(firstError[1].toString());
          } else {
            _setError('Reddit returned an error: $errors');
          }
          return null;
        }

        final things = jsonNode?['data']?['things'] as List? ?? [];
        if (things.isNotEmpty) {
          final firstThing = things.first;
          if (firstThing['kind'] == 't1') {
            return CommentModel.fromJson(firstThing as Map<String, dynamic>);
          }
        }
      }
    }
    return null;
  }

  Future<bool> deleteComment(String commentFullName) async {
    if (!isLoggedIn) return false;
    _clearRequestState();

    final response = await _sendRequest(
      'POST',
      Uri.parse('https://$_oauthHost/api/del'),
      requiresAuth: true,
      body: {
        'id': commentFullName,
      },
    );

    return response?.statusCode == 200;
  }

  Future<CommentModel?> editComment(
      String commentFullName, String newText) async {
    if (!isLoggedIn) return null;
    _clearRequestState();

    final response = await _sendRequest(
      'POST',
      Uri.parse('https://$_oauthHost/api/editusertext'),
      requiresAuth: true,
      body: {
        'thing_id': commentFullName,
        'text': newText,
        'api_type': 'json',
      },
    );

    if (response?.statusCode == 200 && response?.body != null) {
      final decoded = _decodeJsonBody(response!.body);
      if (decoded is Map<String, dynamic>) {
        final jsonNode = decoded['json'];
        final errors = jsonNode?['errors'] as List? ?? [];
        if (errors.isNotEmpty) {
          final firstError = errors.first;
          if (firstError is List && firstError.length > 1) {
            _setError(firstError[1].toString());
          } else {
            _setError('Reddit returned an error: $errors');
          }
          return null;
        }

        final things = jsonNode?['data']?['things'] as List? ?? [];
        if (things.isNotEmpty) {
          final firstThing = things.first;
          if (firstThing['kind'] == 't1') {
            return CommentModel.fromJson(firstThing as Map<String, dynamic>);
          }
        }
      }
    }
    return null;
  }

  Future<void> setNsfwAllowed(bool value) async {
    _nsfwAllowed = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('NSFW', value);
  }

  bool isUserBlocked(String username) =>
      _blockedUsers.contains(username.toLowerCase());
  bool isSubredditBlocked(String subreddit) => _blockedSubreddits
      .contains(subreddit.replaceAll('r/', '').trim().toLowerCase());
  bool isPostReported(String postId) => _reportedPostIds.contains(postId);
  bool isCommentReported(String commentId) =>
      _reportedCommentIds.contains(commentId);

  Set<String> get blockedUsersList => _blockedUsers;
  Set<String> get blockedSubredditsList => _blockedSubreddits;

  Future<void> blockUserLocal(String username) async {
    final clean = username.replaceAll('u/', '').trim().toLowerCase();
    _blockedUsers.add(clean);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('viddit_blocked_users', _blockedUsers.toList());
    _notifySafetyListeners();
  }

  Future<void> unblockUserLocal(String username) async {
    final clean = username.replaceAll('u/', '').trim().toLowerCase();
    _blockedUsers.remove(clean);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('viddit_blocked_users', _blockedUsers.toList());
    _notifySafetyListeners();
  }

  Future<void> blockSubredditLocal(String subreddit) async {
    final clean = subreddit.replaceAll('r/', '').trim().toLowerCase();
    _blockedSubreddits.add(clean);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'viddit_blocked_subreddits', _blockedSubreddits.toList());
    _notifySafetyListeners();
  }

  Future<void> unblockSubredditLocal(String subreddit) async {
    final clean = subreddit.replaceAll('r/', '').trim().toLowerCase();
    _blockedSubreddits.remove(clean);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'viddit_blocked_subreddits', _blockedSubreddits.toList());
    _notifySafetyListeners();
  }

  Future<void> reportPostLocal(String postId) async {
    _reportedPostIds.add(postId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'viddit_reported_posts', _reportedPostIds.toList());
    _notifySafetyListeners();
  }

  Future<void> reportCommentLocal(String commentId) async {
    _reportedCommentIds.add(commentId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'viddit_reported_comments', _reportedCommentIds.toList());
    _notifySafetyListeners();
  }

  Future<bool> reportThing(String thingId, String reason) async {
    if (!isLoggedIn) return false;
    _clearRequestState();

    final response = await _sendRequest(
      'POST',
      Uri.parse('https://$_oauthHost/api/report'),
      requiresAuth: true,
      body: {
        'thing_id': thingId,
        'reason': reason,
        'api_type': 'json',
      },
    );

    return response?.statusCode == 200;
  }

  Future<bool> blockUser(String username) async {
    if (!isLoggedIn) return false;
    _clearRequestState();

    final response = await _sendRequest(
      'POST',
      Uri.parse('https://$_oauthHost/api/block_user'),
      requiresAuth: true,
      body: {
        'name': username.replaceAll('u/', '').trim(),
        'api_type': 'json',
      },
    );

    return response?.statusCode == 200;
  }

  Future<Map<String, dynamic>?> fetchUserInfo() async {
    if (_accessToken == null) return null;
    _clearRequestState();

    final data = await _sendJsonRequest(
      Uri.parse('https://$_oauthHost/api/v1/me'),
      requiresAuth: true,
    );

    if (data is! Map<String, dynamic>) return null;

    _username = data['name']?.toString();
    if (_username == null || _username!.isEmpty) {
      _setError('Reddit did not return a valid username for this account.');
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', _username!);
    return data;
  }

  Future<List<String>> getSubscribedSubreddits() async {
    if (!isLoggedIn) return [];
    if (_subscribedSubreddits != null) return _subscribedSubreddits!;

    try {
      final subreddits = <String>[];
      final uri = Uri.https(
        _oauthHost,
        '/subreddits/mine/subscriber.json',
        {
          'limit': '100',
          'raw_json': '1',
        },
      );

      final data = await _sendJsonRequest(uri, requiresAuth: true);
      if (data is Map<String, dynamic>) {
        final children = data['data']?['children'] as List? ?? [];
        for (final child in children) {
          final name = child['data']?['display_name']?.toString();
          if (name != null && name.isNotEmpty) {
            subreddits.add(name);
          }
        }
      }
      _subscribedSubreddits = subreddits;
      return _subscribedSubreddits!;
    } catch (e) {
      debugPrint('Error fetching subscribed subreddits: $e');
      return [];
    }
  }

  Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _username = '<userless>';
    _tokenExpiration = null;
    _subscribedSubreddits = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('username');
    await prefs.remove('token_expiration');
  }

  Future<bool> checkRedditSaveAudio(String permalink) async {
    final url = Uri.parse(
        'https://redditsave.com/info?url=https://www.reddit.com$permalink');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return !response.body.contains('audio_url=false');
      }
    } catch (_) {}
    return true;
  }

  Future<void> _ensureGuestToken() async {
    if (isLoggedIn) return;

    if (_guestAccessToken != null && _guestTokenExpiration != null) {
      final isExpired = DateTime.now().millisecondsSinceEpoch >
          (_guestTokenExpiration! - 300000);
      if (!isExpired) return;
    }

    final tokenUrl = Uri.parse('https://www.reddit.com/api/v1/access_token');
    final basicAuth = 'Basic ${base64Encode(utf8.encode('$clientId:'))}';

    final deviceId = _deviceId ?? _generateRandomString(24);

    final response = await http.post(
      tokenUrl,
      headers: {
        'User-Agent': userAgent,
        'Authorization': basicAuth,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'https://oauth.reddit.com/grants/installed_client',
        'device_id': deviceId,
      },
    );

    if (response.statusCode != 200) {
      _setError(_responseErrorMessage(response.statusCode, response.body));
      return;
    }

    final data = _decodeJsonBody(response.body);
    if (data is! Map<String, dynamic>) return;

    _guestAccessToken = data['access_token']?.toString();
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 86400;
    _guestTokenExpiration =
        DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch;
  }

  Future<bool> _exchangeCodeForToken(String code) async {
    final tokenUrl = Uri.parse('https://www.reddit.com/api/v1/access_token');
    final basicAuth = 'Basic ${base64Encode(utf8.encode('$clientId:'))}';

    final response = await http.post(
      tokenUrl,
      headers: {
        'User-Agent': userAgent,
        'Authorization': basicAuth,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
      },
    );

    if (response.statusCode != 200) {
      _setError(_responseErrorMessage(response.statusCode, response.body));
      return false;
    }

    final data = _decodeJsonBody(response.body);
    if (data is! Map<String, dynamic>) return false;

    _accessToken = data['access_token']?.toString();
    _refreshToken = data['refresh_token']?.toString() ?? _refreshToken;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
    _tokenExpiration =
        DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch;
    _subscribedSubreddits = null;

    await _saveCredentials();
    return true;
  }

  Future<void> _checkAndRefreshToken() async {
    if (_refreshToken == null || _tokenExpiration == null) return;

    final needsRefresh =
        DateTime.now().millisecondsSinceEpoch > (_tokenExpiration! - 300000);
    if (!needsRefresh) return;

    final tokenUrl = Uri.parse('https://www.reddit.com/api/v1/access_token');
    final basicAuth = 'Basic ${base64Encode(utf8.encode('$clientId:'))}';

    final response = await http.post(
      tokenUrl,
      headers: {
        'User-Agent': userAgent,
        'Authorization': basicAuth,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
      },
    );

    if (response.statusCode != 200) {
      _setError(_responseErrorMessage(response.statusCode, response.body));
      return;
    }

    final data = _decodeJsonBody(response.body);
    if (data is! Map<String, dynamic>) return;

    _accessToken = data['access_token']?.toString();
    if (data['refresh_token'] != null) {
      _refreshToken = data['refresh_token'].toString();
    }
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
    _tokenExpiration =
        DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch;

    await _saveCredentials();
  }

  Future<http.Response?> _sendRequest(
    String method,
    Uri uri, {
    required bool requiresAuth,
    Map<String, String>? body,
    bool retryOnUnauthorized = true,
  }) async {
    try {
      final headers = await _buildHeaders(
          requiresAuth: requiresAuth, isFormRequest: body != null, uri: uri);

      late http.Response response;
      switch (method) {
        case 'POST':
          response = await http.post(uri, headers: headers, body: body);
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: body);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
          break;
        default:
          response = await http.get(uri, headers: headers);
      }

      if (response.statusCode == 401 &&
          requiresAuth &&
          retryOnUnauthorized &&
          _refreshToken != null) {
        await _checkAndRefreshToken();
        return _sendRequest(
          method,
          uri,
          requiresAuth: requiresAuth,
          body: body,
          retryOnUnauthorized: false,
        );
      }

      if (response.statusCode >= 400) {
        _setError(_responseErrorMessage(response.statusCode, response.body));
      }

      return response;
    } catch (e) {
      _setError('Network error while contacting Reddit: $e');
      return null;
    }
  }

  Future<dynamic> _sendJsonRequest(
    Uri uri, {
    required bool requiresAuth,
  }) async {
    final response = await _sendRequest('GET', uri, requiresAuth: requiresAuth);
    if (response == null || response.statusCode != 200) {
      return null;
    }
    return _decodeJsonBody(response.body);
  }

  Future<Map<String, dynamic>?> _fetchListing(
    Uri uri, {
    required bool requiresAuth,
  }) async {
    final data = await _sendJsonRequest(uri, requiresAuth: requiresAuth);
    if (data is! Map<String, dynamic>) return null;
    return data;
  }

  Uri _buildApiUri(String path, Map<String, String> params,
      {bool usePublicHost = false}) {
    final encodedPath = path.replaceAll('+', '%2B');
    final host = usePublicHost ? 'www.reddit.com' : _oauthHost;
    if (params.isEmpty) {
      return Uri.parse('https://$host$encodedPath');
    }
    final queryStr = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return Uri.parse('https://$host$encodedPath?$queryStr');
  }

  static const Map<String, String> _curatedRegionalSubreddits = {
    'IN':
        'india+indiasocial+indiadiscussion+delhi+mumbai+bangalore+kerala+tamilnadu+hyderabad+pune+kolkata',
    'GB': 'unitedkingdom+casualuk+askuk+britishproblems+london+scotland+wales',
    'CA':
        'canada+onguardforthee+askacanadian+toronto+vancouver+montreal+alberta',
    'AU': 'australia+melbourne+sydney+brisbane+perth+casualaustralia',
    'DE': 'de+ich_iel+fragreddit+berlin+germany',
    'FR': 'france+rance+askfrance+paris',
    'BR': 'brasil+brazil+saopaulo+riodejaneiro',
    'JP': 'japan+japanlife+askjapan+tokyo',
    'MX': 'mexico+mexico_city+monterrey+guadalajara',
    'ES': 'spain+espana+barcelona+madrid',
    'IT': 'italy+italia+roma+milano',
    'RU': 'russia+pikabu',
    'NL': 'netherlands+thenetherlands+amsterdam',
    'SG': 'singapore+asksingapore',
    'NZ': 'newzealand+auckland+wellington',
    'PH': 'philippines+filipino',
    'ZA': 'southafrica+johannesburg+capetown',
    'IE': 'ireland+dublin',
    'MY': 'malaysia+kualalumpur',
  };

  Uri _buildListingUri({
    required String feedType,
    required String query,
    required String sort,
    required Map<String, String> params,
  }) {
    const String videoSearchQuery =
        'self:no (site:v.redd.it OR site:gfycat.com OR site:imgur.com OR site:redgifs.com)';

    switch (feedType) {
      case 'front_page':
        if (query.isNotEmpty) {
          final searchParams = Map<String, String>.from(params);
          searchParams['q'] = videoSearchQuery;
          searchParams['sort'] = sort;
          searchParams['restrict_sr'] = '1';
          final countryCode = _getEffectiveCountryCode();
          if (countryCode != null && countryCode != 'GLOBAL') {
            searchParams['g'] = countryCode;
          }
          return _buildApiUri('/r/$query/search.json', searchParams);
        } else {
          final countryCode = _getEffectiveCountryCode();
          if (countryCode != null &&
              _curatedRegionalSubreddits.containsKey(countryCode)) {
            final searchParams = Map<String, String>.from(params);
            searchParams['q'] = videoSearchQuery;
            searchParams['sort'] = sort;
            searchParams['restrict_sr'] = '1';
            final subreddits = _curatedRegionalSubreddits[countryCode]!;
            return _buildApiUri('/r/$subreddits/search.json', searchParams);
          } else {
            final listingParams = Map<String, String>.from(params);
            if (countryCode != null) {
              listingParams['g'] = countryCode;
              listingParams['geo_filter'] = countryCode;
            }
            return _buildApiUri('/r/popular/$sort.json', listingParams);
          }
        }
      case 'popular':
        final countryCode = _getEffectiveCountryCode();
        if (countryCode != null &&
            _curatedRegionalSubreddits.containsKey(countryCode)) {
          final searchParams = Map<String, String>.from(params);
          searchParams['q'] = videoSearchQuery;
          searchParams['sort'] = sort;
          searchParams['restrict_sr'] = '1';
          final subreddits = _curatedRegionalSubreddits[countryCode]!;
          return _buildApiUri('/r/$subreddits/search.json', searchParams);
        } else {
          final listingParams = Map<String, String>.from(params);
          if (countryCode != null) {
            listingParams['g'] = countryCode;
            listingParams['geo_filter'] = countryCode;
          }
          return _buildApiUri('/r/popular/$sort.json', listingParams);
        }
      case 'subreddit':
        final searchParams = Map<String, String>.from(params);
        searchParams['q'] = videoSearchQuery;
        searchParams['restrict_sr'] = '1';
        searchParams['sort'] = sort;
        return _buildApiUri('/r/$query/search.json', searchParams);
      case 'user':
        return _buildApiUri(
          '/user/$query/submitted.json',
          params,
          usePublicHost: !isLoggedIn,
        );
      case 'custom_feed':
        final searchParams = Map<String, String>.from(params);
        searchParams['q'] = videoSearchQuery;
        searchParams['restrict_sr'] = '1';
        searchParams['sort'] = sort;
        final path = query.startsWith('user/')
            ? '/$query/search.json'
            : '/user/$_username/m/$query/search.json';
        return _buildApiUri(path, searchParams);
      default:
        return _buildApiUri('/best.json', params);
    }
  }

  String? _getEffectiveCountryCode() {
    if (_geolocation == 'AUTO') {
      return _detectedCountryCode;
    } else if (_geolocation == 'GLOBAL') {
      return 'GLOBAL';
    } else {
      return _geolocation;
    }
  }

  Future<String> _detectUserCountry() async {
    // 1. Try IP-based geolocation via ipapi.co
    try {
      final response = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data.containsKey('country_code')) {
          final code = data['country_code']?.toString().toUpperCase();
          if (code != null && code.length == 2) {
            return code;
          }
        }
      }
    } catch (e) {
      debugPrint('IP geolocation error: $e');
    }

    // 2. Fallback to timezone offset mapping
    final offset = DateTime.now().timeZoneOffset;
    final minutes = offset.inMinutes;

    if (minutes == 330) {
      return 'IN'; // UTC+5:30 (India)
    }
    if (minutes == 345) {
      return 'NP'; // UTC+5:45 (Nepal)
    }
    if (minutes == 360) {
      return 'BD'; // UTC+6:00 (Bangladesh)
    }
    if (minutes == 480) {
      return 'SG'; // UTC+8:00 (Singapore / Malaysia / China)
    }
    if (minutes == 540) {
      return 'JP'; // UTC+9:00 (Japan / Korea)
    }
    if (minutes == 420) {
      return 'TH'; // UTC+7:00 (Thailand / Vietnam / Indonesia)
    }
    if (minutes == 120) {
      return 'ZA'; // UTC+2:00 (South Africa / Eastern Europe)
    }
    if (minutes == 60) {
      return 'DE'; // UTC+1:00 (Germany / France / Western Europe)
    }
    if (minutes == 0) {
      return 'GB'; // UTC+0:00 (United Kingdom)
    }
    if (minutes == 240) {
      return 'AE'; // UTC+4:00 (UAE)
    }
    if (minutes == 180) {
      return 'SA'; // UTC+3:00 (Saudi Arabia / East Africa)
    }

    // 3. Fallback to system locale
    try {
      final code = PlatformDispatcher.instance.locale.countryCode;
      if (code != null && code.isNotEmpty) {
        return code.toUpperCase();
      }
    } catch (_) {}

    return 'US'; // Default fallback
  }

  Uri _buildCuratedFallbackUri({
    required String sort,
    required String time,
  }) {
    return _buildApiUri('/r/$_curatedVideoFeed/search.json', {
      'q':
          'self:no (site:v.redd.it OR site:gfycat.com OR site:imgur.com OR site:redgifs.com)',
      'restrict_sr': '1',
      'sort': sort,
      'limit': '50',
      'raw_json': '1',
      if (sort == 'top') 't': time,
    });
  }

  List<PostModel> _parsePostsFromListing(Map<String, dynamic>? listing) {
    if (listing == null) return [];

    _lastListingAfter = listing['data']?['after']?.toString();
    final children = listing['data']?['children'] as List? ?? [];
    final posts = <PostModel>[];
    final seenIds = <String>{};

    for (final child in children) {
      final post = PostModel.fromJson(child as Map<String, dynamic>);
      if (post.id.isEmpty ||
          !post.isPlayableVideo ||
          seenIds.contains(post.id)) {
        continue;
      }

      // Filter out NSFW posts if globally disabled
      if (post.isNsfw && !_nsfwAllowed) {
        continue;
      }

      // Handled in UI: Filter out reported posts, posts by blocked users, and blocked subreddits at the widget layer

      seenIds.add(post.id);
      posts.add(post);
    }

    return posts;
  }

  Future<Map<String, String>> _buildHeaders({
    required bool requiresAuth,
    bool isFormRequest = false,
    Uri? uri,
  }) async {
    // If the request is to www.reddit.com (public endpoint), do not send any OAuth Authorization headers
    if (uri != null && uri.host != _oauthHost) {
      return {
        'User-Agent': userAgent,
        'Accept': 'application/json',
      };
    }

    if (requiresAuth) {
      await _checkAndRefreshToken();
    } else if (!isLoggedIn) {
      await _ensureGuestToken();
    }

    final token = requiresAuth
        ? _accessToken
        : (isLoggedIn ? _accessToken : _guestAccessToken);
    return {
      'User-Agent': userAgent,
      if (token != null) 'Authorization': 'bearer $token',
      if (isFormRequest) 'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    };
  }

  dynamic _decodeJsonBody(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) {
      _setError('Reddit returned an empty response.');
      return null;
    }

    if (trimmed.startsWith('<')) {
      _setError(_responseErrorMessage(403, body));
      return null;
    }

    try {
      return jsonDecode(body);
    } catch (e) {
      _setError('Reddit returned malformed JSON: $e');
      return null;
    }
  }

  String _responseErrorMessage(int statusCode, String body) {
    final lowerBody = body.toLowerCase();
    if (lowerBody.contains('blocked by network security')) {
      return 'Reddit is blocking requests from this network right now. Try a different connection or sign in again later.';
    }
    if (statusCode == 401) {
      return 'Reddit authentication expired. Please sign in again.';
    }
    if (statusCode == 403) {
      return 'Reddit denied this request. This can happen because of API restrictions, missing scopes, or network security filtering.';
    }
    if (statusCode == 429) {
      return 'Reddit rate-limited the app. Wait a moment and try again.';
    }
    return 'Reddit request failed with HTTP $statusCode.';
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) {
      await prefs.setString('access_token', _accessToken!);
    }
    if (_refreshToken != null) {
      await prefs.setString('refresh_token', _refreshToken!);
    }
    if (_username != null) {
      await prefs.setString('username', _username!);
    }
    if (_tokenExpiration != null) {
      await prefs.setInt('token_expiration', _tokenExpiration!);
    }
  }

  Future<void> _saveOAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    if (_pendingAuthState != null) {
      await prefs.setString('oauth_state', _pendingAuthState!);
    }
  }

  Future<void> _clearOAuthState() async {
    _pendingAuthState = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('oauth_state');
  }

  void _clearRequestState() {
    _lastErrorMessage = null;
    _lastListingAfter = null;
  }

  /// Downloads a media file (e.g. DASH video or audio).
  /// Tries anonymous first, then falls back to authenticated if blocked.
  Future<Uint8List?> downloadMedia(String url) async {
    _clearRequestState();

    // Append ?source=fallback if not present (required by Reddit CDN)
    var downloadUrl = url;
    if (!downloadUrl.contains('?')) {
      downloadUrl = '$downloadUrl?source=fallback';
    }
    final uri = Uri.parse(downloadUrl);

    // Try 1: Anonymous with User-Agent only
    try {
      debugPrint('[RedditApi] downloadMedia anon: $downloadUrl');
      final response = await http.get(uri, headers: {
        'User-Agent': userAgent,
      }).timeout(const Duration(seconds: 45));
      debugPrint(
          '[RedditApi] downloadMedia anon: HTTP ${response.statusCode}, bytes=${response.bodyBytes.length}');
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('[RedditApi] downloadMedia anon exception: $e');
    }

    // Try 2: With OAuth bearer token
    try {
      if (!isLoggedIn) {
        await _ensureGuestToken();
      } else {
        await _checkAndRefreshToken();
      }
      final token = isLoggedIn ? _accessToken : _guestAccessToken;
      final headers = {
        'User-Agent': userAgent,
        if (token != null) 'Authorization': 'bearer $token',
      };
      debugPrint(
          '[RedditApi] downloadMedia auth: $downloadUrl, token=${token != null ? "present" : "null"}');
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 45));
      debugPrint(
          '[RedditApi] downloadMedia auth: HTTP ${response.statusCode}, bytes=${response.bodyBytes.length}');
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      _setError('Media download failed: HTTP ${response.statusCode}');
    } catch (e) {
      debugPrint('[RedditApi] downloadMedia auth exception: $e');
      _setError('Media download error: $e');
    }
    return null;
  }

  /// Returns the headers (User-Agent and optional OAuth bearer token)
  /// needed for downloading media from Reddit CDNs.
  Future<Map<String, String>> getDownloadHeaders() async {
    try {
      if (!isLoggedIn) {
        await _ensureGuestToken();
      } else {
        await _checkAndRefreshToken();
      }
    } catch (_) {}
    final token = isLoggedIn ? _accessToken : _guestAccessToken;
    return {
      'User-Agent': userAgent,
      if (token != null) 'Authorization': 'bearer $token',
    };
  }

  Uri buildListingUriForTesting({
    required String feedType,
    required String query,
    required String sort,
    required Map<String, String> params,
  }) {
    return _buildListingUri(
      feedType: feedType,
      query: query,
      sort: sort,
      params: params,
    );
  }

  set detectedCountryCodeForTesting(String? code) {
    _detectedCountryCode = code;
  }

  void _setError(String message) {
    _lastErrorMessage = message;
  }

  String _generateRandomString(int length) {
    final random = Random();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }
}
