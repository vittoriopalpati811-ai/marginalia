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
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/weather_provider.dart';
import '../../core/providers/health_provider.dart';
import '../../core/providers/locale_provider.dart';
import '../../core/services/recs_cache.dart';

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

/// Why the recommendation list is empty (when it is). Used to render an
/// actionable empty-state copy ("come back tomorrow" vs "import your
/// highlights" vs "service unavailable") instead of one generic line that
/// confuses every distinct failure into the same word soup.
enum RecsEmptyReason {
  ok,             // not empty — list has data
  noBooks,        // user has no highlights yet
  notAuth,        // not signed in
  rateLimit,      // AI quota exhausted, retry later
  aiError,        // AI errored (malformed JSON, transient)
  aiEmpty,        // AI returned no picks (shouldn't happen, but defensible)
  network,        // couldn't reach the edge function at all
}

/// Result wrapper so the UI can branch on the reason.
class RecsResult {
  const RecsResult({required this.list, required this.reason});
  final List<BookRecommendation> list;
  final RecsEmptyReason reason;

  bool get isEmpty => list.isEmpty;
}

RecsEmptyReason _parseReason(String? raw) {
  switch (raw) {
    case 'ok':             return RecsEmptyReason.ok;
    case 'no_books':       return RecsEmptyReason.noBooks;
    case 'rate_limit':     return RecsEmptyReason.rateLimit;
    case 'ai_error':       return RecsEmptyReason.aiError;
    case 'ai_empty':       return RecsEmptyReason.aiEmpty;
    case 'ai_unconfigured':return RecsEmptyReason.aiError;
    default:               return RecsEmptyReason.aiError;
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
//
// Watches `currentUserProvider` (not the static `supabaseServiceProvider`)
// so the FutureProvider re-runs when auth restoration completes after a
// cold start. Same fix we applied to the stats screen — without it, the
// recs section would cache the "not authenticated" result before Supabase
// finished restoring the session, and never re-fetch.
//
// NOT autoDispose: we want this cached indefinitely across tab navigation.
// The only way recommendations re-fetch is via ref.invalidate(), which
// library_screen.dart calls exclusively after a real My Clippings import,
// or via the explicit "Riprova" button in the rate-limited empty state.

final libraryRecommendationsProvider =
    FutureProvider<RecsResult>((ref) async {
  // Re-emit when auth restoration completes.
  final user = ref.watch(currentUserProvider);
  if (user == null && kIsWeb) {
    debugPrint('[Recs] not authenticated → empty');
    return const RecsResult(list: [], reason: RecsEmptyReason.notAuth);
  }

  // ── 1. Sample a few highlights from EVERY book in the library ──────────────
  //
  // User direction: "mettine un numero di highlights per libro in modo da
  // considerare tutti i libri per un massimo di numero ragionevole e
  // coerente di richieste."
  //
  // Why this beats "the 100 most-recent highlights": a 100-highlight cap
  // skewed the model toward whatever 3-4 books the user was actively
  // reading this week — anything older was invisible. The opposite is
  // better: take a small (3-highlight) sample from EVERY book, so the AI
  // gets a panoramic picture of the user's reading life, not a snapshot
  // of the last fortnight.
  //
  // Caps:
  //   • Per book: 3 highlights — enough signal for the model to grasp
  //     a book's voice without bloating the prompt.
  //   • Total books: 40 — bounded so the request stays under llama-3.1-
  //     8b-instant's 6 K tokens-per-minute ceiling (~3.5 K tokens at the
  //     upper end of this budget). For libraries larger than 40 books we
  //     take the 40 with the most-recent highlight (i.e. the books the
  //     user has touched most recently), which still gives broad
  //     coverage of the active reading life.
  //
  // Both backends already return highlights sorted by added_at DESC, so
  // we just iterate that stream. The first time we see a book id we
  // record it; every subsequent highlight from that book appends until
  // the per-book cap. New books beyond the totalBookCap are skipped.

  const perBookCap   = 3;
  const totalBookCap = 40;

  final Map<String, Map<String, dynamic>> bookMap = {};
  final List<String> orderedBookIds = [];

  void ingest(String bookId, String title, String author, String content) {
    if (bookId.isEmpty || content.isEmpty) return;
    if (!bookMap.containsKey(bookId)) {
      if (bookMap.length >= totalBookCap) return; // library bigger than cap
      if (title.isEmpty) return;
      bookMap[bookId] = {
        'title':      title,
        'author':     author,
        'highlights': <String>[],
      };
      orderedBookIds.add(bookId);
    }
    final hs = bookMap[bookId]!['highlights'] as List<String>;
    if (hs.length < perBookCap) hs.add(content);
  }

  if (kIsWeb) {
    final service = ref.read(supabaseServiceProvider);
    try {
      final data = await service.fetchHighlights();
      debugPrint('[Recs] fetchHighlights → ${data.length} rows');
      for (final h in data) {
        final booksEmbed = h['books'] as Map<String, dynamic>?;
        ingest(
          (h['book_id'] as String?)?.trim() ?? '',
          (booksEmbed?['title']  as String? ?? '').trim(),
          (booksEmbed?['author'] as String? ?? '').trim(),
          (h['content'] as String?)?.trim() ?? '',
        );
      }
    } catch (e, st) {
      debugPrint('[Recs] fetchHighlights error: $e\n$st');
      return const RecsResult(list: [], reason: RecsEmptyReason.network);
    }
  } else {
    // Native (Isar): allHighlightsProvider already sorts by addedAt DESC.
    final all   = await ref.read(allHighlightsProvider.future);
    final books = ref.read(booksProvider).value ?? [];
    // Key by the Isar local id — Highlight.bookId resolves to book.value.id
    // (the local int), NOT the Supabase UUID. Keying this map by supabaseId
    // meant every lookup missed, so the native path always reported "no
    // books" and AI recommendations never appeared on iOS.
    final bookById = {for (final b in books) b.id.toString(): b};
    for (final h in all) {
      final book = bookById[h.bookId.toString()];
      if (book == null) continue;
      ingest(
        h.bookId.toString(),
        book.title,
        book.author,
        h.content,
      );
    }
  }

  final totalHighlights = bookMap.values.fold<int>(
      0, (a, b) => a + (b['highlights'] as List).length);
  debugPrint('[Recs] sampled ${orderedBookIds.length} books, '
      '$totalHighlights highlights total');
  if (orderedBookIds.isEmpty) {
    return const RecsResult(list: [], reason: RecsEmptyReason.noBooks);
  }

  // ── Daily cache ────────────────────────────────────────────────────────────
  //
  // Skip the slow, Groq-quota-limited AI call when we already generated
  // recommendations TODAY for this SAME library. The signature folds in the
  // book + highlight counts, so an import (which changes them) busts the cache
  // automatically; it also rolls over at midnight. This is what keeps the free
  // Groq tier from being burned by repeated cold starts. (No-op on web.)
  final cacheSig =
      '${orderedBookIds.length}:$totalHighlights:${ref.read(localeProvider).languageCode}';
  final cachedRecs = await RecsCache.read(cacheSig);
  if (cachedRecs != null) {
    debugPrint('[Recs] cache hit ($cacheSig) — skipping AI call');
    final list = cachedRecs
        .map((r) => BookRecommendation(
              title: (r['title'] as String? ?? '').trim(),
              author: (r['author'] as String? ?? '').trim(),
              year: (r['year'] as String? ?? '').trim(),
              reason: (r['reason'] as String? ?? '').trim(),
            ))
        .where((r) => r.title.isNotEmpty)
        .toList();
    if (list.isNotEmpty) {
      return RecsResult(list: list, reason: RecsEmptyReason.ok);
    }
  }

  // ── 2. Build request payload ───────────────────────────────────────────────

  final allTitles  = orderedBookIds
      .map((id) => bookMap[id]!['title'] as String)
      .toList();

  // Send every sampled book — the server applies its own caps as safety.
  final booksPayload = orderedBookIds.map((id) {
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
        // Output language for the AI-written reasons (US rollout). The
        // recommend-books function switches its prompt/reason language on this.
        'lang':           ref.read(localeProvider).languageCode,
      },
    );

    if (result.data == null) {
      debugPrint('[Recs] Edge Function returned null data');
      return const RecsResult(list: [], reason: RecsEmptyReason.network);
    }

    if (result.data is Map<String, dynamic>) {
      responseBody = result.data as Map<String, dynamic>;
    } else if (result.data is String) {
      responseBody = jsonDecode(result.data as String) as Map<String, dynamic>;
    } else {
      debugPrint('[Recs] unexpected data type: ${result.data.runtimeType}');
      return const RecsResult(list: [], reason: RecsEmptyReason.aiError);
    }
  } catch (e, st) {
    debugPrint('[Recs] Edge Function error: $e\n$st');
    return const RecsResult(list: [], reason: RecsEmptyReason.network);
  }

  // ── 5. Parse ───────────────────────────────────────────────────────────────

  final reason  = _parseReason(responseBody['reason'] as String?);
  final rawList = responseBody['recommendations'] as List<dynamic>?;

  if (rawList == null || rawList.isEmpty) {
    debugPrint('[Recs] empty list, reason=$reason');
    return RecsResult(
      list: const [],
      // If the server forgot to set reason but the list is empty, default
      // to aiEmpty so the user gets a generic "no picks right now" copy.
      reason: reason == RecsEmptyReason.ok ? RecsEmptyReason.aiEmpty : reason,
    );
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

  // Cache this successful set for the rest of today (only successes are cached,
  // so a rate-limited day can still recover on the next attempt).
  if (recommendations.isNotEmpty) {
    await RecsCache.write(
      cacheSig,
      recommendations
          .map((r) => {
                'title': r.title,
                'author': r.author,
                'year': r.year,
                'reason': r.reason,
              })
          .toList(),
    );
  }

  return RecsResult(list: recommendations, reason: RecsEmptyReason.ok);
});

// ─── Section widget ───────────────────────────────────────────────────────────

class LibraryRecommendationsSection extends ConsumerWidget {
  const LibraryRecommendationsSection({super.key});

  /// Maps an empty reason to user-facing copy. The previous version
  /// collapsed every failure into "Importa i tuoi highlight Kindle…" which
  /// was actively misleading when (a) the user already had highlights and
  /// (b) the AI was rate-limited or down. Each reason now gets the line
  /// that matches reality.
  String _copyFor(BuildContext context, RecsEmptyReason reason) {
    switch (reason) {
      case RecsEmptyReason.notAuth:
        return context.l10n.recsNotAuth;
      case RecsEmptyReason.noBooks:
        return context.l10n.recsEmpty;
      case RecsEmptyReason.rateLimit:
        return context.l10n.recsRateLimit;
      case RecsEmptyReason.aiEmpty:
        return context.l10n.recsAiEmpty;
      case RecsEmptyReason.aiError:
        return context.l10n.recsAiError;
      case RecsEmptyReason.network:
        return context.l10n.recsNetwork;
      case RecsEmptyReason.ok:
        return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryRecommendationsProvider);

    return async.when(
      loading: () => _RecommendationsSkeleton(),
      error: (e, _) {
        debugPrint('[Recs] UI error: $e');
        // Surface the error instead of pretending nothing happened.
        return _RecommendationsHint(
          context.l10n.recsAiError,
          onRetry: () => ref.invalidate(libraryRecommendationsProvider),
        );
      },
      data: (result) {
        if (result.isEmpty) {
          // "noBooks" is the only empty state without a retry button — the
          // user needs to import, not retry. Every other empty reason gets
          // a Riprova affordance.
          final canRetry = result.reason != RecsEmptyReason.noBooks &&
              result.reason != RecsEmptyReason.notAuth;
          return _RecommendationsHint(
            _copyFor(context, result.reason),
            onRetry: canRetry
                ? () => ref.invalidate(libraryRecommendationsProvider)
                : null,
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(),
              const SizedBox(height: 16),
              ...result.list.asMap().entries.map(
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
  const _RecommendationsHint(this.message, {this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary isolates this widget's paint layer from siblings.
    // Without it, the html web renderer was leaving a diagonal cascade of
    // paint residue from the slide-X animations on adjacent cards
    // (each ghost line getting progressively fainter + horizontally
    // offset). The "ho letto 40 libri" empty-state copy was the most
    // visible victim — its trailing wrapped line stacked 6-7 times.
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(),
            const SizedBox(height: 10),
            Text(
              message,
              softWrap: true,
              overflow: TextOverflow.visible,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: MarginaliaColors.inkFaint,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              // Quiet text button — matches the editorial register of the
              // empty-state copy (italic Garamond), not a full primary CTA.
              // The user is being invited to retry, not pushed.
              GestureDetector(
                onTap: onRetry,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.refresh_rounded,
                      size: 14,
                      color: MarginaliaColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.retry,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MarginaliaColors.primary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
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
