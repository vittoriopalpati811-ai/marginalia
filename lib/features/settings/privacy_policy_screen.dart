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
        ..setBackgroundColor(ScriptaColors.background)
        ..loadHtmlString(html);
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
        title: Text(context.l10n.privacyTitle),
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
              url: widget.isItalian
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
