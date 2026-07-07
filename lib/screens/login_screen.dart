import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../api/reddit_api.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final WebViewController _webController;
  bool _isLoading = true;
  final RedditApi _api = RedditApi();

  @override
  void initState() {
    super.initState();

    final String authUrl = _api.getAuthorizationUrl();

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
            _checkRedirect(url);
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_checkRedirect(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    // Clear cookies before loading OAuth so user gets a fresh login prompt
    WebViewCookieManager().clearCookies().then((_) {
      _webController.loadRequest(Uri.parse(authUrl));
    });
  }

  bool _checkRedirect(String url) {
    if (url.startsWith(RedditApi.redirectUri)) {
      setState(() {
        _isLoading = true;
      });
      _api.handleAuthCallback(url).then((success) {
        if (mounted) {
          Navigator.pop(context, success);
        }
      });
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Connect Community Account',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        backgroundColor: AppTheme.surfaceElevated,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webController),
          if (_isLoading)
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: Center(
                    child: SpinKitRing(
                      color: AppTheme.accentOrange.withValues(alpha: 0.8),
                      size: 44.0,
                      lineWidth: 2.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
