import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/services/amazon_sync_service.dart';
import '../../core/services/import_service.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/isar_provider.dart';

enum _SyncState { browsing, extracting, done, error }

class AmazonLoginScreen extends ConsumerStatefulWidget {
  const AmazonLoginScreen({super.key});

  @override
  ConsumerState<AmazonLoginScreen> createState() => _AmazonLoginScreenState();
}

class _AmazonLoginScreenState extends ConsumerState<AmazonLoginScreen> {
  late final WebViewController _webController;
  _SyncState _syncState = _SyncState.browsing;
  String? _errorMessage;
  int _highlightsImported = 0;
  int _progressCount = 0;
  String? _progressBook;
  bool _importing = false;

  // Fails the extraction with a clear message if the injected script goes silent
  // (e.g. an unexpected Amazon page / JS error) instead of spinning forever.
  // Re-armed on every progress message so large libraries don't trip it.
  Timer? _watchdog;

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 75), () {
      if (!mounted || _syncState != _SyncState.extracting) return;
      setState(() {
        _syncState = _SyncState.error;
        _errorMessage = context.l10n.kindleWatchdog;
      });
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return; // WebView not available on web

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // The extractor is asynchronous (many fetches + pagination) and WKWebView
      // does not await Promises through runJavaScriptReturningResult, so results
      // stream back through this channel instead.
      ..addJavaScriptChannel(
        AmazonSyncService.channelName,
        onMessageReceived: _onChannelMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: _onPageFinished,
          onWebResourceError: (error) {
            // Ignore sub-resource errors (ads, trackers, favicons) — only the
            // main navigation matters and the user can retry from the overlay.
            if (error.isForMainFrame == false) return;
          },
        ),
      )
      ..loadRequest(Uri.parse(AmazonSyncService.entryUrl));
  }

  /// Opens the Kindle notebook on the SAME Amazon host the user is currently on
  /// (region-safe), so an amazon.it / amazon.de / … account opens its own
  /// notebook. onPageFinished then injects the extractor.
  Future<void> _openNotebook() async {
    String target = AmazonSyncService.notebookUrl;
    try {
      target = AmazonSyncService.notebookUrlForHost(
          await _webController.currentUrl());
    } catch (_) {
      // Fall back to the global notebook URL.
    }
    await _webController.loadRequest(Uri.parse(target));
  }

  /// Fires when any page finishes loading. We only act once the user has reached
  /// the (authenticated) notebook — at which point we inject the extractor.
  Future<void> _onPageFinished(String url) async {
    if (!AmazonSyncService.isOnNotebookPage(url)) return;
    if (_syncState != _SyncState.browsing) return;

    setState(() {
      _syncState = _SyncState.extracting;
      _progressCount = 0;
      _progressBook = null;
    });

    try {
      final script = await AmazonSyncService.extractorScript();
      // Fire-and-forget: the extractor posts progress + the final payload back
      // through the channel (handled in _onChannelMessage).
      await _webController.runJavaScript(script);
      _armWatchdog();
    } catch (e) {
      setState(() {
        _syncState = _SyncState.error;
        _errorMessage = e.toString();
      });
    }
  }

  /// Receives JSON messages posted by the injected extractor.
  void _onChannelMessage(JavaScriptMessage message) {
    if (!mounted) return;
    final msg = AmazonSyncService.parseChannelMessage(message.message);
    switch (msg.type) {
      case SyncMessageType.progress:
        _armWatchdog(); // still alive — reset the silence timer
        setState(() {
          _progressCount = msg.total ?? _progressCount;
          _progressBook = msg.book;
        });
        break;
      case SyncMessageType.done:
        _watchdog?.cancel();
        _importHighlights(msg.highlights ?? const []);
        break;
      case SyncMessageType.error:
        _watchdog?.cancel();
        setState(() {
          _syncState = _SyncState.error;
          _errorMessage =
              msg.error == 'NO_BOOKS' ? context.l10n.kindleNoBooks : msg.error;
        });
        break;
    }
  }

  /// Imports the extracted highlights via the shared My Clippings pipeline.
  Future<void> _importHighlights(List<AmazonHighlight> highlights) async {
    if (_importing) return; // guard against duplicate "done" messages
    _importing = true;

    if (highlights.isEmpty) {
      setState(() {
        _syncState = _SyncState.error;
        _errorMessage = context.l10n.kindleNoHighlights;
      });
      _importing = false;
      return;
    }

    try {
      final clippingsText = amazonHighlightsToClippingsText(highlights);
      final userId = ref.read(currentUserProvider)?.id ?? 'local';
      final isar = ref.read(isarProvider);
      final service = ImportService(isar, userId);
      final result = await service.importClippingsText(clippingsText);

      if (!mounted) return;
      setState(() {
        _syncState = _SyncState.done;
        _highlightsImported = result.highlightsAdded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncState = _SyncState.error;
        _errorMessage = e.toString();
      });
    } finally {
      _importing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.settingsKindleSync),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: kIsWeb ? const _WebNotSupported() : _nativeBody(),
      bottomNavigationBar: (!kIsWeb && _syncState == _SyncState.browsing)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  // Navigate to the notebook on whatever Amazon host the user
                  // ended up on after login (region-safe); onPageFinished then
                  // injects the extractor.
                  onPressed: _openNotebook,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(context.l10n.jamExtractHighlights),
                ),
              ),
            )
          : null,
    );
  }

  Widget _nativeBody() {
    return Stack(
      children: [
        AnimatedOpacity(
          opacity: _syncState == _SyncState.browsing ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: WebViewWidget(controller: _webController),
        ),
        if (_syncState == _SyncState.extracting)
          _ExtractingOverlay(count: _progressCount, book: _progressBook),
        if (_syncState == _SyncState.done)
          _DoneOverlay(
            count: _highlightsImported,
            onClose: () => context.pop(),
          ),
        if (_syncState == _SyncState.error)
          _ErrorOverlay(
            message: _errorMessage ?? 'Unknown error',
            onRetry: () {
              _watchdog?.cancel();
              setState(() {
                _syncState = _SyncState.browsing;
                _errorMessage = null;
                _progressCount = 0;
                _progressBook = null;
                _importing = false;
              });
              _webController.loadRequest(
                Uri.parse(AmazonSyncService.entryUrl),
              );
            },
          ),
      ],
    );
  }
}

