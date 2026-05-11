import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/books_provider.dart';

class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({super.key, required this.bookId});

  final int bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(bookByIdProvider(bookId));
    final highlightsAsync = ref.watch(highlightsByBookProvider(bookId));

    return Scaffold(
      body: bookAsync.when(
        data: (book) {
          if (book == null) {
            return const Center(
              child: Text(
                'Libro non trovato.',
                style: TextStyle(color: MarginaliaColors.inkMuted),
              ),
            );
          }

          final coverColor = MarginaliaDecorations.bookCoverColor(book.title);

          return CustomScrollView(
            slivers: [
              // ── Header editoriale ──────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: coverColor,
                foregroundColor: Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: coverColor),
                      // Texture overlay
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withAlpha(0),
                                Colors.black.withAlpha(60),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Titolo + autore centrati in basso
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              book.title,
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
                              maxLines: 3,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              book.author.toUpperCase(),
                              style: MarginaliaTextStyles.bookAuthor.copyWith(
                                color: Colors.white.withAlpha(180),
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  titlePadding: EdgeInsets.zero,
                  title: const SizedBox.shrink(),
                ),
              ),

              // ── Intestazione highlight ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 12),
                  child: Row(
                    children: [
                      Text('HIGHLIGHT', style: MarginaliaTextStyles.sectionTitle),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Divider(color: MarginaliaColors.ruleFaint, height: 1),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Lista highlight ────────────────────────────────────────────
              highlightsAsync.when(
                data: (highlights) => highlights.isEmpty
                    ? SliverFillRemaining(
                        child: Center(
                          child: Text(
                            'Nessun highlight per questo libro.',
                            style: TextStyle(color: MarginaliaColors.inkMuted),
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                        sliver: SliverList.builder(
                          itemCount: highlights.length,
                          itemBuilder: (ctx, i) => _HighlightCard(
                            highlight: highlights[i],
                            index: i,
                            coverColor: coverColor,
                            onTap: () => context.push('/highlight/${highlights[i].id}'),
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
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: MarginaliaColors.sienna,
            strokeWidth: 1.5,
          ),
        ),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

// ─── Highlight card con bordo sinistro colorato ───────────────────────────────

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
              // Bordo sinistro colorato — il tratto di penna del lettore
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
                      // Numero progressivo stile libro
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
                              style: MarginaliaTextStyles.highlightBodySmall,
                            ),
                          ),
                        ],
                      ),

                      // Nota marginale
                      if (highlight.note != null && highlight.note!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          decoration: BoxDecoration(
                            color: MarginaliaColors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.edit_outlined,
                                size: 12,
                                color: MarginaliaColors.inkFaint,
                              ),
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
                              'pos. ${highlight.location}',
                              style: MarginaliaTextStyles.label,
                            ),
                          const Spacer(),
                          if (highlight.isFavorite)
                            const Padding(
                              padding: EdgeInsets.only(right: 10),
                              child: Icon(
                                Icons.bookmark,
                                size: 13,
                                color: MarginaliaColors.sienna,
                              ),
                            ),
                          GestureDetector(
                            onTap: () => Share.share(highlight.content),
                            child: const Icon(
                              Icons.ios_share,
                              size: 15,
                              color: MarginaliaColors.inkFaint,
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
      ),
    )
        .animate(delay: (index * 35).ms)
        .fadeIn(duration: 300.ms, curve: Curves.easeOut)
        .slideY(begin: 0.03, end: 0, duration: 300.ms, curve: Curves.easeOut);
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
