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
            return const Center(child: Text('Libro non trovato.'));
          }
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 160,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(book.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: MarginaliaColors.text,
                      )),
                  background: Container(color: MarginaliaColors.surface),
                  titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                ),
                backgroundColor: MarginaliaColors.background,
                foregroundColor: MarginaliaColors.text,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Text(book.author, style: MarginaliaTextStyles.bookAuthor),
                ),
              ),
              highlightsAsync.when(
                data: (highlights) => SliverList.builder(
                  itemCount: highlights.length,
                  itemBuilder: (ctx, i) => _HighlightCard(
                    highlight: highlights[i],
                    index: i,
                    onTap: () => context.push('/highlight/${highlights[i].id}'),
                  ),
                ),
                loading: () => const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: MarginaliaColors.accent),
                  ),
                ),
                error: (e, _) => SliverFillRemaining(child: Center(child: Text('$e'))),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: MarginaliaColors.accent),
        ),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.highlight,
    required this.index,
    required this.onTap,
  });

  final Highlight highlight;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: _highlightBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MarginaliaColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Color indicator strip
            if (highlight.color != null)
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: _highlightStripColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(highlight.content, style: MarginaliaTextStyles.highlightBodySmall),
                  if (highlight.note != null && highlight.note!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(color: MarginaliaColors.border, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.edit_outlined,
                            size: 13, color: MarginaliaColors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            highlight.note!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: MarginaliaColors.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (highlight.location != null)
                        Text('pos. ${highlight.location}', style: MarginaliaTextStyles.label),
                      const Spacer(),
                      if (highlight.isFavorite)
                        const Icon(Icons.bookmark, size: 14, color: MarginaliaColors.accent),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => Share.share(highlight.content),
                        child: const Icon(Icons.ios_share, size: 16, color: MarginaliaColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: (index * 30).ms)
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.04, end: 0);
  }

  Color get _highlightBackgroundColor {
    return switch (highlight.color) {
      'yellow' => MarginaliaColors.highlightYellow.withAlpha(80),
      'blue' => MarginaliaColors.highlightBlue.withAlpha(80),
      'pink' => MarginaliaColors.highlightPink.withAlpha(80),
      'orange' => MarginaliaColors.highlightOrange.withAlpha(80),
      _ => MarginaliaColors.surface,
    };
  }

  Color get _highlightStripColor {
    return switch (highlight.color) {
      'yellow' => const Color(0xFFFFC107),
      'blue' => const Color(0xFF2196F3),
      'pink' => const Color(0xFFE91E63),
      'orange' => const Color(0xFFFF9800),
      _ => MarginaliaColors.border,
    };
  }
}
