import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';

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
      'https://vittoriopalpati811-ai.github.io/marginalia/privacy/it/';
  static const _enUrl =
      'https://vittoriopalpati811-ai.github.io/marginalia/privacy/';

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  WebViewController? _controller;

  // webview_flutter only ships mobile implementations (iOS/Android).
  bool get _webViewSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  String get _assetPath => widget.isItalian
      ? 'docs/privacy/it/index.html'
      : 'docs/privacy/index.html';

  @override
  void initState() {
    super.initState();
    if (_webViewSupported) _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      final html = await rootBundle.loadString(_assetPath);
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setBackgroundColor(MarginaliaColors.background)
        ..loadHtmlString(html);
      if (mounted) setState(() => _controller = controller);
    } catch (_) {
      // Leaves _controller null → the loading spinner stays; harmless.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        foregroundColor: MarginaliaColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Privacy'),
      ),
      body: _webViewSupported
          ? (_controller == null
              ? const Center(
                  child: CircularProgressIndicator(
                    color: MarginaliaColors.sienna,
                    strokeWidth: 1.5,
                  ),
                )
              : WebViewWidget(controller: _controller!))
          : _BrowserFallback(
              url: widget.isItalian
                  ? PrivacyPolicyScreen._itUrl
                  : PrivacyPolicyScreen._enUrl,
              isItalian: widget.isItalian,
            ),
    );
  }
}

class _BrowserFallback extends StatelessWidget {
  const _BrowserFallback({required this.url, required this.isItalian});

  final String url;
  final bool isItalian;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isItalian
                  ? 'Anteprima non disponibile su questa piattaforma.'
                  : 'Preview is not available on this platform.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: MarginaliaColors.inkMuted),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(isItalian ? 'Apri nel browser' : 'Open in browser'),
            ),
          ],
        ),
      ),
    );
  }
}
