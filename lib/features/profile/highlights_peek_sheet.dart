import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/highlights_provider.dart';

/// A modal "peek" of highlights — the same content you see when you open a book
/// in the library, but as a quick bottom-sheet preview. Used by long-pressing
/// the profile photo (your recent highlights) and a favourite-book cover (that
/// book's highlights). Reads [allHighlightsProvider] and, when [bookTitle] is
/// given, filters to that book — so it works on every platform without an
/// Isar-only per-book query.
class HighlightsPeekSheet extends ConsumerWidget {
  const HighlightsPeekSheet({
    super.key,
    this.bookTitle,
    required this.title,
    this.subtitle,
  });

  /// When non-null, only show highlights from this book; otherwise the most
  /// recent across all books.
  final String? bookTitle;
  final String title;
  final String? subtitle;

  static Future<void> show(
    BuildContext context, {
    String? bookTitle,
    required String title,
    String? subtitle,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HighlightsPeekSheet(
        bookTitle: bookTitle,
        title: title,
        subtitle: subtitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final it = Localizations.localeOf(context).languageCode == 'it';
    final bottom = MediaQuery.of(context).padding.bottom;
    final async = ref.watch(allHighlightsProvider);

    List<Highlight> resolve(List<Highlight> all) {
      var list = all;
      final t = bookTitle?.toLowerCase().trim();
      if (t != null && t.isNotEmpty) {
        list = all
            .where((h) => (h.bookTitle ?? '').toLowerCase().trim() == t)
            .toList();
      }
      return list.take(20).toList();
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: ScriptaColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ScriptaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.ebGaramond(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: ScriptaColors.ink,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!.toUpperCase(),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: ScriptaColors.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: ScriptaColors.ruleFaint),
            Expanded(
              child: async.when(
                data: (all) {
                  final list = resolve(all);
                  if (list.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          it
                              ? 'Nessun highlight da mostrare.'
                              : 'No highlights to show yet.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                              fontSize: 13.5, color: ScriptaColors.inkMuted),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 18),
                    itemBuilder: (_, i) => _PeekCard(h: list[i], index: i),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: ScriptaColors.sienna, strokeWidth: 1.5),
                ),
                error: (_, __) => Center(
                  child: Text(
                    it ? 'Errore nel caricamento.' : 'Failed to load.',
                    style: GoogleFonts.manrope(
                        fontSize: 13.5, color: ScriptaColors.inkMuted),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeekCard extends StatelessWidget {
  const _PeekCard({required this.h, required this.index});
  final Highlight h;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          h.content,
          style: GoogleFonts.ebGaramond(
            fontSize: 16,
            height: 1.6,
            fontStyle: FontStyle.italic,
            color: ScriptaColors.ink,
          ),
        ),
        if ((h.bookTitle ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            h.bookTitle!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: ScriptaColors.inkFaint,
            ),
          ),
        ],
      ],
    );
  }
}
