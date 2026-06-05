// ─── Recensioni (Reviews) tab ─────────────────────────────────────────────────
//
// Social book ratings. A review is a 1–5 star rating + a free-text "perché"
// for a book the reader has highlights of (their imported MyClippings books),
// with an optional attached highlight.
//
// Surface:
//   ReviewsTab           — the tab body (list + empty state + compose button)
//   openReviewComposer   — shows the compose sheet (also reused by the header +)
//
// Data:
//   • myReviewsProvider          (reviews_service.dart) — the user's reviews
//   • _composerBooksProvider     — the user's library (SupabaseService.fetchMyBooks)
//   • _bookHighlightsProvider    — highlights for a chosen book (fetchHighlights)
//
// Aesthetics: warm whites, EB Garamond serif for the review body + attached
// highlight, sage (MarginaliaColors.primary/primaryDark) accents, soft cards —
// matching the rest of the profile screen and recommendations_section.dart.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/reviews_service.dart';
import '../social/report_sheet.dart';
import '../library/book_cover.dart';

// ─── Providers used only by the composer ──────────────────────────────────────

/// The user's library (id/title/author) — reuses SupabaseService.fetchMyBooks,
/// the exact source the profile's own `_myBooksProvider` and the favourite-books
/// picker use, so the composer lists the same books.
final _composerBooksProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated || svc.userId == null) return [];
  try {
    return await svc.fetchMyBooks();
  } catch (_) {
    return [];
  }
});

/// Highlights for a chosen book, keyed by the book's Supabase UUID. Loaded only
/// after a book is picked, so the user can attach one of that book's highlights.
final _bookHighlightsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, bookId) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated || bookId.isEmpty) return [];
  try {
    return await svc.fetchHighlights(bookId: bookId);
  } catch (_) {
    return [];
  }
});

// ─── Tab body ─────────────────────────────────────────────────────────────────

class ReviewsTab extends ConsumerWidget {
  const ReviewsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myReviewsProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: CircularProgressIndicator(
              color: MarginaliaColors.sienna, strokeWidth: 1.5),
        ),
      ),
      error: (_, __) => _ReviewsEmpty(
        onCompose: () => openReviewComposer(context, ref),
      ),
      data: (reviews) {
        if (reviews.isEmpty) {
          return _ReviewsEmpty(
            onCompose: () => openReviewComposer(context, ref),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: title + "Scrivi recensione"
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                children: [
                  Text(context.l10n.reviewsSectionTitle,
                      style: MarginaliaTextStyles.sectionTitle),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Divider(color: MarginaliaColors.ruleFaint)),
                  const SizedBox(width: 8),
                  _ComposeChip(onTap: () => openReviewComposer(context, ref)),
                ],
              ),
            ),
            ...reviews.asMap().entries.map(
                  (e) => _ReviewCard(review: e.value, index: e.key),
                ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ─── Compose chip (small pill, matches the "Scrivi" pill on the Post tab) ─────

class _ComposeChip extends StatelessWidget {
  const _ComposeChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: MarginaliaColors.primaryFaint,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: MarginaliaColors.primary.withAlpha(50),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 12, color: MarginaliaColors.primaryDark),
            const SizedBox(width: 3),
            Text(
              context.l10n.reviewsWriteCta,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: MarginaliaColors.primaryDark,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Star row (display) ───────────────────────────────────────────────────────

class _Stars extends StatelessWidget {
  const _Stars({required this.rating});
  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(
              i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 16,
              color: i <= rating
                  ? MarginaliaColors.primaryDark
                  : MarginaliaColors.inkFaint,
            ),
          ),
      ],
    );
  }
}

