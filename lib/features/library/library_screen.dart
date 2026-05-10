import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/theme.dart';
import '../../core/models/book.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/auth_provider.dart';
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
      appBar: AppBar(
        title: const Text('Libreria'),
        actions: [
          if (_isImporting)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MarginaliaColors.accent,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Importa My Clippings.txt',
              onPressed: _pickAndImportFile,
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Daily highlight card
          randomHighlightAsync.when(
            data: (highlight) => highlight != null
                ? SliverToBoxAdapter(
                    child: _DailyHighlightCard(
                      content: highlight.content,
                      onTap: () => context.push('/highlight/${highlight.id}'),
                    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),
                  )
                : const SliverToBoxAdapter(child: SizedBox.shrink()),
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // Section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Text('I TUOI LIBRI', style: MarginaliaTextStyles.sectionTitle),
            ),
          ),

          // Books list
          booksAsync.when(
            data: (books) => books.isEmpty
                ? SliverFillRemaining(child: _EmptyLibrary(onImport: _pickAndImportFile))
                : SliverList.builder(
                    itemCount: books.length,
                    itemBuilder: (ctx, i) => _BookRow(
                      book: books[i],
                      index: i,
                      onTap: () => context.push('/book/${books[i].id}'),
                    ),
                  ),
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: MarginaliaColors.accent)),
            ),
            error: (err, _) => SliverFillRemaining(
              child: Center(child: Text('Errore: $err')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndImportFile() async {
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
      final service = ImportService(isar, userId);
      final importResult = await service.importClippingsText(rawText);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${importResult.highlightsAdded} highlight importati da ${importResult.booksAdded} libri.',
            ),
            backgroundColor: MarginaliaColors.accent,
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
}

class _DailyHighlightCard extends StatelessWidget {
  const _DailyHighlightCard({required this.content, required this.onTap});

  final String content;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MarginaliaColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Oggi', style: MarginaliaTextStyles.label),
            const SizedBox(height: 10),
            Text(
              content.length > 180 ? '${content.substring(0, 180)}…' : content,
              style: MarginaliaTextStyles.highlightBodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.book, required this.index, required this.onTap});

  final Book book;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: MarginaliaColors.border)),
        ),
        child: Row(
          children: [
            // Book cover placeholder
            Container(
              width: 42,
              height: 58,
              decoration: BoxDecoration(
                color: MarginaliaColors.accentLight.withAlpha(60),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.book_outlined,
                color: MarginaliaColors.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title, style: MarginaliaTextStyles.bookTitle, maxLines: 2),
                  const SizedBox(height: 2),
                  Text(book.author, style: MarginaliaTextStyles.bookAuthor),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: MarginaliaColors.textMuted, size: 18),
          ],
        ),
      ),
    )
        .animate(delay: (index * 40).ms)
        .fadeIn(duration: 300.ms)
        .slideX(begin: 0.04, end: 0);
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_books_outlined,
                size: 56, color: MarginaliaColors.accentLight),
            const SizedBox(height: 20),
            const Text(
              'La tua libreria è vuota',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Importa il file My Clippings.txt\ndal tuo Kindle, oppure sincronizza\ncon Amazon.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MarginaliaColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Importa Clippings'),
            ),
          ],
        ),
      ),
    );
  }
}
