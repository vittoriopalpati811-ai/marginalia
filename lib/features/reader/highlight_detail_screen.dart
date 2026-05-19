import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/services/share_card_service.dart';

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
        // Back button usa il colore ink
        iconTheme: const IconThemeData(color: MarginaliaColors.inkMuted),
        actions: [
          highlightAsync.when(
            data: (h) => h != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Bookmark
                      IconButton(
                        icon: Icon(
                          h.isFavorite
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_outline_rounded,
                          color: h.isFavorite
                              ? MarginaliaColors.sienna
                              : MarginaliaColors.inkFaint,
                          size: 22,
                        ),
                        onPressed: () => ref
                            .read(highlightFavoriteNotifierProvider.notifier)
                            .toggleFavorite(highlightId),
                      ),
                      // Share
                      IconButton(
                        icon: const Icon(
                          Icons.ios_share_rounded,
                          color: MarginaliaColors.inkFaint,
                          size: 20,
                        ),
                        onPressed: () => ShareCardService.show(
                          context,
                          content: h.content,
                          bookTitle: h.bookTitle,
                          bookAuthor: h.bookAuthor,
                          kindleColor: h.color,
                        ),
                      ),
                      const SizedBox(width: 8),
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
            return Center(
              child: Text(
                'Highlight non trovato.',
                style: MarginaliaTextStyles.label
                    .copyWith(color: MarginaliaColors.inkFaint),
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

  static (String?, String?) _embeddedBook(dynamic h) {
    try {
      final title = h.bookTitle as String?;
      final author = h.bookAuthor as String?;
      if (title != null) return (title, author);
    } catch (_) {}
    return (null, null);
  }

  static int _bookId(dynamic h) {
    try { return (h.book?.value?.id as int?) ?? -1; } catch (_) {}
    try { return (h.bookId as int?) ?? -1; } catch (_) {}
    return -1;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (embTitle, embAuthor) = _embeddedBook(highlight);
    final bookAsync = embTitle == null
        ? ref.watch(bookByIdProvider(_bookId(highlight)))
        : null;

    // Colore highlight per l'indicatore
    final hlColor = _colorFor(highlight.color as String?);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Intestazione libro ─────────────────────────────────────────────
          if (embTitle != null)
            _BookHeader(title: embTitle, author: embAuthor ?? '', accentColor: hlColor)
          else if (bookAsync != null)
            bookAsync.when(
              data: (book) => book != null
                  ? _BookHeader(title: book.title, author: book.author, accentColor: hlColor)
                  : const SizedBox(height: 16),
              loading: () => const SizedBox(height: 16),
              error: (_, __) => const SizedBox(height: 16),
            )
          else
            const SizedBox(height: 24),

          // ── Zona quote principale ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Virgoletta ornamentale
                Text(
                  '“',
                  style: MarginaliaTextStyles.quoteDecor.copyWith(
                    fontSize: 80,
                    height: 0.65,
                    color: MarginaliaColors.siennaFaint,
                  ),
                ),
                const SizedBox(height: 6),

                // Testo highlight — EB Garamond italic grande, cuore dell'app
                Text(
                  highlight.content as String,
                  style: MarginaliaTextStyles.highlightBody.copyWith(
                    fontSize: 21,
                    height: 1.85,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 700.ms, curve: Curves.easeOut)
                    .slideY(begin: 0.03, end: 0, duration: 700.ms, curve: Curves.easeOut),

                const SizedBox(height: 40),

                // ── Regola ornamentale ─────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 0.8,
                      color: hlColor.withAlpha(180),
                    ),
                    Expanded(
                      child: Container(height: 0.8, color: MarginaliaColors.ruleFaint),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Nota personale (se presente) ───────────────────────────
                if ((highlight.note as String?) != null &&
                    (highlight.note as String).isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        size: 13,
                        color: MarginaliaColors.inkFaint,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          highlight.note as String,
                          style: GoogleFonts.barlow(
                            color: MarginaliaColors.inkMuted,
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            height: 1.65,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Metadati ───────────────────────────────────────────────
                Wrap(
                  spacing: 20,
                  runSpacing: 10,
                  children: [
                    if ((highlight.location as String?) != null)
                      _MetaItem(
                        icon: Icons.straighten_outlined,
                        label: 'Pos. ${highlight.location}',
                      ),
                    if ((highlight.addedAt as DateTime?) != null)
                      _MetaItem(
                        icon: Icons.calendar_today_outlined,
                        label: _formatDate(highlight.addedAt as DateTime),
                      ),
                    if ((highlight.color as String?) != null)
                      _MetaItem(
                        icon: Icons.circle,
                        label: _colorName(highlight.color as String),
                        iconColor: hlColor,
                      ),
                  ],
                ),

                const SizedBox(height: 120), // spazio per la nav bar
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day} ${_monthName(date.month)} ${date.year}';

  String _monthName(int m) => const [
        '',
        'gen', 'feb', 'mar', 'apr', 'mag', 'giu',
        'lug', 'ago', 'set', 'ott', 'nov', 'dic',
      ][m];

  String _colorName(String c) => switch (c) {
        'yellow' => 'Giallo',
        'blue'   => 'Blu',
        'pink'   => 'Rosa',
        'orange' => 'Arancione',
        _        => c,
      };

  Color _colorFor(String? c) => switch (c) {
        'yellow' => const Color(0xFFD4A017),
        'blue'   => const Color(0xFF4A90BF),
        'pink'   => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _        => MarginaliaColors.siennaLight,
      };
}

// ─── Intestazione libro ───────────────────────────────────────────────────────

class _BookHeader extends StatelessWidget {
  const _BookHeader({
    required this.title,
    required this.author,
    required this.accentColor,
  });
  final String title;
  final String author;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
      decoration: BoxDecoration(
        color: MarginaliaColors.surface,
        border: const Border(
          bottom: BorderSide(color: MarginaliaColors.ruleFaint, width: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indicatore colore highlight + label "DA"
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'DA',
                style: MarginaliaTextStyles.sectionTitle.copyWith(
                  fontSize: 9,
                  letterSpacing: 2.5,
                  color: MarginaliaColors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: MarginaliaTextStyles.bookTitle.copyWith(fontSize: 16),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (author.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              author.toUpperCase(),
              style: MarginaliaTextStyles.bookAuthor,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Metadato singolo ────────────────────────────────────────────────────────

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label, this.iconColor});

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: iconColor ?? MarginaliaColors.inkFaint),
        const SizedBox(width: 5),
        Text(
          label,
          style: MarginaliaTextStyles.label.copyWith(
            fontSize: 11,
            color: MarginaliaColors.inkFaint,
          ),
        ),
      ],
    );
  }
}
