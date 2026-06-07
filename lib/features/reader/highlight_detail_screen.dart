import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/services/share_card_service.dart';
import '../../core/l10n/l10n_extension.dart';
import 'book_info_screen.dart';
import 'highlight_story_share.dart';

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
                              ? MarginaliaColors.primaryDark
                              : MarginaliaColors.inkFaint,
                          size: 22,
                        ),
                        onPressed: () => ref
                            .read(highlightFavoriteNotifierProvider.notifier)
                            .toggleFavorite(highlightId),
                      ),
                      // (The dedicated Instagram-story icon was moved OUT of the
                      // app bar into a prominent green CTA in the body below.)
                      // Share — menu with card vs. Instagram-story image
                      PopupMenuButton<_ShareAction>(
                        icon: const Icon(
                          Icons.ios_share_rounded,
                          color: MarginaliaColors.inkFaint,
                          size: 20,
                        ),
                        color: MarginaliaColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        position: PopupMenuPosition.under,
                        onSelected: (action) {
                          switch (action) {
                            case _ShareAction.card:
                              ShareCardService.show(
                                context,
                                content: h.content,
                                bookTitle: h.bookTitle,
                                bookAuthor: h.bookAuthor,
                                kindleColor: h.color,
                              );
                            case _ShareAction.story:
                              shareHighlightAsStory(
                                context,
                                text: h.content,
                                title: h.bookTitle,
                                author: h.bookAuthor,
                              );
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: _ShareAction.card,
                            child: _ShareMenuRow(
                              icon: Icons.ios_share_rounded,
                              label: context.l10n.shareImageCta,
                            ),
                          ),
                          PopupMenuItem(
                            value: _ShareAction.story,
                            child: _ShareMenuRow(
                              icon: PhosphorIconsRegular.instagramLogo,
                              label: context.l10n.shareAsStory,
                            ),
                          ),
                        ],
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
                context.l10n.highlightNotFound,
                style: MarginaliaTextStyles.label
                    .copyWith(color: MarginaliaColors.inkFaint),
              ),
            );
          }
          return _HighlightBody(highlight: highlight);
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: MarginaliaColors.primaryDark,
            strokeWidth: 1.5,
          ),
        ),
        error: (e, _) => Center(child: Text(context.l10n.errorPrefix('$e'))),
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
    try {
      return (h.book?.value?.id as int?) ?? -1;
    } catch (_) {}
    try {
      return (h.bookId as int?) ?? -1;
    } catch (_) {}
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
            _BookHeader(
                title: embTitle, author: embAuthor ?? '', accentColor: hlColor)
          else if (bookAsync != null)
            bookAsync.when(
              data: (book) => book != null
                  ? _BookHeader(
                      title: book.title,
                      author: book.author,
                      accentColor: hlColor)
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
                    .slideY(
                        begin: 0.03,
                        end: 0,
                        duration: 700.ms,
                        curve: Curves.easeOut),

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
                      child: Container(
                          height: 0.8, color: MarginaliaColors.ruleFaint),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Condividi come storia — CTA forte e verde (viralità) ────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: () => shareHighlightAsStory(
                      context,
                      text: highlight.content as String,
                      title: embTitle,
                      author: embAuthor,
                    ),
                    icon: const Icon(PhosphorIconsRegular.instagramLogo,
                        size: 20),
                    label: Text(
                      context.l10n.shareAsStory,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: MarginaliaColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
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
                          style: GoogleFonts.manrope(
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
                        label: context.l10n
                            .bookLocationPrefix('${highlight.location}'),
                      ),
                    if ((highlight.addedAt as DateTime?) != null)
                      _MetaItem(
                        icon: Icons.calendar_today_outlined,
                        label:
                            _formatDate(context, highlight.addedAt as DateTime),
                      ),
                    if ((highlight.color as String?) != null)
                      _MetaItem(
                        icon: Icons.circle,
                        label: _colorName(context, highlight.color as String),
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

  String _formatDate(BuildContext context, DateTime date) =>
      DateFormat.yMMMd(Localizations.localeOf(context).languageCode)
          .format(date);

  String _colorName(BuildContext context, String c) => switch (c) {
        'yellow' => context.l10n.colorYellow,
        'blue' => context.l10n.colorBlue,
        'pink' => context.l10n.colorPink,
        'orange' => context.l10n.colorOrange,
        _ => c,
      };

  Color _colorFor(String? c) => switch (c) {
        'yellow' => const Color(0xFFD4A017),
        'blue' => const Color(0xFF4A90BF),
        'pink' => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _ => MarginaliaColors.siennaLight,
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
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.highlightFromLabel,
                style: MarginaliaTextStyles.sectionTitle.copyWith(
                  fontSize: 9,
                  letterSpacing: 2.5,
                  color: MarginaliaColors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Tappable → opens the book's detail (cover, overview, categories),
          // so a reader can jump from a phrase straight to "what's this book?".
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    BookInfoScreen(title: title, author: author),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: MarginaliaTextStyles.bookTitle
                              .copyWith(fontSize: 16),
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
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 2),
                    child: Icon(Icons.chevron_right,
                        size: 20, color: MarginaliaColors.inkFaint),
                  ),
                ],
              ),
            ),
          ),
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

// ─── Share menu ──────────────────────────────────────────────────────────────

/// The two ways to share a highlight from the detail screen.
enum _ShareAction { card, story }

class _ShareMenuRow extends StatelessWidget {
  const _ShareMenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: MarginaliaColors.inkMuted),
        const SizedBox(width: 12),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: MarginaliaColors.ink,
          ),
        ),
      ],
    );
  }
}
