// ─── The invisible half of the automatic Kindle sync ─────────────────────────
//
// Mounted once, inside the app shell, and never seen. It owns a zero-size
// WebView that the background sync drives: load the Amazon notebook, inject the
// same extractor the visible sync screen uses, import whatever comes back.
//
// Why a real (if invisible) WebView rather than a detached controller: a
// WKWebView that is not in the view hierarchy is free to be throttled or frozen
// by iOS, which would turn "sync quietly in the background" into "hang quietly
// in the background". One-pixel-and-transparent is boring, but it is the version
// that actually runs.
//
// It stays out of the way in every other respect: the widget occupies no layout
// space, ignores pointers, and is only built while a sync is genuinely in
// flight — so an app that never syncs never pays for a WebView at all.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/isar_provider.dart';
import '../../core/services/amazon_sync_service.dart';
import '../../core/services/import_service.dart';
import '../../core/services/kindle_auto_sync.dart';

/// Gives up on a silent run rather than holding a WebView open forever. The
/// visible screen can afford to wait on a person; an unattended job cannot.
const Duration _kSilentTimeout = Duration(seconds: 90);

class KindleSyncHost extends ConsumerStatefulWidget {
  const KindleSyncHost({super.key});

  @override
  ConsumerState<KindleSyncHost> createState() => _KindleSyncHostState();
}

class _KindleSyncHostState extends ConsumerState<KindleSyncHost> {
  WebViewController? _controller;
  Completer<int>? _run;
  Timer? _watchdog;
  bool _imported = false;

  @override
  void initState() {
    super.initState();
    // Hand the controller's "run a sync" ability to the notifier, which owns
    // WHEN it happens; this widget only knows HOW.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(kindleAutoSyncProvider.notifier).runner = _run0;
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    ref.read(kindleAutoSyncProvider.notifier).runner = null;
    super.dispose();
  }

  /// One silent sync. Completes with the number of NEW highlights imported;
  /// throws [amazonSessionExpired] when Amazon wants a password again.
  Future<int> _run0() async {
    if (_run != null) return 0; // one at a time
    final completer = Completer<int>();
    _run = completer;
    _imported = false;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        AmazonSyncService.channelName,
        onMessageReceived: _onMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: _onPageFinished,
          onWebResourceError: (e) {
            if (e.isForMainFrame == true) _fail(Exception(e.description));
          },
        ),
      );

    setState(() => _controller = controller);
    await controller.loadRequest(Uri.parse(AmazonSyncService.notebookUrl));

    _watchdog = Timer(_kSilentTimeout, () => _fail(TimeoutException('kindle')));

    try {
      return await completer.future;
    } finally {
      _watchdog?.cancel();
      _run = null;
      if (mounted) setState(() => _controller = null);
    }
  }

  Future<void> _onPageFinished(String url) async {
    if (_run == null || _run!.isCompleted) return;

    // Amazon answers an expired session with the sign-in page. That is not an
    // error worth surfacing — it is a "ask me again when I'm looking".
    if (!AmazonSyncService.isOnNotebookPage(url)) {
      if (url.contains('/ap/signin') || url.contains('/ap/cvf')) {
        _fail(amazonSessionExpired);
      }
      return;
    }

    try {
      await _controller?.runJavaScript(await AmazonSyncService.extractorScript());
    } catch (e) {
      _fail(e);
    }
  }

  void _onMessage(JavaScriptMessage message) {
    if (_run == null || _run!.isCompleted) return;
    final msg = AmazonSyncService.parseChannelMessage(message.message);
    switch (msg.type) {
      case SyncMessageType.progress:
        // Still alive — a large library must not trip the watchdog.
        _watchdog?.cancel();
        _watchdog =
            Timer(_kSilentTimeout, () => _fail(TimeoutException('kindle')));
        break;
      case SyncMessageType.done:
        _import(msg.highlights ?? const []);
        break;
      case SyncMessageType.error:
        _fail(Exception(msg.error ?? 'kindle'));
        break;
    }
  }

  Future<void> _import(List<AmazonHighlight> highlights) async {
    if (_imported) return; // guard against a duplicate "done"
    _imported = true;
    _watchdog?.cancel();

    if (highlights.isEmpty) {
      _run?.complete(0);
      return;
    }

    try {
      final userId = ref.read(currentUserProvider)?.id ?? 'local';
      final service = ImportService(ref.read(isarProvider), userId);
      final result = await service.importClippingsText(
        amazonHighlightsToClippingsText(highlights),
      );
      // Nothing new is the common case and stays invisible; when something DID
      // arrive, refresh what is on screen so the reader sees it without a pull.
      if (result.highlightsAdded > 0) {
        ref.invalidate(allHighlightsProvider);
        ref.invalidate(booksProvider);
      }
      _run?.complete(result.highlightsAdded);
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object error) {
    _watchdog?.cancel();
    if (_run != null && !_run!.isCompleted) _run!.completeError(error);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    // Present enough to run, invisible enough to be nowhere: no layout space,
    // no paint, no touches.
    return IgnorePointer(
      child: Opacity(
        opacity: 0,
        child: SizedBox(
          width: 1,
          height: 1,
          child: WebViewWidget(controller: controller),
        ),
      ),
    );
  }
}
