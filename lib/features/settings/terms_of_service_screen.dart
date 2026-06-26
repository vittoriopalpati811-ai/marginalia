import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
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
  // ONE controller for the screen's lifetime. The EN/IT toggle re-navigates it
  // to the other language's bundled asset via loadFlutterAsset. We use
  // loadFlutterAsset (a REAL asset URL) rather than loadHtmlString: re-calling
  // loadHtmlString on the same controller did not reliably re-render on the
  // Android WebView → "tapping EN did nothing". A real navigation always
  // re-renders. If the main frame ever fails (it shouldn't — the asset ships in
  // the app) we fall back to the hosted page so the screen is never blank.
  WebViewController? _controller;
  bool _loaded = false;
  // Both sticky (set once, never reset) — see _load() + the delegate below.
  bool _pageDone = false; // the asset page reached onPageFinished at least once
  bool _triedHosted = false; // we already used the hosted fallback once

  late bool _isItalian;

  // webview_flutter only ships mobile implementations (iOS/Android).
  bool get _webViewSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  String get _assetPath =>
      _isItalian ? 'docs/terms/it/index.html' : 'docs/terms/index.html';

  String get _hostedUrl =>
      _isItalian ? TermsOfServiceScreen._itUrl : TermsOfServiceScreen._enUrl;

  @override
  void initState() {
    super.initState();
    _isItalian = widget.isItalian;
    if (_webViewSupported) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setBackgroundColor(ScriptaColors.background)
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) {
            _pageDone = true;
            if (mounted && !_loaded) setState(() => _loaded = true);
          },
          onWebResourceError: (error) {
            // Recover ONLY from a genuine first-load main-frame failure. Once
            // the page has rendered once we never bounce again: sub-resource
            // 404s (favicon / web-font) report isForMainFrame=false, and on
            // Android isForMainFrame can be unreliable — bouncing to the hosted
            // page while offline would just re-blank the screen.
            if (!_pageDone &&
                !_triedHosted &&
                (error.isForMainFrame ?? false) &&
                mounted) {
              _triedHosted = true;
              _controller?.loadRequest(Uri.parse(_hostedUrl));
            }
          },
        ));
      _load();
    }
  }

  void _toggleLanguage() {
    setState(() {
      _isItalian = !_isItalian;
      _loaded = false; // show the spinner over the webview during the reload
    });
    if (_webViewSupported) _load();
  }

  // loadFlutterAsset navigates to a real asset URL → reliable re-render on the
  // toggle (unlike re-calling loadHtmlString). It throws a Dart ArgumentError
  // (NOT a WebResourceError) if a key were ever missing, so we catch that and
  // fall back to the hosted page. The watchdog guarantees the spinner can never
  // hang forever if a page-load callback is ever missed.
  Future<void> _load() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.loadFlutterAsset(_assetPath);
    } catch (_) {
      if (mounted && !_triedHosted) {
        _triedHosted = true;
        try {
          await controller.loadRequest(Uri.parse(_hostedUrl));
        } catch (_) {/* offline: the watchdog below still clears the spinner */}
      }
    }
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_loaded) setState(() => _loaded = true);
    });
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
      body: !_webViewSupported
          ? _BrowserFallback(url: _hostedUrl)
          : Stack(
              children: [
                if (_controller != null)
                  WebViewWidget(controller: _controller!),
                if (!_loaded)
                  const Center(
                    child: CircularProgressIndicator(
                      color: ScriptaColors.sienna,
                      strokeWidth: 1.5,
                    ),
                  ),
              ],
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
