import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/books_provider.dart';
import '../../core/services/export_service.dart';

class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({super.key, required this.bookId});

  final int bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(bookByIdProvider(bookId));
    final highlightsAsync = ref.watch(highlightsByBookProvider(bookId));

    return bookAsync.when(
      data: (book) {
        if (book == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text('Libro non trovato.',
                  style: TextStyle(color: MarginaliaColors.inkMuted)),
            ),
          );
        }

        final coverColor = MarginaliaDecorations.bookCoverColor(book.title);
        final initial =
            book.title.isNotEmpty ? book.title[0].toUpperCase() : '?';

        final highlightCount = highlightsAsync.maybeWhen(
          data: (h) => h.length,
          orElse: () => 0,
        );

        return Scaffold(
          backgroundColor: MarginaliaColors.background,
          body: Stack(
            children: [
              // ── Hero colorato (full screen height = copertina) ────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 300,
                child: _BookHero(
                  coverColor: coverColor,
                  initial: initial,
                  title: book.title,
                  author: book.author,
                  highlightCount: highlightCount,
                ),
              ),

              // ── Panel sovrapposto (stile CourseInfoScreen) ────────────────
              Positioned.fill(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.62,
                  minChildSize: 0.62,
                  maxChildSize: 1.0,
                  builder: (ctx, scrollCtrl) {
                    return Container(
                      decoration: const BoxDecoration(
                        color: MarginaliaColors.background,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(28),
                          topRight: Radius.circular(28),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x20261E1D),
                            blurRadius: 20,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      child: CustomScrollView(
                        controller: scrollCtrl,
                        slivers: [
                          // Handle
                          SliverToBoxAdapter(
                            child: Column(
                              children: [
                                const SizedBox(height: 12),
                                Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: MarginaliaColors.rule,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),

                          // ── Stat boxes (stile CourseInfoScreen) ──────────
                          SliverToBoxAdapter(
                            child: _StatRow(
                              highlightCount: highlightCount,
                              author: book.author,
                            ),
                          ),

                          // ── Sezione header ────────────────────────────────
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(22, 28, 22, 12),
                              child: Row(
                                children: [
                                  Text('HIGHLIGHT',
                                      style:
                                          MarginaliaTextStyles.sectionTitle),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Divider(
                                        color: MarginaliaColors.ruleFaint,
                                        height: 1),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // ── Lista highlights ──────────────────────────────
                          highlightsAsync.when(
                            data: (highlights) => highlights.isEmpty
                                ? SliverFillRemaining(
                                    child: Center(
                                      child: Text(
                                        'Nessun highlight per questo libro.',
                                        style: TextStyle(
                                            color:
                                                MarginaliaColors.inkMuted),
                                      ),
                                    ),
                                  )
                                : SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 0, 16, 60),
                                    sliver: SliverList.builder(
                                      itemCount: highlights.length,
                                      itemBuilder: (c, i) => _HighlightCard(
                                        highlight: highlights[i],
                                        index: i,
                                        coverColor: coverColor,
                                        onTap: () => context.push(
                                            '/highlight/${highlights[i].id}'),
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
                            error: (e, _) => SliverFillRemaining(
                              child: Center(child: Text('$e')),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // ── Back button (sovrapposto all'hero) ────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(50),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 20),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),

              // ── Export button (top-right) ─────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: highlightsAsync.maybeWhen(
                  data: (highlights) => highlights.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: 'Esporta in Markdown',
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(50),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.download_outlined,
                                color: Colors.white, size: 20),
                          ),
                          onPressed: () async {
                            try {
                              await ExportService.exportBook(
                                bookTitle: book.title,
                                bookAuthor: book.author,
                                highlights: highlights,
                              );
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Errore esportazione: $e')),
                                );
                              }
                            }
                          },
                        ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Scaffold(
        backgroundColor: MarginaliaColors.background,
        body: const Center(
          child: CircularProgressIndicator(
            color: MarginaliaColors.sienna,
            strokeWidth: 1.5,
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$e')),
      ),
    );
  }
}

// ─── Hero copertina ───────────────────────────────────────────────────────────

class _BookHero extends StatelessWidget {
  const _BookHero({
    required this.coverColor,
    required this.initial,
    required this.title,
    required this.author,
    required this.highlightCount,
  });

  final Color coverColor;
  final String initial;
  final String title;
  final String author;
  final int highlightCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [coverColor, coverColor.withAlpha(210)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Virgoletta decorativa — EB Garamond
          Positioned(
            bottom: 60,
            right: 16,
            child: Text(
              '"',
              style: MarginaliaTextStyles.quoteDecor.copyWith(
                fontSize: 160,
                height: 1,
                color: Colors.white.withAlpha(16),
              ),
            ),
          ),
          // Initial letter — EB Garamond serif
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 80,
            child: Center(
              child: Text(
                initial,
                style: MarginaliaTextStyles.bookTitleLarge.copyWith(
                  fontSize: 88,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withAlpha(195),
                  height: 1,
                ),
              ),
            ),
          ),
          // Titolo + autore in basso
          Positioned(
            left: 20,
            right: 20,
            bottom: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MarginaliaTextStyles.bookTitleLarge.copyWith(
                    color: Colors.white,
                    fontSize: 20,
                    shadows: [
                      const Shadow(
                        color: Color(0x40000000),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  author.toUpperCase(),
                  style: MarginaliaTextStyles.bookAuthor.copyWith(
                    color: Colors.white.withAlpha(175),
                    letterSpacing: 1.2,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stat boxes (stile CourseInfoScreen 3-box row) ────────────────────────────

class _StatRow extends StatelessWidget {
  const _StatRow({required this.highlightCount, required this.author});

  final int highlightCount;
  final String author;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _StatBox(
            value: '$highlightCount',
            label: highlightCount == 1 ? 'highlight' : 'highlights',
            icon: Icons.format_quote_outlined,
          ),
          // Sottile divisore verticale
          Container(
            width: 0.8, height: 32,
            color: MarginaliaColors.ruleFaint,
            margin: const EdgeInsets.symmetric(horizontal: 20),
          ),
          _StatBox(
            value: author.split(' ').last,
            label: 'autore',
            icon: Icons.person_outline,
          ),
          Container(
            width: 0.8, height: 32,
            color: MarginaliaColors.ruleFaint,
            margin: const EdgeInsets.symmetric(horizontal: 20),
          ),
          _StatBox(
            value: '',
            label: 'in lettura',
            icon: Icons.menu_book_outlined,
          ),
        ],
      )
          .animate()
          .fadeIn(delay: 100.ms, duration: 350.ms)
          .slideY(begin: 0.04, end: 0, delay: 100.ms, duration: 350.ms),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          // Valore in EB Garamond
          if (value.isNotEmpty)
            Text(
              value,
              style: MarginaliaTextStyles.bookTitle.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.ink,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 18, color: MarginaliaColors.sienna),
          const SizedBox(height: 3),
          // Label in Barlow Condensed uppercase
          Text(
            label.toUpperCase(),
            style: MarginaliaTextStyles.sectionTitle.copyWith(
              fontSize: 8.5,
              letterSpacing: 1.5,
              color: MarginaliaColors.inkFaint,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Highlight card ───────────────────────────────────────────────────────────

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.highlight,
    required this.index,
    required this.coverColor,
    required this.onTap,
  });

  final Highlight highlight;
  final int index;
  final Color coverColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header: numero + colore dot ──────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${(index + 1).toString().padLeft(2, '0')}',
                        style: MarginaliaTextStyles.indexNumber.copyWith(
                          color: MarginaliaColors.inkFaint,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Spacer(),
                      if (highlight.isFavorite)
                        const Icon(
                          Icons.bookmark_rounded,
                          size: 14,
                          color: MarginaliaColors.sienna,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Testo in EB Garamond italic ────────────────────
                  Text(
                    highlight.content,
                    style: MarginaliaTextStyles.highlightBodySmall.copyWith(
                      fontSize: 15.5,
                      height: 1.75,
                    ),
                  ),

                  // ── Nota marginale ─────────────────────────────────
                  if (highlight.note != null && highlight.note!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.edit_outlined,
                            size: 11, color: MarginaliaColors.inkFaint),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            highlight.note!,
                            style: GoogleFonts.barlow(
                              fontSize: 12,
                              color: MarginaliaColors.inkMuted,
                              fontStyle: FontStyle.italic,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // ── Footer metadati ────────────────────────────────
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (highlight.location != null)
                        Text(
                          'pos. ${highlight.location}',
                          style: MarginaliaTextStyles.label.copyWith(
                            fontSize: 10,
                            color: MarginaliaColors.inkFaint,
                          ),
                        ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Share.share(highlight.content),
                        child: const Icon(Icons.ios_share_rounded,
                            size: 14, color: MarginaliaColors.inkFaint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
            // Divider sottile tra highlight
            Container(height: 0.8, color: MarginaliaColors.ruleFaint),
          ],
        ),
      ),
    )
        .animate(delay: (index * 35).ms)
        .fadeIn(duration: 300.ms, curve: Curves.easeOut)
        .slideY(
            begin: 0.03, end: 0, duration: 300.ms, curve: Curves.easeOut);
  }

  Color get _accentColor {
    return switch (highlight.color) {
      'yellow' => const Color(0xFFD4A017),
      'blue' => const Color(0xFF4A90BF),
      'pink' => const Color(0xFFBF4A72),
      'orange' => const Color(0xFFBF7A34),
      _ => MarginaliaColors.siennaLight,
    };
  }
}
