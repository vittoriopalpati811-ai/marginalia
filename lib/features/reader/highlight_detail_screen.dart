import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/books_provider.dart';

class HighlightDetailScreen extends ConsumerWidget {
  const HighlightDetailScreen({super.key, required this.highlightId});

  final int highlightId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlightAsync = ref.watch(highlightByIdProvider(highlightId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          highlightAsync.when(
            data: (h) => h != null
                ? Row(children: [
                    IconButton(
                      icon: Icon(
                        h.isFavorite ? Icons.bookmark : Icons.bookmark_border,
                        color: h.isFavorite ? MarginaliaColors.accent : null,
                      ),
                      tooltip: h.isFavorite ? 'Rimuovi preferito' : 'Aggiungi ai preferiti',
                      onPressed: () => ref
                          .read(highlightFavoriteNotifierProvider.notifier)
                          .toggleFavorite(highlightId),
                    ),
                    IconButton(
                      icon: const Icon(Icons.ios_share),
                      tooltip: 'Condividi',
                      onPressed: () => Share.share(h.content),
                    ),
                  ])
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: highlightAsync.when(
        data: (highlight) {
          if (highlight == null) {
            return const Center(child: Text('Highlight non trovato.'));
          }
          return _buildBody(context, ref, highlight);
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: MarginaliaColors.accent),
        ),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, dynamic highlight) {
    final bookAsync = ref.watch(bookByIdProvider(highlight.book.id ?? -1));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Book info
          bookAsync.when(
            data: (book) => book != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.title, style: MarginaliaTextStyles.bookTitle),
                      const SizedBox(height: 2),
                      Text(book.author, style: MarginaliaTextStyles.bookAuthor),
                      const SizedBox(height: 24),
                    ],
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // Decorative quote mark
          Text(
            '“',
            style: TextStyle(
              fontSize: 80,
              height: 0.5,
              color: MarginaliaColors.accentLight,
              fontFamily: 'serif',
            ),
          ),
          const SizedBox(height: 8),

          // Highlight content
          Text(highlight.content, style: MarginaliaTextStyles.highlightBody)
              .animate()
              .fadeIn(duration: 500.ms)
              .slideY(begin: 0.05, end: 0),

          const SizedBox(height: 32),

          // Note (if any)
          if (highlight.note != null && highlight.note!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MarginaliaColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MarginaliaColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.edit_outlined, size: 14, color: MarginaliaColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      highlight.note!,
                      style: const TextStyle(
                        color: MarginaliaColors.textMuted,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Metadata
          Row(
            children: [
              if (highlight.location != null) ...[
                const Icon(Icons.place_outlined, size: 13, color: MarginaliaColors.textMuted),
                const SizedBox(width: 4),
                Text('Posizione ${highlight.location}', style: MarginaliaTextStyles.label),
              ],
              if (highlight.addedAt != null) ...[
                const SizedBox(width: 16),
                const Icon(Icons.schedule_outlined, size: 13, color: MarginaliaColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  _formatDate(highlight.addedAt!),
                  style: MarginaliaTextStyles.label,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
