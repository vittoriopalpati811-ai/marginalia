// ─── Book recommendations section ────────────────────────────────────────────
//
// Shared widget used by LibraryScreen (and optionally MyProfileScreen).
//
// Public surface:
//   BookRecommendation              — data class
//   libraryRecommendationsProvider  — FutureProvider (Edge Function + AI)
//   LibraryRecommendationsSection   — drop-in ConsumerWidget
//
// How it works:
//   1. Group all user highlights by book (title + author).
//   2. Take the 20 most recently active distinct books.
//   3. Call the `recommend-books` Supabase Edge Function:
//        • book title, author, up to 4 highlights each as reading context
//        • full list of existing titles to exclude from suggestions
//        • optional: weather, health context
//   4. Display each recommendation with an AI-written reason.
//   5. Tap a card → book detail sheet with personal notes + Amazon buy link.
//
// Caching:
//   The provider uses keepAlive() for 1 hour. It is intentionally NOT
//   invalidated on pull-to-refresh (see library_screen.dart) — only
//   after a real My Clippings import so AI calls are not wasted.

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/weather_provider.dart';
import '../../core/providers/health_provider.dart';

// Re-export so library_screen can import just this file if needed
export '../../core/providers/auth_provider.dart' show myDisplayNameProvider;

// ─── Amazon Associates referral tag ──────────────────────────────────────────
//
// Register at https://programma-affiliazione.amazon.it/ to get your own tag.
// Replace the value below with your Associates tag (format: yourname-21).
// Every purchase made through this link earns you ~4% commission (~€0.60-0.80
// per book sold at average Italian book prices of €15-20).

const _amazonTag = 'marginaliaapp-21';

// ─── Book recommendation data class ──────────────────────────────────────────

class BookRecommendation {
  const BookRecommendation({
    required this.title,
    required this.author,
    required this.year,
    required this.reason,
  });
  final String title;
  final String author;
  final String year;
  final String reason; // AI-generated personalised explanation
}

// ─── Provider ─────────────────────────────────────────────────────────────────

