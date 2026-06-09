import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';

/// In-app Terms of Service (EULA). Renders the bundled HTML (IT/EN by
/// [isItalian]) inside a WebView so the terms live *inside* the app instead of
/// opening an external GitHub link — an App Store expectation (Guideline 1.2,
/// user-generated content requires an agreed-to EULA). Falls back to an "open
/// in browser" button on platforms where webview_flutter isn't supported (e.g.
/// the Windows dev build) so it never crashes there.
class TermsOfServiceScreen extends StatefulWidget {
  const TermsOfServiceScreen({super.key, required this.isItalian});

  final bool isItalian;

  static const _itUrl =
      'https://get-scripta.app/terms/it/';
  static const _enUrl =
      'https://get-scripta.app/terms/';

  @override
  State<TermsOfServiceScreen> createState() => _TermsOfServiceScreenState();
}

class _TermsOfServiceScreenState extends State<TermsOfServiceScreen> {
  WebViewController? _controller;

  // Language is mutable so the in-app EN/IT toggle actually swaps the rendered
  // document. The bundled HTML's own language links can't navigate (JS is
  // disabled and the page is injected via loadHtmlString, not a real URL), so
  // the toggle has to live in the app chrome and reload the other asset.
  late bool _isItalian;

  // webview_flutter only ships mobile implementations (iOS/Android).
  bool get _webViewSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  String get _assetPath =>
      _isItalian ? 'docs/terms/it/index.html' : 'docs/terms/index.html';

  @override
  void initState() {
    super.initState();
    _isItalian = widget.isItalian;
    if (_webViewSupported) _initWebView();
  }

  void _toggleLanguage() {
    setState(() {
      _isItalian = !_isItalian;
      _controller = null; // show the spinner while the other asset loads
    });
    if (_webViewSupported) _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      final html = await rootBundle.loadString(_assetPath);
      // Strip favicon/apple-touch and Open Graph/Twitter image tags: they
      // point at /assets/ paths that can't resolve in a data-URI WebView
      // (the page is injected via loadHtmlString, not served from a host).
      final cleaned = html
          .replaceAll(
              RegExp(r'\s*<link[^>]*rel="(icon|apple-touch-icon)"[^>]*>',
                  caseSensitive: false),
              '')
          .replaceAll(
              RegExp(r'\s*<meta[^>]*(og:image|twitter:image|twitter:card)[^>]*>',
                  caseSensitive: false),
              '');
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setBackgroundColor(ScriptaColors.background)
        ..loadHtmlString(cleaned);
      if (mounted) setState(() => _controller = controller);
    } catch (_) {
      // Leaves _controller null → the loading spinner stays; harmless.
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
        title: Text(context.l10n.termsTitle),
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
          ? (_controller == null
              ? const Center(
                  child: CircularProgressIndicator(
                    color: ScriptaColors.sienna,
                    strokeWidth: 1.5,
                  ),
                )
              : WebViewWidget(controller: _controller!))
          : _BrowserFallback(
              url: _isItalian
                  ? TermsOfServiceScreen._itUrl
                  : TermsOfServiceScreen._enUrl,
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
