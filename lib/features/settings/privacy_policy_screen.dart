import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';

/// In-app privacy policy. Renders the bundled HTML (IT/EN by [isItalian])
/// inside a WebView so the policy lives *inside* the app instead of opening an
/// external GitHub link — an App Store expectation and what the founder asked
/// for. Falls back to an "open in browser" button on platforms where
/// webview_flutter isn't supported (e.g. the Windows dev build) so it never
/// crashes there.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key, required this.isItalian});

  final bool isItalian;

  static const _itUrl =
      'https://get-scripta.app/privacy/it/';
  static const _enUrl =
      'https://get-scripta.app/privacy/';

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  // ONE controller for the lifetime of the screen. The EN/IT toggle reloads the
  // other language's HTML into THIS SAME controller via loadHtmlString. The old
  // approach recreated the controller on toggle, but the "set _controller=null"
  // and "set _controller=new" setStates batched into one frame, so the WebView
  // element was reused and kept showing the previous page → tapping EN did
  // nothing. Reloading the live controller's content always re-renders.
  WebViewController? _controller;
  bool _loaded = false;

  late bool _isItalian;

  // webview_flutter only ships mobile implementations (iOS/Android).
  bool get _webViewSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  String get _assetPath => _isItalian
      ? 'docs/privacy/it/index.html'
      : 'docs/privacy/index.html';

  @override
  void initState() {
    super.initState();
    _isItalian = widget.isItalian;
    if (_webViewSupported) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setBackgroundColor(ScriptaColors.background);
      _loadAsset();
    }
  }

  void _toggleLanguage() {
    setState(() => _isItalian = !_isItalian);
    if (_webViewSupported) _loadAsset(); // reload the SAME controller
  }

  Future<void> _loadAsset() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final html = await rootBundle.loadString(_assetPath);
      // Strip favicon/apple-touch + Open Graph/Twitter image tags: they point
      // at /assets/ paths that can't resolve in a data-URI WebView.
      final cleaned = html
          .replaceAll(
              RegExp(r'\s*<link[^>]*rel="(icon|apple-touch-icon)"[^>]*>',
                  caseSensitive: false),
              '')
          .replaceAll(
              RegExp(r'\s*<meta[^>]*(og:image|twitter:image|twitter:card)[^>]*>',
                  caseSensitive: false),
              '');
      await controller.loadHtmlString(cleaned);
      if (mounted) setState(() => _loaded = true);
    } catch (_) {
      // Keep the spinner on failure; harmless.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: ScriptaColors.background,
        foregroundColor: ScriptaColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(context.l10n.privacyTitle),
        actions: [
          // The label shows the language you'll switch TO.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _toggleLanguage,
              style: TextButton.styleFrom(
                foregroundColor: ScriptaColors.sienna,
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              child: Text(_isItalian ? 'EN' : 'IT'),
            ),
          ),
        ],
      ),
      body: _webViewSupported
          ? (_controller == null || !_loaded
              ? const Center(
                  child: CircularProgressIndicator(
                    color: ScriptaColors.sienna,
                    strokeWidth: 1.5,
                  ),
                )
              : WebViewWidget(controller: _controller!))
          : _BrowserFallback(
              url: _isItalian
                  ? PrivacyPolicyScreen._itUrl
                  : PrivacyPolicyScreen._enUrl,
            ),
    );
  }
}

class _BrowserFallback extends StatelessWidget {
  const _BrowserFallback({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.privacyPreviewUnavailable,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ScriptaColors.inkMuted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(context.l10n.privacyOpenInBrowser),
            ),
          ],
        ),
      ),
    );
  }
}