// NOT autoDispose: we want this cached indefinitely across tab navigation.
// The only way recommendations re-fetch is via ref.invalidate(), which
// library_screen.dart calls exclusively after a real My Clippings import.
final libraryRecommendationsProvider =
    FutureProvider<List<BookRecommendation>>((ref) async {

  // ── 1. Collect highlights grouped by book ──────────────────────────────────

  final Map<String, Map<String, dynamic>> bookMap = {};
  final List<String> orderedBookIds = [];

  if (kIsWeb) {
    final service = ref.read(supabaseServiceProvider);
    if (!service.isAuthenticated) {
      debugPrint('[Recs] not authenticated → empty');
      return [];
    }
    try {
      final data = await service.fetchHighlights();
      debugPrint('[Recs] fetchHighlights → ${data.length} rows');

      for (final h in data) {
        final bookId  = (h['book_id'] as String?)?.trim() ?? '';
        final content = (h['content'] as String?)?.trim() ?? '';
        if (bookId.isEmpty) continue;

        if (!bookMap.containsKey(bookId)) {
          final booksEmbed = h['books'] as Map<String, dynamic>?;
          final title  = (booksEmbed?['title']  as String? ?? '').trim();
          final author = (booksEmbed?['author'] as String? ?? '').trim();
          if (title.isEmpty) continue;

          bookMap[bookId] = {
            'title':      title,
            'author':     author,
            'highlights': <String>[],
          };
          orderedBookIds.add(bookId);
        }

        final highlights = bookMap[bookId]!['highlights'] as List<String>;
        if (highlights.length < 4 && content.isNotEmpty) {
          highlights.add(content);
        }
      }
    } catch (e, st) {
      debugPrint('[Recs] fetchHighlights error: $e\n$st');
      return [];
    }
  } else {
    // Native (Isar): no embedded join — use book ID + title from booksProvider.
    final all   = await ref.read(allHighlightsProvider.future);
    final books = ref.read(booksProvider).value ?? [];
    final bookById = {for (final b in books) b.supabaseId: b};

    for (final h in all) {
      final bookId = h.bookId.toString();
      if (!bookMap.containsKey(bookId)) {
        final book = bookById[bookId];
        if (book == null || book.title.isEmpty) continue;
        bookMap[bookId] = {
          'title':      book.title,
          'author':     book.author,
          'highlights': <String>[],
        };
        orderedBookIds.add(bookId);
      }
      final highlights = bookMap[bookId]!['highlights'] as List<String>;
      if (highlights.length < 4 && h.content.isNotEmpty) {
        highlights.add(h.content);
      }
    }
  }

  debugPrint('[Recs] distinct books: ${orderedBookIds.length}');
  if (orderedBookIds.isEmpty) return [];

  // ── 2. Build request payload ───────────────────────────────────────────────

  final recentIds  = orderedBookIds.take(20).toList();
  final allTitles  = orderedBookIds
      .map((id) => bookMap[id]!['title'] as String)
      .toList();

  final booksPayload = recentIds.map((id) {
    final info = bookMap[id]!;
    return {
      'title':      info['title'] as String,
      'author':     info['author'] as String,
      'highlights': (info['highlights'] as List<String>),
    };
  }).toList();

  debugPrint('[Recs] calling recommend-books with ${booksPayload.length} books');

  // ── 3. Collect optional context (weather + health) ────────────────────────

  final userName   = ref.read(myDisplayNameProvider).asData?.value ?? '';
  final weather    = ref.read(weatherProvider).asData?.value;
  final healthSnap = ref.read(healthSnapshotProvider).asData?.value;

  final contextPayload = <String, dynamic>{
    if (weather != null) ...{
      'weather':     weather.widgetParam,
      'weatherCity': weather.cityName,
      'weatherTemp': weather.temperatureRounded,
    },
    if (healthSnap != null && healthSnap.isAvailable) ...{
      if (healthSnap.stepsToday != null) 'stepsToday': healthSnap.stepsToday,
      if (healthSnap.workoutsThisWeek.isNotEmpty)
        'lastWorkout': healthSnap.workoutsThisWeek.first.typeLabel,
      if (healthSnap.hasCycle && healthSnap.cyclePhase != null)
        'cyclePhase': healthSnap.cyclePhase!.name,
    },
  };

  // ── 4. Invoke Edge Function ────────────────────────────────────────────────

  final service = ref.read(supabaseServiceProvider);
  late final Map<String, dynamic> responseBody;

  try {
    final result = await service.client.functions.invoke(
      'recommend-books',
      body: {
        'books':          booksPayload,
        'existingTitles': allTitles,
        'context':        contextPayload,
        'userName':       userName,
      },
    );

    if (result.data == null) {
      debugPrint('[Recs] Edge Function returned null data');
      return [];
    }

    if (result.data is Map<String, dynamic>) {
      responseBody = result.data as Map<String, dynamic>;
    } else if (result.data is String) {
      responseBody = jsonDecode(result.data as String) as Map<String, dynamic>;
    } else {
      debugPrint('[Recs] unexpected data type: ${result.data.runtimeType}');
      return [];
    }
  } catch (e, st) {
    debugPrint('[Recs] Edge Function error: $e\n$st');
    return [];
  }

  // ── 5. Parse ───────────────────────────────────────────────────────────────

  final rawList = responseBody['recommendations'] as List<dynamic>?;
  if (rawList == null || rawList.isEmpty) {
    debugPrint('[Recs] no recommendations in response');
    return [];
  }

  final recommendations = rawList.map((raw) {
    final r = raw as Map<String, dynamic>;
    return BookRecommendation(
      title:  (r['title']  as String? ?? '').trim(),
      author: (r['author'] as String? ?? '').trim(),
      year:   (r['year']   as String? ?? '').trim(),
      reason: (r['reason'] as String? ?? '').trim(),
    );
  }).where((r) => r.title.isNotEmpty).toList();

  debugPrint('[Recs] received ${recommendations.length} recommendations');
  return recommendations;
});

