import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
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
          // Texture: quote mark decorativo
          Positioned(
            bottom: 60,
            right: 16,
            child: Text(
              '"',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 160,
                height: 1,
                color: Colors.white.withAlpha(18),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Initial letter centrata
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 80,
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withAlpha(200),
                  fontFamily: 'Georgia',
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _StatBox(
            value: '$highlightCount',
            label: highlightCount == 1 ? 'highlight' : 'highlights',
            icon: Icons.format_quote_outlined,
          ),
          const SizedBox(width: 10),
          _StatBox(
            value: author.split(' ').last,
            label: 'autore',
            icon: Icons.person_outline,
          ),
          const SizedBox(width: 10),
          _StatBox(
            value: '📖',
            label: 'in lettura',
            icon: null,
          ),
        ],
      )
          .animate()
          .fadeIn(delay: 100.ms, duration: 350.ms)
          .slideY(begin: 0.05, end: 0, delay: 100.ms, duration: 350.ms),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MarginaliaColors.rule),
        ),
        child: Column(
          children: [
            if (icon != null)
              Icon(icon, size: 16, color: MarginaliaColors.sienna)
            else
              Text(value,
                  style:
                      const TextStyle(fontSize: 16, color: MarginaliaColors.sienna)),
            const SizedBox(height: 4),
            if (icon != null)
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MarginaliaColors.ink,
                ),
              ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: MarginaliaColors.inkMuted,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
        margin: const EdgeInsets.only(bottom: 10),
        decoration: MarginaliaDecorations.card(),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Bordo sinistro colorato
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Numero progressivo
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index + 1}.',
                            style: MarginaliaTextStyles.indexNumber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              highlight.content,
                              style:
                                  MarginaliaTextStyles.highlightBodySmall,
                            ),
                          ),
                        ],
                      ),

                      // Nota marginale
                      if (highlight.note != null &&
                          highlight.note!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding:
                              const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          decoration: BoxDecoration(
                            color: MarginaliaColors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.edit_outlined,
                                  size: 12,
                                  color: MarginaliaColors.inkFaint),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  highlight.note!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: MarginaliaColors.inkMuted,
                                    fontStyle: FontStyle.italic,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Footer
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (highlight.location != null)
                            Text(
                              'pos. ${highlight.location}',
                              style: MarginaliaTextStyles.label,
                            ),
                          const Spacer(),
                          if (highlight.isFavorite)
                            const Padding(
                              padding: EdgeInsets.only(right: 10),
                              child: Icon(Icons.bookmark,
                                  size: 13,
                                  color: MarginaliaColors.sienna),
                            ),
                          GestureDetector(
                            onTap: () => Share.share(highlight.content),
                            child: const Icon(Icons.ios_share,
                                size: 15,
                                color: MarginaliaColors.inkFaint),
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
