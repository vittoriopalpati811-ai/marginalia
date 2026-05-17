import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
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

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return; // WebView not available on web

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: _onPageFinished,
          onWebResourceError: (error) {
            setState(() {
              _syncState = _SyncState.error;
              _errorMessage = error.description;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(AmazonSyncService.notebookUrl));
  }

  Future<void> _onPageFinished(String url) async {
    if (!AmazonSyncService.isOnNotebookPage(url)) return;
    if (_syncState != _SyncState.browsing) return;

    setState(() => _syncState = _SyncState.extracting);

    try {
      final amazonHighlights = await AmazonSyncService.extractHighlights(_webController);

      if (amazonHighlights.isEmpty) {
        setState(() => _syncState = _SyncState.browsing);
        return;
      }

      final clippingsText = amazonHighlightsToClippingsText(amazonHighlights);
      final userId = ref.read(currentUserProvider)?.id ?? 'local';
      final isar = ref.read(isarProvider);
      final service = ImportService(isar, userId);
      final result = await service.importClippingsText(clippingsText);

      setState(() {
        _syncState = _SyncState.done;
        _highlightsImported = result.highlightsAdded;
      });
    } catch (e) {
      setState(() {
        _syncState = _SyncState.error;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Kindle'),
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
                  onPressed: () => _onPageFinished(AmazonSyncService.notebookUrl),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Estrai highlight ora'),
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
        if (_syncState == _SyncState.extracting) _ExtractingOverlay(),
        if (_syncState == _SyncState.done)
          _DoneOverlay(
            count: _highlightsImported,
            onClose: () => context.pop(),
          ),
        if (_syncState == _SyncState.error)
          _ErrorOverlay(
            message: _errorMessage ?? 'Errore sconosciuto',
            onRetry: () {
              setState(() => _syncState = _SyncState.browsing);
              _webController.loadRequest(
                Uri.parse(AmazonSyncService.notebookUrl),
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
            const Text(
              'Sync automatico non disponibile sul web',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: MarginaliaColors.text),
            ),
            const SizedBox(height: 12),
            const Text(
              'Il sync diretto con Amazon Kindle richiede l\'app iOS nativa.\n\n'
              'Su web puoi importare i tuoi highlight manualmente: vai su Settings e carica il file My Clippings.txt dalla memoria del tuo Kindle.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: MarginaliaColors.textMuted),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.go('/profile'),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Vai a Import manuale'),
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
  @override
  Widget build(BuildContext context) {
    return Container(
      color: MarginaliaColors.background,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: MarginaliaColors.accent),
            SizedBox(height: 20),
            Text(
              'Sto estraendo gli highlight…',
              style: TextStyle(color: MarginaliaColors.textMuted, fontSize: 15),
            ),
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
            const Text(
              'Sync completato!',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: MarginaliaColors.text),
            ),
            const SizedBox(height: 8),
            Text(
              '$count highlight importati.',
              style: const TextStyle(
                  fontSize: 16, color: MarginaliaColors.textMuted),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: onClose,
              child: const Text('Vai alla libreria'),
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
            const Text(
              'Qualcosa è andato storto',
              style: TextStyle(
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
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }
}