class _WebNotSupported extends StatelessWidget {
  const _WebNotSupported();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_iphone,
                size: 64, color: MarginaliaColors.accentLight),
            const SizedBox(height: 24),
            Text(
              context.l10n.kindleWebTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: MarginaliaColors.text),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.kindleWebBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: MarginaliaColors.textMuted),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.go('/profile'),
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(context.l10n.amazonGoToManualImport),
              style: FilledButton.styleFrom(
                backgroundColor: MarginaliaColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtractingOverlay extends StatelessWidget {
  const _ExtractingOverlay({required this.count, this.book});

  final int count;
  final String? book;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MarginaliaColors.background,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: MarginaliaColors.accent),
            const SizedBox(height: 20),
            Text(
              context.l10n.kindleReading,
              style: const TextStyle(color: MarginaliaColors.text, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              count > 0
                  ? context.l10n.kindleSoFar(count)
                  : context.l10n.kindleOpeningLibrary,
              style: const TextStyle(
                  color: MarginaliaColors.textMuted, fontSize: 13),
            ),
            if (book != null && book!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                book!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: MarginaliaColors.textMuted,
                    fontSize: 12,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DoneOverlay extends StatelessWidget {
  const _DoneOverlay({required this.count, required this.onClose});

  final int count;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MarginaliaColors.background,
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 72, color: MarginaliaColors.accent),
            const SizedBox(height: 24),
            Text(
              context.l10n.kindleDone,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: MarginaliaColors.text),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.kindleImported(count),
              style: const TextStyle(
                  fontSize: 16, color: MarginaliaColors.textMuted),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: onClose,
              child: Text(context.l10n.amazonGoToLibrary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MarginaliaColors.background,
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 56, color: MarginaliaColors.textMuted),
            const SizedBox(height: 20),
            Text(
              context.l10n.kindleSomethingWrong,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: MarginaliaColors.text),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: MarginaliaColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.amazonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