// ─── Section widget ───────────────────────────────────────────────────────────

class LibraryRecommendationsSection extends ConsumerWidget {
  const LibraryRecommendationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryRecommendationsProvider);

    return async.when(
      loading: () => _RecommendationsSkeleton(),
      error: (e, _) {
        debugPrint('[Recs] UI error: $e');
        return const SizedBox.shrink();
      },
      data: (books) {
        if (books.isEmpty) {
          return _RecommendationsHint(context.l10n.recsEmpty);
        }
        // NOTE: previously rendered _RecommendationsSubtitle here too, but
        // its copy ("Selezionati in base ai tuoi highlight") was visually
        // redundant with _SectionHeader's tagline ("Selezionati da
        // Marginalia, solo per te"), and on certain devices the two lines
        // appeared stacked/duplicated like a render ghost. One tagline is
        // enough — context comes from the section title above it.
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(),
              const SizedBox(height: 16),
              ...books.asMap().entries.map(
                (e) => _RecommendationCard(rec: e.value, index: e.key),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Section header (shared by loaded / empty / skeleton states) ──────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader();

  @override
  Widget build(BuildContext context) {
    // Tagline ("Selezionati da Marginalia, solo per te") removed: the
    // section title "LIBRI CONSIGLIATI" already says everything the user
    // needs, and the italic green sub-line was reading as filler the
    // user kept getting flagged in screenshots.
    return Row(
      children: [
        Text(context.l10n.recsTitle,
            style: MarginaliaTextStyles.sectionTitle),
        const SizedBox(width: 12),
        const Expanded(
          child: Divider(color: MarginaliaColors.ruleFaint, height: 1),
        ),
      ],
    );
  }
}

// ─── Card (tappable) ──────────────────────────────────────────────────────────

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.rec, required this.index});
  final BookRecommendation rec;
  final int index;

  @override
  Widget build(BuildContext context) {
    final meta = [rec.author, rec.year]
        .where((s) => s.isNotEmpty && s != '—')
        .join(' · ');

    return GestureDetector(
      onTap: () => _openSheet(context),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MarginaliaColors.ruleFaint, width: 0.8),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rec.title,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: MarginaliaColors.ink,
                      height: 1.3,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: MarginaliaColors.inkFaint),
              ],
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                meta,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: MarginaliaColors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(height: 0.7, color: MarginaliaColors.ruleFaint),
            const SizedBox(height: 10),
            // Reason is the main body of each card — keep it upright.
            // Italic was reserved for short decorative captions (the green
            // tagline above the section) and felt too heavy as paragraph copy.
            Text(
              rec.reason.isNotEmpty
                  ? rec.reason
                  : context.l10n.recsFallback,
              style: GoogleFonts.ebGaramond(
                fontSize: 14,
                height: 1.6,
                color: rec.reason.isNotEmpty
                    ? MarginaliaColors.ink
                    : MarginaliaColors.inkFaint,
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: (index * 80).ms)
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: 0.04, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }

  void _openSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookDetailSheet(rec: rec),
    );
  }
}

// ─── Book detail bottom sheet ──────────────────────────────────────────────────

class _BookDetailSheet extends StatefulWidget {
  const _BookDetailSheet({required this.rec});
  final BookRecommendation rec;

  @override
  State<_BookDetailSheet> createState() => _BookDetailSheetState();
}

