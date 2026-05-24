import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/models/book.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/services/import_service.dart';
import '../../core/providers/isar_provider.dart';
import 'book_cover.dart';
import 'recommendations_section.dart';

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
  bool _isImporting  = false;
  bool _showAllBooks = false; // toggles the "La tua libreria" grid

  @override
  Widget build(BuildContext context) {
    final booksAsync        = ref.watch(booksProvider);
    final allHighlightsAsync = ref.watch(allHighlightsProvider);
    final filter            = ref.watch(_libraryFilterProvider);
    final randomAsync       = ref.watch(randomHighlightProvider);

    // Apply filter
    final filteredBooksAsync = booksAsync.whenData((books) {
      if (filter == _LibraryFilter.favorites) {
        final favBookIds = allHighlightsAsync.maybeWhen(
          data: (hl) =>
              hl.where((h) => h.isFavorite).map((h) => h.bookId).toSet(),
          orElse: () => <int>{},
        );
        return books.where((b) => favBookIds.contains(b.id)).toList();
      }
      return books;
    });

    // Derive display list: max 3 when collapsed, all when expanded
    final allBooks     = filteredBooksAsync.value;
    final hasMoreBooks = (allBooks?.length ?? 0) > 3;
    final displayBooks = allBooks == null
        ? <Book>[]
        : (_showAllBooks ? allBooks : allBooks.take(3).toList());

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: RefreshIndicator(
        onRefresh: () async => _invalidateAfterImport(),
        color: MarginaliaColors.sienna,
        backgroundColor: MarginaliaColors.surfaceElevated,
        displacement: 60,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header editoriale ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: _EditorialHeader(
                isImporting:    _isImporting,
                onImport:       _pickAndImportFile,
                onForceReimport: () => _pickAndImportFile(forceClean: true),
                userName: ref.watch(_myDisplayNameProvider).asData?.value,
              ),
            ),

            // ── Hero pull-quote: highlight del giorno ──────────────────────
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
              loading: () =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // ── Strip highlights recenti ───────────────────────────────────
            allHighlightsAsync.when(
              data: (highlights) {
                if (highlights.isEmpty) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverToBoxAdapter(
                  child: _RecentHighlightsStrip(
                    highlights: highlights.take(8).toList(),
                    onTap: (h) => context.push('/highlight/${h.id}'),
                  ),
                );
              },
              loading: () =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // ── "LA TUA LIBRERIA" header + filter chips ────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          context.l10n.libraryTitle.toUpperCase(),
                          style: MarginaliaTextStyles.sectionTitle,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Divider(
                            color: MarginaliaColors.ruleFaint,
                            height: 1,
                          ),
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

            // ── Book grid (max 3 when collapsed) ──────────────────────────
            if (allBooks == null)
              // Loading
              const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(
                      color: MarginaliaColors.sienna,
                      strokeWidth: 1.5,
                    ),
                  ),
                ),
              )
            else if (allBooks.isEmpty)
              SliverFillRemaining(
                child: _EmptyLibrary(
                  onImport: _pickAndImportFile,
                  onDemo:   _loadDemoData,
                  isFiltered: filter != _LibraryFilter.all,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _BookGridCard(
                      book:  displayBooks[i],
                      index: i,
                      onTap: () => context.push('/book/${displayBooks[i].id}'),
                    ),
                    childCount: displayBooks.length,
                  ),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:   2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing:  12,
                    childAspectRatio: 0.72,
                  ),
                ),
              ),

            // ── "Vedi tutti / Nascondi" button ────────────────────────────
            if (allBooks != null && allBooks.isNotEmpty && hasMoreBooks)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _showAllBooks = !_showAllBooks),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: MarginaliaColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: MarginaliaColors.rule,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _showAllBooks
                                ? 'Nascondi'
                                : 'Vedi tutti i ${allBooks.length} libri',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: MarginaliaColors.primary,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _showAllBooks
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: MarginaliaColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ── Libri consigliati ─────────────────────────────────────────
            const SliverToBoxAdapter(
              child: LibraryRecommendationsSection(),
            ),

            // ── Bottom padding for nav bar ─────────────────────────────────
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  // ─── Encoding ────────────────────────────────────────────────────────────────

  String _decodeClippings(Uint8List bytes) {
    var data = bytes;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      data = bytes.sublist(3);
    }
    try {
      return utf8.decode(data);
    } catch (_) {}
    return latin1.decode(data);
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

  // ─── Import da file picker ───────────────────────────────────────────────────

  Future<void> _pickAndImportFile({bool forceClean = false}) async {
    if (!_requireAuth()) return;

    if (forceClean) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: MarginaliaColors.surfaceElevated,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('Cancella e reimporta?',
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          content: const Text(
            'Tutti i tuoi highlight e libri verranno eliminati da Supabase, '
            'poi reimportati dal file scelto.\n\n'
            'Utile per correggere caratteri corrotti da import precedenti.',
            style: TextStyle(
                color: MarginaliaColors.inkMuted,
                fontSize: 14,
                height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB54848)),
              child: const Text('Cancella e reimporta'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    var rawText = _decodeClippings(file.bytes!);
    setState(() => _isImporting = true);

    if (forceClean) {
      try {
        await ref.read(supabaseServiceProvider).deleteAllUserData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Errore pulizia dati: $e')));
        }
        setState(() => _isImporting = false);
        return;
      }
    }

    try {
      final userId  = ref.read(currentUserProvider)?.id ?? 'local';
      final isar    = ref.read(isarProvider);
      final supabase = ref.read(supabaseServiceProvider);
      final service = ImportService(isar, userId, supabaseService: supabase);
      final importResult = await service.importClippingsText(rawText);
      _invalidateAfterImport();

      if (mounted) {
        final msg = importResult.firstError != null
            ? 'Import parziale — ${importResult.highlightsAdded} HL, '
                '${importResult.highlightsFailed} errori.\n${importResult.firstError}'
            : importResult.highlightsAdded > 0
                ? '${importResult.highlightsAdded} highlight importati da '
                    '${importResult.booksAdded} libri.'
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Errore importazione: $e')));
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _invalidateAfterImport() {
    ref.invalidate(booksProvider);
    ref.invalidate(randomHighlightProvider);
    ref.invalidate(allHighlightsProvider);
    ref.invalidate(libraryRecommendationsProvider);
  }

  // ─── Demo data ───────────────────────────────────────────────────────────────

  Future<void> _loadDemoData() async {
    if (!_requireAuth()) return;
    setState(() => _isImporting = true);
    try {
      var rawText =
          await rootBundle.loadString('assets/demo/My Clippings.txt');
      if (rawText.startsWith('﻿')) rawText = rawText.substring(1);

      final userId  = ref.read(currentUserProvider)?.id ?? 'local';
      final isar    = ref.read(isarProvider);
      final supabase = ref.read(supabaseServiceProvider);
      final service = ImportService(isar, userId, supabaseService: supabase);
      final result  = await service.importClippingsText(rawText);
      _invalidateAfterImport();
      if (mounted) {
        final msg = result.firstError != null
            ? 'Import parziale — ${result.booksAdded} libri, '
                '${result.highlightsAdded} HL.\nErrore: ${result.firstError}'
            : result.highlightsAdded > 0
                ? 'Demo caricata: ${result.highlightsAdded} highlight da '
                    '${result.booksAdded} libri.'
                : 'I dati demo sono già presenti.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration:
                Duration(seconds: result.firstError != null ? 15 : 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Errore caricamento demo: $e')));
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }
}

// ─── Greeting utility ─────────────────────────────────────────────────────────

String contextualGreeting(String? name, {int? hour}) {
  final h = hour ?? DateTime.now().hour;
  final String base;
  if (h < 6)       base = 'Così presto';
  else if (h < 12) base = 'Buongiorno';
  else if (h < 13) base = 'Prenditi una pausa';
  else if (h < 18) base = 'Buon pomeriggio';
  else if (h < 21) base = 'Buonasera';
  else             base = 'Buonanotte';

  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return base;
  final suffix = h < 6 ? ', $trimmed?' : ', $trimmed';
  return '$base$suffix';
}

// ─── Provider for current user display name ───────────────────────────────────

final _myDisplayNameProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated || svc.userId == null) return null;
  try {
    final p = await svc.fetchPublicProfile(svc.userId!);
    return p?['display_name'] as String?;
  } catch (_) {
    return null;
  }
});

// ─── Header editoriale ────────────────────────────────────────────────────────

class _EditorialHeader extends StatelessWidget {
  const _EditorialHeader({
    required this.isImporting,
    required this.onImport,
    required this.onForceReimport,
    this.userName,
  });

  final bool isImporting;
  final VoidCallback onImport;
  final VoidCallback onForceReimport;
  final String? userName;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, top + 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Marginalia',
                  style: MarginaliaTextStyles.bookTitleLarge.copyWith(
                    fontSize: 30,
                    color: MarginaliaColors.primary,
                    letterSpacing: -0.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isImporting)
                const Padding(
                  padding: EdgeInsets.only(top: 4, right: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: MarginaliaColors.sienna,
                    ),
                  ),
                )
              else
                GestureDetector(
                  onLongPress: onForceReimport,
                  child: IconButton(
                    icon: const Icon(Icons.upload_file_outlined),
                    color: MarginaliaColors.inkFaint,
                    iconSize: 20,
                    tooltip:
                        'Importa · Tieni premuto per reimportare da zero',
                    onPressed: onImport,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            contextualGreeting(userName),
            style: MarginaliaTextStyles.label.copyWith(
              color: MarginaliaColors.inkFaint,
              letterSpacing: 0.2,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 0.8, color: MarginaliaColors.ruleFaint),
        ],
      ),
    );
  }
}