// ─── Single review card ───────────────────────────────────────────────────────

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.review, required this.index});
  final Review review;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.read(supabaseServiceProvider).userId;
    final isOwner = myId != null && myId == review.userId;
    final card = Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: MarginaliaDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover + title/author + stars ──────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 46,
                  height: 64,
                  child: BookEditorialCover(
                    title: review.bookTitle,
                    author: review.bookAuthor,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.bookTitle,
                      style: GoogleFonts.manrope(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: MarginaliaColors.ink,
                        height: 1.25,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (review.bookAuthor.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        review.bookAuthor.toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: MarginaliaColors.inkMuted,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    _Stars(rating: review.rating),
                  ],
                ),
              ),
              // Overflow menu — delete own review, or report someone else's.
              _ReviewMenu(
                isOwner: isOwner,
                onDelete: () async {
                  await ref
                      .read(reviewsServiceProvider)
                      .deleteReview(review.id);
                  ref.invalidate(myReviewsProvider);
                },
                onReport: () => showReportSheet(
                  context,
                  ref,
                  contentType: 'review',
                  contentId: review.id,
                  reportedUserId: review.userId,
                ),
              ),
            ],
          ),

          // ── The "perché" body ─────────────────────────────────────────────
          if (review.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              review.body,
              style: GoogleFonts.ebGaramond(
                fontSize: 15.5,
                height: 1.6,
                color: MarginaliaColors.ink,
              ),
            ),
          ],

          // ── Attached highlight ────────────────────────────────────────────
          if (review.highlightText != null &&
              review.highlightText!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: MarginaliaColors.primaryFaint,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                      color: MarginaliaColors.primaryDark.withAlpha(140),
                      width: 3),
                ),
              ),
              child: Text(
                review.highlightText!,
                style: GoogleFonts.ebGaramond(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                  color: MarginaliaColors.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return card
        .animate(delay: (index * 50).ms)
        .fadeIn(duration: 320.ms, curve: Curves.easeOut)
        .slideY(begin: 0.04, end: 0, duration: 320.ms);
  }
}

class _ReviewMenu extends StatelessWidget {
  const _ReviewMenu({
    required this.isOwner,
    required this.onDelete,
    required this.onReport,
  });
  final bool isOwner;
  final Future<void> Function() onDelete;
  final Future<void> Function() onReport;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz,
          size: 18, color: MarginaliaColors.inkFaint),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      color: MarginaliaColors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) {
        if (v == 'delete') onDelete();
        if (v == 'report') onReport();
      },
      itemBuilder: (_) => isOwner
          ? [
              PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline,
                        size: 17, color: Color(0xFFB3503F)),
                    const SizedBox(width: 8),
                    Text(context.l10n.delete,
                        style: const TextStyle(
                            fontSize: 13.5, color: MarginaliaColors.ink)),
                  ],
                ),
              ),
            ]
          : [
              PopupMenuItem<String>(
                value: 'report',
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined,
                        size: 17, color: MarginaliaColors.inkMuted),
                    const SizedBox(width: 8),
                    Text(context.l10n.reportAction,
                        style: const TextStyle(
                            fontSize: 13.5, color: MarginaliaColors.ink)),
                  ],
                ),
              ),
            ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _ReviewsEmpty extends StatelessWidget {
  const _ReviewsEmpty({required this.onCompose});
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 40),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: MarginaliaColors.primaryFaint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.rate_review_outlined,
                size: 28, color: MarginaliaColors.primaryDark),
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.reviewsEmptyTitle,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: MarginaliaColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.reviewsEmptyBody,
            textAlign: TextAlign.center,
            style: GoogleFonts.ebGaramond(
              fontSize: 15,
              height: 1.6,
              color: MarginaliaColors.inkMuted,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onCompose,
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              context.l10n.reviewsWriteCta,
              style: GoogleFonts.manrope(
                  fontSize: 14, fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: MarginaliaColors.primary,
              foregroundColor: const Color(0xFF1B1F1B),
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 320.ms);
  }
}

// ─── Composer entry point ─────────────────────────────────────────────────────