class _BookDetailSheetState extends State<_BookDetailSheet> {
  late final TextEditingController _notesCtrl;
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController();
    _loadNote();
  }

  @override
  void dispose() {
    // Auto-save when sheet closes (if there are unsaved notes)
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNote() async {
    // Find a SupabaseService from the nearest ProviderScope ancestor.
    // We can't use ref here (StatefulWidget), so we use a direct Supabase call.
    try {
      // Read the provider via a ProviderContainer if available, else skip.
      // The simplest approach: access Supabase directly via the client singleton.
      final supabase = ProviderScope.containerOf(context, listen: false);
      // ignore: invalid_use_of_internal_member
      final service = supabase.read(supabaseServiceProvider);
      final note = await service.fetchBookNote(
        title: widget.rec.title,
        author: widget.rec.author,
      );
      if (mounted) {
        _notesCtrl.text = note ?? '';
        setState(() => _loaded = true);
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _saveNote() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final supabase = ProviderScope.containerOf(context, listen: false);
      // ignore: invalid_use_of_internal_member
      final service = supabase.read(supabaseServiceProvider);
      await service.saveBookNote(
        title:  widget.rec.title,
        author: widget.rec.author,
        notes:  _notesCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.bookNotesSaved),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      /* silent */
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openAmazon() async {
    final query = Uri.encodeQueryComponent('${widget.rec.title} ${widget.rec.author}');
    final url   = Uri.parse(
        'https://www.amazon.it/s?k=$query&tag=$_amazonTag');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final rec    = widget.rec;
    final meta   = [rec.author, rec.year]
        .where((s) => s.isNotEmpty && s != '—')
        .join(' · ');
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, bottom + 32),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ───────────────────────────────────────────────
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: MarginaliaColors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Book title & meta ──────────────────────────────────────────
            Text(
              rec.title,
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: MarginaliaColors.ink,
                height: 1.2,
                letterSpacing: -0.5,
              ),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                meta,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: MarginaliaColors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // ── AI reason ─────────────────────────────────────────────────
            if (rec.reason.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MarginaliaColors.siennaFaint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  rec.reason,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 15,
                    height: 1.65,
                    color: MarginaliaColors.sienna,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            const SizedBox(height: 24),

            // ── My notes ──────────────────────────────────────────────────
            Row(
              children: [
                Text(context.l10n.bookMyNotes,
                    style: MarginaliaTextStyles.sectionTitle),
                const SizedBox(width: 12),
                const Expanded(
                    child:
                        Divider(color: MarginaliaColors.ruleFaint, height: 1)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              minLines: 3,
              maxLines: 8,
              enabled: _loaded,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.6,
                color: MarginaliaColors.ink,
              ),
              decoration: InputDecoration(
                hintText: context.l10n.bookNotesHint,
                hintStyle: GoogleFonts.manrope(
                  fontSize: 14,
                  color: MarginaliaColors.inkFaint,
                ),
                filled: true,
                fillColor: MarginaliaColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: MarginaliaColors.rule, width: 0.8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: MarginaliaColors.rule, width: 0.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: MarginaliaColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _saveNote,
                style: FilledButton.styleFrom(
                  backgroundColor: MarginaliaColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        context.l10n.save,
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Amazon buy link ────────────────────────────────────────────
            Row(
              children: [
                Text(context.l10n.bookBuyOnAmazon.toUpperCase(),
                    style: MarginaliaTextStyles.sectionTitle),
                const SizedBox(width: 12),
                const Expanded(
                    child:
                        Divider(color: MarginaliaColors.ruleFaint, height: 1)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openAmazon,
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: Text(context.l10n.bookBuyOnAmazon),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF232F3E), // Amazon dark
                  side: const BorderSide(color: Color(0xFF232F3E), width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.bookAmazonEarningsHint,
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: MarginaliaColors.inkFaint,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Hint widget (empty state) ────────────────────────────────────────────────

class _RecommendationsHint extends StatelessWidget {
  const _RecommendationsHint(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(),
          const SizedBox(height: 10),
          Text(
            message,
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: MarginaliaColors.inkFaint,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Skeleton loader ──────────────────────────────────────────────────────────

class _RecommendationsSkeleton extends StatelessWidget {
  const _RecommendationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(),
          const SizedBox(height: 8),
          Text(
            context.l10n.recsLoading,
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: MarginaliaColors.inkFaint,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < 3; i++)
            Container(
              height: 120,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: MarginaliaColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
        ],
      ),
    );
  }
}
