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
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          highlightAsync.when(
            data: (h) => h != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          h.isFavorite ? Icons.bookmark : Icons.bookmark_border,
                          color: h.isFavorite
                              ? MarginaliaColors.sienna
                              : MarginaliaColors.inkMuted,
                        ),
                        onPressed: () => ref
                            .read(highlightFavoriteNotifierProvider.notifier)
                            .toggleFavorite(highlightId),
                      ),
                      IconButton(
                        icon: const Icon(Icons.ios_share, color: MarginaliaColors.inkMuted),
                        onPressed: () => Share.share(h.content),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: highlightAsync.when(
        data: (highlight) {
          if (highlight == null) {
            return const Center(
              child: Text(
                'Highlight non trovato.',
                style: TextStyle(color: MarginaliaColors.inkMuted),
              ),
            );
          }
          return _HighlightBody(highlight: highlight);
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

class _HighlightBody extends ConsumerWidget {
  const _HighlightBody({required this.highlight});

  final dynamic highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(bookByIdProvider(highlight.book?.id ?? highlight.book?.value?.id ?? -1));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Info libro ─────────────────────────────────────────────────────
          bookAsync.when(
            data: (book) => book != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 2,
                        color: MarginaliaColors.siennaLight,
                        margin: const EdgeInsets.only(bottom: 14),
                      ),
                      Text(book.title, style: MarginaliaTextStyles.bookTitle),
                      const SizedBox(height: 4),
                      Text(
                        book.author.toUpperCase(),
                        style: MarginaliaTextStyles.bookAuthor,
                      ),
                      const SizedBox(height: 32),
                    ],
                  )
                : const SizedBox(height: 16),
            loading: () => const SizedBox(height: 16),
            error: (_, __) => const SizedBox(height: 16),
          ),

          // ── Virgoletta decorativa ──────────────────────────────────────────
          Text('"', style: MarginaliaTextStyles.quoteDecor),

          const SizedBox(height: 4),

          // ── Testo highlight ────────────────────────────────────────────────
          Text(
            highlight.content as String,
            style: MarginaliaTextStyles.highlightBody,
          )
              .animate()
              .fadeIn(duration: 600.ms, curve: Curves.easeOut)
              .slideY(begin: 0.04, end: 0, duration: 600.ms, curve: Curves.easeOut),

          const SizedBox(height: 40),

          // ── Riga decorativa ────────────────────────────────────────────────
          const Divider(color: MarginaliaColors.ruleFaint),

          const SizedBox(height: 16),

          // ── Nota ──────────────────────────────────────────────────────────
          if ((highlight.note as String?) != null &&
              (highlight.note as String).isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MarginaliaColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MarginaliaColors.ruleFaint),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: MarginaliaColors.inkFaint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      highlight.note as String,
                      style: const TextStyle(
                        color: MarginaliaColors.inkMuted,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Metadati ───────────────────────────────────────────────────────
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              if ((highlight.location as String?) != null)
                _MetaChip(
                  icon: Icons.place_outlined,
                  label: 'Posizione ${highlight.location}',
                ),
              if ((highlight.addedAt as DateTime?) != null)
                _MetaChip(
                  icon: Icons.calendar_today_outlined,
                  label: _formatDate(highlight.addedAt as DateTime),
                ),
              if ((highlight.color as String?) != null)
                _MetaChip(
                  icon: Icons.circle,
                  label: _colorName(highlight.color as String),
                  iconColor: _colorFor(highlight.color as String),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day} ${_monthName(date.month)} ${date.year}';

  String _monthName(int m) => const [
        '',
        'gen',
        'feb',
        'mar',
        'apr',
        'mag',
        'giu',
        'lug',
        'ago',
        'set',
        'ott',
        'nov',
        'dic'
      ][m];

  String _colorName(String c) => switch (c) {
        'yellow' => 'Giallo',
        'blue' => 'Blu',
        'pink' => 'Rosa',
        'orange' => 'Arancione',
        _ => c,
      };

  Color _colorFor(String c) => switch (c) {
        'yellow' => const Color(0xFFD4A017),
        'blue' => const Color(0xFF4A90BF),
        'pink' => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _ => MarginaliaColors.inkFaint,
      };
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.iconColor});

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: iconColor ?? MarginaliaColors.inkFaint),
        const SizedBox(width: 5),
        Text(label, style: MarginaliaTextStyles.label),
      ],
    );
  }
}