/// Opens the "Scrivi recensione" sheet. On a successful save it invalidates
/// [myReviewsProvider] so the list refreshes.
void openReviewComposer(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Push on the ROOT navigator so the sheet renders ABOVE the shell's
    // floating glass navbar. The shell (`_ScaffoldWithNav` in app.dart) does
    // NOT use Scaffold.bottomNavigationBar — it paints the navbar as the LAST
    // child of the body Stack (Positioned bottom:0), so anything opened on the
    // shell navigator lands UNDER that opaque bar. The bar would then intercept
    // taps meant for the lower part of the "Perché" field (founder: "non si può
    // scrivere") and cover the Publish button (founder: "finisce sotto la
    // navbar"). Rooting the sheet lifts the whole composer over the navbar.
    useRootNavigator: true,
    builder: (_) => _ReviewComposerSheet(
      onSaved: () => ref.invalidate(myReviewsProvider),
    ),
  );
}

// ─── Composer sheet ───────────────────────────────────────────────────────────

class _ReviewComposerSheet extends ConsumerStatefulWidget {
  const _ReviewComposerSheet({required this.onSaved});
  final VoidCallback onSaved;

  @override
  ConsumerState<_ReviewComposerSheet> createState() =>
      _ReviewComposerSheetState();
}

class _ReviewComposerSheetState extends ConsumerState<_ReviewComposerSheet> {
  final _bodyCtrl = TextEditingController();

  // Selected book.
  String? _bookId;
  String _bookTitle = '';
  String _bookAuthor = '';

  int _rating = 0;
  String? _attachedHighlight;
  bool _saving = false;

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _bookTitle.isNotEmpty && _rating > 0 && !_saving;