// ─── Hero pull-quote: highlight del giorno ───────────────────────────────────

class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.content, required this.onTap});

  final String content;
  final VoidCallback onTap;

  static const _days = ['LUN', 'MAR', 'MER', 'GIO', 'VEN', 'SAB', 'DOM'];

  @override
  Widget build(BuildContext context) {
    final text =
        content.length > 260 ? '${content.substring(0, 260)}…' : content;
    final dayLabel = _days[DateTime.now().weekday - 1];

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('HIGHLIGHT DEL GIORNO',
                    style: MarginaliaTextStyles.sectionTitle),
                const SizedBox(width: 10),
                Text(
                  '·  $dayLabel',
                  style: MarginaliaTextStyles.sectionTitle.copyWith(
                    color: MarginaliaColors.inkFaint,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 0.8, color: MarginaliaColors.rule),
            const SizedBox(height: 20),
            Text(
              '"',
              style: MarginaliaTextStyles.quoteDecor.copyWith(
                fontSize: 64,
                height: 0.5,
                color: MarginaliaColors.siennaFaint,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: MarginaliaTextStyles.highlightBody.copyWith(
                fontSize: 19,
                height: 1.82,
                color: MarginaliaColors.ink,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Container(
                      height: 0.8,
                      color: MarginaliaColors.ruleFaint),
                ),
                const SizedBox(width: 12),
                Text(
                  'Leggi',
                  style: MarginaliaTextStyles.label.copyWith(
                    color: MarginaliaColors.sienna,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 10,
                  color: MarginaliaColors.sienna,
                ),
              ],
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

// ─── Strip highlights recenti ─────────────────────────────────────────────────

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
                child: Divider(
                    color: MarginaliaColors.ruleFaint, height: 1),
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
              final h           = highlights[i];
              final accentColor = _accentFor(h.color);
              return GestureDetector(
                onTap: () => onTap(h),
                child: Container(
                  width: 240,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: MarginaliaColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: MarginaliaColors.rule),
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
                    child: Stack(
                      children: [
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((h.bookTitle ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Text(
                                    h.bookTitle!.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MarginaliaTextStyles.bookAuthor
                                        .copyWith(
                                      fontSize: 9,
                                      color: MarginaliaColors.inkFaint,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 7),
                              Expanded(
                                child: Text(
                                  h.content,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: _QuoteStyle.strip,
                                ),
                              ),
                            ],
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
        'blue'   => const Color(0xFF4A90BF),
        'pink'   => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _        => MarginaliaColors.siennaLight,
      };
}

class _QuoteStyle {
  static final strip = MarginaliaTextStyles.highlightBodySmall.copyWith(
    fontSize: 13,
    height: 1.6,
  );
}

// ─── Filter chips ─────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});

  final _LibraryFilter selected;
  final ValueChanged<_LibraryFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(
          label:  'Tutti',
          icon:   Icons.auto_stories_outlined,
          active: selected == _LibraryFilter.all,
          onTap:  () => onSelect(_LibraryFilter.all),
        ),
        const SizedBox(width: 8),
        _Chip(
          label:  'Preferiti',
          icon:   Icons.bookmark_outline,
          active: selected == _LibraryFilter.favorites,
          onTap:  () => onSelect(_LibraryFilter.favorites),
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

  final String   label;
  final IconData icon;
  final bool     active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? MarginaliaColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color:
                active ? MarginaliaColors.primary : MarginaliaColors.rule,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active
                  ? const Color(0xFFF1EEE7)
                  : MarginaliaColors.inkMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: MarginaliaTextStyles.sectionTitle.copyWith(
                color: active
                    ? const Color(0xFFF1EEE7)
                    : MarginaliaColors.inkMuted,
                letterSpacing: 1.5,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Book grid card ───────────────────────────────────────────────────────────

class _BookGridCard extends StatelessWidget {
  const _BookGridCard({
    required this.book,
    required this.index,
    required this.onTap,
  });

  final Book       book;
  final int        index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            Expanded(
              flex: 63,
              child: BookEditorialCover(
                title: book.title,
                author: book.author,
                borderRadius: const BorderRadius.only(
                  topLeft:  Radius.circular(15),
                  topRight: Radius.circular(15),
                ),
              ),
            ),
            Expanded(
              flex: 38,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 11, 11, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MarginaliaTextStyles.bookTitle.copyWith(
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      book.author.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MarginaliaTextStyles.bookAuthor.copyWith(
                        fontSize: 9,
                        letterSpacing: 0.6,
                      ),
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
              isFiltered
                  ? context.l10n.libraryNoFavorites
                  : context.l10n.libraryNoBooks,
              style:
                  MarginaliaTextStyles.bookTitle.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 10),
            Text(
              isFiltered
                  ? context.l10n.libraryNoFavoritesBody
                  : context.l10n.libraryNoBooksBody,
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
                label: Text(context.l10n.libraryImportClippings),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onDemo,
                icon: Icon(Icons.auto_awesome_outlined,
                    size: 16,
                    color: MarginaliaColors.siennaLight),
                label: Text(
                  context.l10n.libraryTryDemo,
                  style: const TextStyle(
                      color: MarginaliaColors.siennaLight),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Recommendations section → see recommendations_section.dart ──────────────
