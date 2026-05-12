import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/theme.dart';
import '../../core/models/book.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/services/import_service.dart';
import '../../core/providers/isar_provider.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final randomHighlightAsync = ref.watch(randomHighlightProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── App bar senza chrome ───────────────────────────────────────────
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: MarginaliaColors.background,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              'Marginalia',
              style: MarginaliaTextStyles.bookTitleLarge.copyWith(
                fontSize: 20,
                color: MarginaliaColors.sienna,
              ),
            ),
            actions: [
              if (_isImporting)
                const Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MarginaliaColors.sienna,
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.add, size: 22),
                  color: MarginaliaColors.ink,
                  tooltip: 'Importa My Clippings.txt',
                  onPressed: _pickAndImportFile,
                ),
            ],
          ),

          // ── Hero card: highlight del giorno ──────────────────────────────
          randomHighlightAsync.when(
            data: (highlight) => highlight != null
                ? SliverToBoxAdapter(
                    child: _DailyCard(
                      content: highlight.content,
                      onTap: () => context.push('/highlight/${highlight.id}'),
                    )
                        .animate()
                        .fadeIn(duration: 500.ms, curve: Curves.easeOut)
                        .slideY(begin: 0.06, end: 0, duration: 500.ms, curve: Curves.easeOut),
                  )
                : const SliverToBoxAdapter(child: SizedBox(height: 8)),
            loading: () => const SliverToBoxAdapter(child: SizedBox(height: 8)),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ),

          // ── Intestazione sezione ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
              child: Row(
                children: [
                  Text('LA TUA LIBRERIA', style: MarginaliaTextStyles.sectionTitle),
                  const SizedBox(width: 12),
                  const Expanded(child: Divider(color: MarginaliaColors.ruleFaint, height: 1)),
                ],
              ),
            ),
          ),

          // ── Lista libri ───────────────────────────────────────────────────
          booksAsync.when(
            data: (books) => books.isEmpty
                ? SliverFillRemaining(
                    child: _EmptyLibrary(
                      onImport: _pickAndImportFile,
                      onDemo: _loadDemoData,
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList.builder(
                      itemCount: books.length,
                      itemBuilder: (ctx, i) => _BookTile(
                        book: books[i],
                        index: i,
                        onTap: () => context.push('/book/${books[i].id}'),
                      ),
                    ),
                  ),
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: MarginaliaColors.sienna,
                  strokeWidth: 1.5,
                ),
              ),
            ),
            error: (err, _) => SliverFillRemaining(
              child: Center(
                child: Text(
                  'Errore: $err',
                  style: const TextStyle(color: MarginaliaColors.inkMuted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _requireAuth() {
    final supabase = ref.read(supabaseServiceProvider);
    if (!supabase.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Accedi per importare i tuoi highlight.'),
          action: SnackBarAction(
            label: 'Accedi',
            textColor: Colors.white,
            onPressed: () => context.push('/auth'),
          ),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _pickAndImportFile() async {
    if (!_requireAuth()) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    final rawText = String.fromCharCodes(file.bytes!);
    setState(() => _isImporting = true);

    try {
      final userId = ref.read(currentUserProvider)?.id ?? 'local';
      final isar = ref.read(isarProvider);
      final supabase = ref.read(supabaseServiceProvider);
      final service = ImportService(isar, userId, supabaseService: supabase);
      final importResult = await service.importClippingsText(rawText);
      _invalidateAfterImport();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              importResult.highlightsAdded > 0
                  ? '${importResult.highlightsAdded} highlight importati da ${importResult.booksAdded} libri.'
                  : 'Nessun nuovo highlight (${importResult.highlightsDeduplicated} già presenti).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore importazione: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _invalidateAfterImport() {
    ref.invalidate(booksProvider);
    ref.invalidate(randomHighlightProvider);
    ref.invalidate(allHighlightsProvider);
  }

  Future<void> _loadDemoData() async {
    if (!_requireAuth()) return;
    setState(() => _isImporting = true);
    try {
      final rawText = await rootBundle.loadString('assets/demo/My Clippings.txt');
      final userId = ref.read(currentUserProvider)?.id ?? 'local';
      final isar = ref.read(isarProvider);
      final supabase = ref.read(supabaseServiceProvider);
      final service = ImportService(isar, userId, supabaseService: supabase);
      final result = await service.importClippingsText(rawText);
      _invalidateAfterImport();
      if (mounted) {
        final msg = result.firstError != null
            ? 'Import parziale — libri OK: ${result.booksAdded}, falliti: ${result.booksFailed}. HL OK: ${result.highlightsAdded}, falliti: ${result.highlightsFailed}.\n\nERRORE: ${result.firstError}'
            : result.highlightsAdded > 0
                ? 'Demo caricata: ${result.highlightsAdded} highlight da ${result.booksAdded} libri.'
                : 'I dati demo sono già presenti.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 15),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore caricamento demo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }
}

// ─── Hero card: highlight del giorno ─────────────────────────────────────────

class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.content, required this.onTap});

  final String content;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = content.length > 220 ? '${content.substring(0, 220)}…' : content;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        decoration: MarginaliaDecorations.heroCard,
        child: Stack(
          children: [
            // Quote mark decorativo
            Positioned(
              top: -8,
              left: 14,
              child: Text('“', style: MarginaliaTextStyles.quoteDecor),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(22, 40, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: MarginaliaTextStyles.highlightBodySmall.copyWith(
                      color: Colors.white.withAlpha(230),
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'OGGI',
                        style: MarginaliaTextStyles.label.copyWith(
                          color: Colors.white.withAlpha(130),
                          letterSpacing: 1.8,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: Colors.white.withAlpha(160),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Book tile ────────────────────────────────────────────────────────────────

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book, required this.index, required this.onTap});

  final Book book;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final coverColor = MarginaliaDecorations.bookCoverColor(book.title);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: MarginaliaDecorations.card(),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Book cover
              Container(
                width: 46,
                height: 64,
                decoration: BoxDecoration(
                  color: coverColor,
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    BoxShadow(
                      color: coverColor.withAlpha(100),
                      blurRadius: 6,
                      offset: const Offset(2, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    book.title.isNotEmpty ? book.title[0].toUpperCase() : '?',
                    style: MarginaliaTextStyles.bookTitleLarge.copyWith(
                      color: Colors.white.withAlpha(220),
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: MarginaliaTextStyles.bookTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author.toUpperCase(),
                      style: MarginaliaTextStyles.bookAuthor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: MarginaliaColors.inkFaint,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    )
        .animate(delay: (index * 45).ms)
        .fadeIn(duration: 350.ms, curve: Curves.easeOut)
        .slideX(begin: 0.03, end: 0, duration: 350.ms, curve: Curves.easeOut);
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport, required this.onDemo});

  final VoidCallback onImport;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: MarginaliaColors.siennaFaint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.auto_stories_outlined,
                size: 32,
                color: MarginaliaColors.siennaLight,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Nessun libro ancora',
              style: MarginaliaTextStyles.bookTitle.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 10),
            const Text(
              'Importa il file My Clippings.txt\ndal tuo Kindle per cominciare.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MarginaliaColors.inkMuted,
                height: 1.6,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Importa Clippings'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onDemo,
              icon: Icon(Icons.auto_awesome_outlined,
                  size: 16, color: MarginaliaColors.siennaLight),
              label: Text(
                'Prova con dati demo',
                style: TextStyle(color: MarginaliaColors.siennaLight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