  Future<void> _pickBook() async {
    final books = await ref.read(_composerBooksProvider.future);
    if (!mounted) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Same reason as openReviewComposer: stay above the shell's floating
      // navbar so the picker list is fully tappable.
      useRootNavigator: true,
      builder: (_) => _BookPickerSheet(books: books),
    );
    if (picked != null) {
      setState(() {
        _bookId = picked['id'] as String? ?? '';
        _bookTitle = picked['title'] as String? ?? '';
        _bookAuthor = picked['author'] as String? ?? '';
        // Reset any highlight attached from a previously-selected book.
        _attachedHighlight = null;
      });
    }
  }

  Future<void> _pickHighlight() async {
    final id = _bookId;
    if (id == null || id.isEmpty) return;
    final highlights = await ref.read(_bookHighlightsProvider(id).future);
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Same reason as openReviewComposer: stay above the shell's floating
      // navbar so the highlight list is fully tappable.
      useRootNavigator: true,
      builder: (_) => _HighlightPickerSheet(highlights: highlights),
    );
    if (picked != null) {
      setState(() => _attachedHighlight = picked.isEmpty ? null : picked);
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      await ref.read(reviewsServiceProvider).addReview(
            bookTitle: _bookTitle,
            bookAuthor: _bookAuthor,
            rating: _rating,
            body: _bodyCtrl.text,
            highlightText: _attachedHighlight,
          );
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.reviewsSaveError),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Belt-and-suspenders bottom inset for the Publish button so it is NEVER
    // hidden under the keyboard, the iPhone home indicator, or the shell's
    // floating glass navbar. `viewInsets.bottom` is the keyboard height (0 when
    // closed); `padding.bottom` is the home-indicator safe area. We take the
    // larger of the two (the keyboard already overlaps the home indicator, so
    // adding them would double-count) and keep a floor of 24 so that even when
    // both are 0 the Publish button still floats clear of the bottom edge.
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final safeInset = MediaQuery.of(context).padding.bottom;
    final bottom = keyboardInset > safeInset ? keyboardInset : safeInset;
    final maxH = MediaQuery.of(context).size.height * 0.9;
    final hasBook = _bookTitle.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: const BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ────────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: MarginaliaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Title ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                children: [
                  Text(
                    context.l10n.reviewsSheetTitle,
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: MarginaliaColors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.close_rounded,
                        size: 22, color: MarginaliaColors.inkMuted),
                  ),
                ],
              ),
            ),

            const Divider(color: MarginaliaColors.ruleFaint, height: 1),

            // ── Scrollable form ───────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── (a) Book picker ─────────────────────────────────
                    _FieldLabel(context.l10n.reviewsFieldBook),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _saving ? null : _pickBook,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: MarginaliaColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: MarginaliaColors.rule, width: 0.8),
                        ),
                        child: Row(
                          children: [
                            if (hasBook) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: SizedBox(
                                  width: 34,
                                  height: 48,
                                  child: BookEditorialCover(
                                    title: _bookTitle,
                                    author: _bookAuthor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _bookTitle,
                                      style: GoogleFonts.manrope(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: MarginaliaColors.ink,
                                        height: 1.25,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (_bookAuthor.isNotEmpty)
                                      Text(
                                        _bookAuthor.toUpperCase(),
                                        style: GoogleFonts.manrope(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: MarginaliaColors.inkMuted,
                                          letterSpacing: 0.4,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.swap_horiz_rounded,
                                  size: 18, color: MarginaliaColors.inkMuted),
                            ] else ...[
                              const Icon(Icons.menu_book_outlined,
                                  size: 18, color: MarginaliaColors.primaryDark),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  context.l10n.reviewsPickBook,
                                  style: GoogleFonts.manrope(
                                    fontSize: 13.5,
                                    color: MarginaliaColors.inkMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  size: 20, color: MarginaliaColors.inkFaint),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── (b) Star rating ─────────────────────────────────
                    _FieldLabel(context.l10n.reviewsFieldRating),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (int i = 1; i <= 5; i++)
                          GestureDetector(
                            onTap: _saving
                                ? null
                                : () => setState(() => _rating = i),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                i <= _rating
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 34,
                                color: i <= _rating
                                    ? MarginaliaColors.primaryDark
                                    : MarginaliaColors.inkFaint,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── (c) "Perché" multiline ──────────────────────────
                    _FieldLabel(context.l10n.reviewsFieldReason),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bodyCtrl,
                      minLines: 3,
                      maxLines: 8,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.sentences,
                      style: GoogleFonts.ebGaramond(
                        fontSize: 16,
                        height: 1.6,
                        color: MarginaliaColors.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: context.l10n.reviewsHint,
                        hintStyle: GoogleFonts.ebGaramond(
                          fontSize: 16,
                          color: MarginaliaColors.inkFaint,
                        ),
                        filled: true,
                        fillColor: MarginaliaColors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: MarginaliaColors.rule, width: 0.8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: MarginaliaColors.rule, width: 0.8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: MarginaliaColors.primaryDark, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── (d) Optional: attach a highlight ────────────────
                    // Only meaningful once a book is chosen — that's the book
                    // whose highlights we load (highlightsProvider equivalent:
                    // SupabaseService.fetchHighlights(bookId:)).
                    if (hasBook) ...[
                      _FieldLabel(context.l10n.reviewsFieldHighlightOptional),
                      const SizedBox(height: 8),
                      if (_attachedHighlight == null)
                        GestureDetector(
                          onTap: _saving ? null : _pickHighlight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: MarginaliaColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: MarginaliaColors.rule, width: 0.8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.format_quote_rounded,
                                    size: 18,
                                    color: MarginaliaColors.primaryDark),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    context.l10n.reviewsAttachHighlight,
                                    style: GoogleFonts.manrope(
                                      fontSize: 13.5,
                                      color: MarginaliaColors.inkMuted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded,
                                    size: 20, color: MarginaliaColors.inkFaint),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                          decoration: BoxDecoration(
                            color: MarginaliaColors.primaryFaint,
                            borderRadius: BorderRadius.circular(12),
                            border: Border(
                              left: BorderSide(
                                  color: MarginaliaColors.primaryDark
                                      .withAlpha(140),
                                  width: 3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  _attachedHighlight!,
                                  style: GoogleFonts.ebGaramond(
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                    height: 1.55,
                                    color: MarginaliaColors.ink,
                                  ),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: _saving
                                    ? null
                                    : () => setState(
                                        () => _attachedHighlight = null),
                                child: const Icon(Icons.close_rounded,
                                    size: 18,
                                    color: MarginaliaColors.inkMuted),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(color: MarginaliaColors.ruleFaint, height: 1),

            // ── Save button ───────────────────────────────────────────────
            // `bottom` already encodes max(keyboard, home-indicator); the +16
            // floor guarantees clearance from the bottom edge / floating navbar
            // even when both are 0 (founder: Publish button under the navbar).
            Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, bottom + 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: MarginaliaColors.primary,
                    foregroundColor: const Color(0xFF1B1F1B),
                    disabledBackgroundColor: MarginaliaColors.surfaceElevated,
                    disabledForegroundColor: MarginaliaColors.inkFaint,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Color(0xFF1B1F1B)),
                        )
                      : Text(
                          context.l10n.reviewsPublish,
                          style: GoogleFonts.manrope(
                              fontSize: 14, fontWeight: FontWeight.w700),
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: MarginaliaColors.inkFaint,
          letterSpacing: 0.8,
        ),
      );
}

// ─── Book picker sheet ────────────────────────────────────────────────────────

class _BookPickerSheet extends StatelessWidget {
  const _BookPickerSheet({required this.books});
  final List<Map<String, dynamic>> books;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.8;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: const BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: MarginaliaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.reviewsPickerTitle,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: MarginaliaColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
            const Divider(color: MarginaliaColors.ruleFaint, height: 1),
            Flexible(
              child: books.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Text(
                        context.l10n.reviewsPickerEmpty,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.ebGaramond(
                          fontSize: 15,
                          height: 1.6,
                          color: MarginaliaColors.inkMuted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(0, 6, 0, bottom + 12),
                      itemCount: books.length,
                      itemBuilder: (_, i) {
                        final book = books[i];
                        final title = book['title'] as String? ?? '';
                        final author = book['author'] as String? ?? '';
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(book),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 9),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: SizedBox(
                                    width: 36,
                                    height: 50,
                                    child: BookEditorialCover(
                                      title: title,
                                      author: author,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: GoogleFonts.manrope(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: MarginaliaColors.ink,
                                          height: 1.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (author.isNotEmpty)
                                        Text(
                                          author.toUpperCase(),
                                          style: GoogleFonts.manrope(
                                            fontSize: 9,
                                            letterSpacing: 0.4,
                                            fontWeight: FontWeight.w500,
                                            color: MarginaliaColors.inkMuted,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded,
                                    size: 18,
                                    color: MarginaliaColors.inkFaint),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Highlight picker sheet ───────────────────────────────────────────────────

class _HighlightPickerSheet extends StatelessWidget {
  const _HighlightPickerSheet({required this.highlights});
  final List<Map<String, dynamic>> highlights;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.8;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: const BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: MarginaliaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.reviewsHighlightPickerTitle,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: MarginaliaColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
            const Divider(color: MarginaliaColors.ruleFaint, height: 1),
            Flexible(
              child: highlights.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Text(
                        context.l10n.reviewsNoHighlights,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.ebGaramond(
                          fontSize: 15,
                          height: 1.6,
                          color: MarginaliaColors.inkMuted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 12),
                      itemCount: highlights.length,
                      itemBuilder: (_, i) {
                        final content =
                            highlights[i]['content'] as String? ?? '';
                        if (content.trim().isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return GestureDetector(
                          onTap: () => Navigator.of(context).pop(content),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            decoration: BoxDecoration(
                              color: MarginaliaColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: MarginaliaColors.ruleFaint,
                                  width: 0.8),
                            ),
                            child: Text(
                              content,
                              style: GoogleFonts.ebGaramond(
                                fontSize: 14.5,
                                fontStyle: FontStyle.italic,
                                height: 1.6,
                                color: MarginaliaColors.ink,
                              ),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
