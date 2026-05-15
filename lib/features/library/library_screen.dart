import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/theme.dart';
import '../../core/models/book.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/services/import_service.dart';
import '../../core/providers/isar_provider.dart';

// ─── Filter state ─────────────────────────────────────────────────────────────

enum _LibraryFilter { all, favorites }

final _libraryFilterProvider =
    StateProvider<_LibraryFilter>((ref) => _LibraryFilter.all);

// ─── Screen ───────────────────────────────────────────────────────────────────

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
    final allHighlightsAsync = ref.watch(allHighlightsProvider);
    final filter = ref.watch(_libraryFilterProvider);
    final randomAsync = ref.watch(randomHighlightProvider);

    // Apply filter to books
    final filteredBooksAsync = booksAsync.whenData((books) {
      if (filter == _LibraryFilter.favorites) {
        final favBookIds = allHighlightsAsync.maybeWhen(
          data: (hl) => hl.where((h) => h.isFavorite).map((h) => h.bookId).toSet(),
          orElse: () => <int>{},
        );
        return books.where((b) => favBookIds.contains(b.id)).toList();
      }
      return books;
    });

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Header editoriale ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _EditorialHeader(
              isImporting: _isImporting,
              onImport: _pickAndImportFile,
            ),
          ),

          // ── Hero card: highlight del giorno ─────────────────────────────────
          randomAsync.when(
            data: (h) => h != null
                ? SliverToBoxAdapter(
                    child: _DailyCard(
                      content: h.content,
                      onTap: () => context.push('/highlight/${h.id}'),
                    )
                        .animate()
                        .fadeIn(duration: 500.ms, curve: Curves.easeOut)
                        .slideY(begin: 0.05, end: 0, duration: 500.ms),
                  )
                : const SliverToBoxAdapter(child: SizedBox.shrink()),
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // ── Strip highlights recenti ──────────────────────────────────────
          allHighlightsAsync.when(
            data: (highlights) {
              if (highlights.isEmpty) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }
              final recent = highlights.take(8).toList();
              return SliverToBoxAdapter(
                child: _RecentHighlightsStrip(
                  highlights: recent,
                  onTap: (h) => context.push('/highlight/${h.id}'),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // ── Header libreria + filter chips ────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('LA TUA LIBRERIA',
                          style: MarginaliaTextStyles.sectionTitle),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Divider(
                            color: MarginaliaColors.ruleFaint, height: 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _FilterChips(
                    selected: filter,
                    onSelect: (f) =>
                        ref.read(_libraryFilterProvider.notifier).state = f,
                  ),
                ],
              ),
            ),
          ),

          // ── Griglia libri 2 colonne ────────────────────────────────────────
          filteredBooksAsync.when(
            data: (books) => books.isEmpty
                ? SliverFillRemaining(
                    child: _EmptyLibrary(
                      onImport: _pickAndImportFile,
                      onDemo: _loadDemoData,
                      isFiltered: filter != _LibraryFilter.all,
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _BookGridCard(
                          book: books[i],
                          index: i,
                          onTap: () => context.push('/book/${books[i].id}'),
                        ),
                        childCount: books.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.72,
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
                child: Text('Errore: $err',
                    style:
                        const TextStyle(color: MarginaliaColors.inkMuted)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Auth guard ─────────────────────────────────────────────────────────────

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

  // ─── Import da file picker ────────────────────────────────────────────────

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

    // utf8.decode handles multi-byte characters (è, à, ù, etc.) correctly.
    // allowMalformed: true tolerates BOM or mixed encodings from older Kindle.
    var rawText = utf8.decode(file.bytes!, allowMalformed: true);
    if (rawText.startsWith('﻿')) rawText = rawText.substring(1);

    setState(() => _isImporting = true);
    try {
      final userId = ref.read(currentUserProvider)?.id ?? 'local';
      final isar = ref.read(isarProvider);
      final supabase = ref.read(supabaseServiceProvider);
      final service = ImportService(isar, userId, supabaseService: supabase);
      final importResult = await service.importClippingsText(rawText);
      _invalidateAfterImport();

      if (mounted) {
        final msg = importResult.firstError != null
            ? 'Import parziale — ${importResult.highlightsAdded} HL, ${importResult.highlightsFailed} errori.\n${importResult.firstError}'
            : importResult.highlightsAdded > 0
                ? '${importResult.highlightsAdded} highlight importati da ${importResult.booksAdded} libri.'
                : 'Nessun nuovo highlight (${importResult.highlightsDeduplicated} già presenti).';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: Duration(
                seconds: importResult.firstError != null ? 15 : 4),
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

  // ─── Demo data ────────────────────────────────────────────────────────────

  Future<void> _loadDemoData() async {
    if (!_requireAuth()) return;
    setState(() => _isImporting = true);
    try {
      var rawText =
          await rootBundle.loadString('assets/demo/My Clippings.txt');
      if (rawText.startsWith('﻿')) rawText = rawText.substring(1);

      final userId = ref.read(currentUserProvider)?.id ?? 'local';
      final isar = ref.read(isarProvider);
      final supabase = ref.read(supabaseServiceProvider);
      final service = ImportService(isar, userId, supabaseService: supabase);
      final result = await service.importClippingsText(rawText);
      _invalidateAfterImport();
      if (mounted) {
        final msg = result.firstError != null
            ? 'Import parziale — ${result.booksAdded} libri, ${result.highlightsAdded} HL.\nErrore: ${result.firstError}'
            : result.highlightsAdded > 0
                ? 'Demo caricata: ${result.highlightsAdded} highlight da ${result.booksAdded} libri.'
                : 'I dati demo sono già presenti.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: Duration(
                seconds: result.firstError != null ? 15 : 5),
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

// ─── Header editoriale ────────────────────────────────────────────────────────

class _EditorialHeader extends StatelessWidget {
  const _EditorialHeader({
    required this.isImporting,
    required this.onImport,
  });

  final bool isImporting;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          22, MediaQuery.of(context).padding.top + 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titolo editoriale
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Marginalia',
                  style: MarginaliaTextStyles.bookTitleLarge.copyWith(
                    fontSize: 26,
                    color: MarginaliaColors.primary,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Le tue annotazioni, in un posto solo.',
                  style: TextStyle(
                    fontSize: 12,
                    color: MarginaliaColors.inkMuted,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
          // Import button
          if (isImporting)
            const Padding(
              padding: EdgeInsets.only(top: 6, right: 8),
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
              icon: const Icon(Icons.upload_file_outlined),
              color: MarginaliaColors.inkMuted,
              tooltip: 'Importa My Clippings.txt',
              onPressed: onImport,
            ),
        ],
      ),
    );
  }
}

// ─── Hero card: highlight del giorno ─────────────────────────────────────────

class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.content, required this.onTap});

  final String content;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = content.length > 200 ? '${content.substring(0, 200)}…' : content;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        decoration: MarginaliaDecorations.heroCard,
        child: Stack(
          children: [
            // Quote mark decorativo
            Positioned(
              top: -6,
              left: 14,
              child: Text('"', style: MarginaliaTextStyles.quoteDecor),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 44, 22, 22),
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
                        'HIGHLIGHT DEL GIORNO',
                        style: MarginaliaTextStyles.label.copyWith(
                          color: Colors.white.withAlpha(120),
                          letterSpacing: 1.8,
                          fontSize: 10,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.arrow_forward,
                          size: 15,
                          color: Colors.white.withAlpha(150)),
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

// ─── Strip highlights recenti (stile CategoryListView) ───────────────────────

class _RecentHighlightsStrip extends StatelessWidget {
  const _RecentHighlightsStrip({
    required this.highlights,
    required this.onTap,
  });

  final List<Highlight> highlights;
  final ValueChanged<Highlight> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          child: Row(
            children: [
              Text('RECENTI', style: MarginaliaTextStyles.sectionTitle),
              const SizedBox(width: 12),
              const Expanded(
                child:
                    Divider(color: MarginaliaColors.ruleFaint, height: 1),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 136,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16, right: 16),
            itemCount: highlights.length,
            itemBuilder: (ctx, i) {
              final h = highlights[i];
              final accentColor = _accentFor(h.color);
              return GestureDetector(
                onTap: () => onTap(h),
                child: Container(
                  width: 240,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: MarginaliaColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MarginaliaColors.rule),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0C261E1D),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Row(
                      children: [
                        // Accent strip
                        Container(width: 3, color: accentColor),
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(12, 12, 12, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Book title pill
                                if ((h.bookTitle ?? '').isNotEmpty)
                                  Text(
                                    h.bookTitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: MarginaliaColors.sienna,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                // Excerpt
                                Expanded(
                                  child: Text(
                                    h.content,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFontsLora.small,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
                  .animate(delay: (i * 50).ms)
                  .fadeIn(duration: 300.ms)
                  .slideX(begin: 0.04, end: 0, duration: 300.ms);
            },
          ),
        ),
      ],
    );
  }

  Color _accentFor(String? color) => switch (color) {
        'yellow' => const Color(0xFFD4A017),
        'blue' => const Color(0xFF4A90BF),
        'pink' => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _ => MarginaliaColors.siennaLight,
      };
}

// Helper: Lora piccolo (non possiamo usare MarginaliaTextStyles.highlightBody
// qui perché GoogleFonts non è const)
class GoogleFontsLora {
  static final small = MarginaliaTextStyles.highlightBodySmall.copyWith(
    fontSize: 12,
    height: 1.55,
  );
}

// ─── Filter chips (stile Design Course category selector) ────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});

  final _LibraryFilter selected;
  final ValueChanged<_LibraryFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(
          label: 'Tutti',
          icon: Icons.auto_stories_outlined,
          active: selected == _LibraryFilter.all,
          onTap: () => onSelect(_LibraryFilter.all),
        ),
        const SizedBox(width: 8),
        _Chip(
          label: 'Preferiti',
          icon: Icons.bookmark_outline,
          active: selected == _LibraryFilter.favorites,
          onTap: () => onSelect(_LibraryFilter.favorites),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? MarginaliaColors.primary : MarginaliaColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? MarginaliaColors.primary
                : MarginaliaColors.rule,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active
                  ? const Color(0xFFF1EEE7)
                  : MarginaliaColors.inkMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active
                    ? const Color(0xFFF1EEE7)
                    : MarginaliaColors.inkMuted,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Book grid card (stile PopularCourseListView) ────────────────────────────

class _BookGridCard extends StatelessWidget {
  const _BookGridCard({
    required this.book,
    required this.index,
    required this.onTap,
  });

  final Book book;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final coverColor = MarginaliaDecorations.bookCoverColor(book.title);
    final initial =
        book.title.isNotEmpty ? book.title[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MarginaliaColors.rule),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10261E1D),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Cover block (60% of card height) ──────────────────────────
            Expanded(
              flex: 60,
              child: Container(
                decoration: BoxDecoration(
                  color: coverColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(15),
                    topRight: Radius.circular(15),
                  ),
                  gradient: LinearGradient(
                    colors: [
                      coverColor,
                      coverColor.withAlpha(200),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Texture: quote mark sfumato in basso
                    Positioned(
                      bottom: -14,
                      right: 4,
                      child: Text(
                        '"',
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 88,
                          height: 1,
                          color: Colors.white.withAlpha(28),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    // Initial letter
                    Center(
                      child: Text(
                        initial,
                        style: TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w800,
                          color: Colors.white.withAlpha(220),
                          fontFamily: 'Georgia',
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Info block (40%) ──────────────────────────────────────────
            Expanded(
              flex: 40,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Title
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MarginaliaTextStyles.bookTitle.copyWith(
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                    // Author
                    Text(
                      book.author.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MarginaliaTextStyles.bookAuthor.copyWith(
                        fontSize: 9,
                        letterSpacing: 0.5,
                      ),
                    ),
                    // Arrow
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: coverColor.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.arrow_forward,
                            size: 13,
                            color: coverColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: (index * 55).ms)
        .fadeIn(duration: 350.ms, curve: Curves.easeOut)
        .slideY(begin: 0.04, end: 0, duration: 350.ms, curve: Curves.easeOut);
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.onImport,
    required this.onDemo,
    this.isFiltered = false,
  });

  final VoidCallback onImport;
  final VoidCallback onDemo;
  final bool isFiltered;

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
              isFiltered ? 'Nessun preferito ancora' : 'Nessun libro ancora',
              style: MarginaliaTextStyles.bookTitle.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 10),
            Text(
              isFiltered
                  ? 'Aggiungi un segnalibro a qualche highlight per vederlo qui.'
                  : 'Importa il file My Clippings.txt\ndal tuo Kindle per cominciare.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MarginaliaColors.inkMuted,
                height: 1.6,
                fontSize: 14,
              ),
            ),
            if (!isFiltered) ...[
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
                  style:
                      TextStyle(color: MarginaliaColors.siennaLight),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
