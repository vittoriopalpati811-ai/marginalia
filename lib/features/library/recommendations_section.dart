// ─── Book recommendations section ────────────────────────────────────────────
//
// Shared widget used by both LibraryScreen and MyProfileScreen.
//
// Public surface:
//   BookRecommendation              — data class
//   libraryRecommendationsProvider  — FutureProvider (Edge Function + Claude AI)
//   LibraryRecommendationsSection   — drop-in ConsumerWidget
//
// How it works:
//   1. Group all user highlights by book (title + author from embedded join).
//   2. Take the 20 most recently active distinct books.
//   3. Send to the `recommend-books` Supabase Edge Function:
//        • book title, author, up to 4 highlights each as reading context
//        • full list of existing titles to exclude from suggestions
//   4. The Edge Function fetches Open Library plots and asks Claude Haiku
//      for 5 personalised recommendations with Italian explanations.
//   5. Display each recommendation with an AI-written reason.

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/weather_provider.dart';
import '../../core/providers/health_provider.dart';

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
  final String reason; // AI-generated personalised explanation (Italian)
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final libraryRecommendationsProvider =
    FutureProvider.autoDispose<List<BookRecommendation>>((ref) async {
  // Cache recommendations for 1 hour — avoids re-calling Gemini on every
  // screen transition and prevents hitting the 15 RPM free-tier limit.
  final link = ref.keepAlive();
  Future.delayed(const Duration(hours: 1), link.close);
  // ── 1. Collect highlights grouped by book ──────────────────────────────────
  //
  // We fetch all highlights ordered by added_at DESC (Supabase) so that
  // "most recent book" = first distinct book_id encountered.
  //
  // For each book we keep:
  //   • title + author   (from embedded books() join)
  //   • up to 4 highlight texts (reading context for Claude)

  // bookId → { title, author, highlights[] }
  final Map<String, Map<String, dynamic>> bookMap = {};
  // Ordered list of distinct book IDs (insertion order = recency)
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

        // Keep up to 4 highlights per book
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
    // Native (Isar): no embedded join, use book ID + title from booksProvider
    final all    = await ref.read(allHighlightsProvider.future);
    final books  = ref.read(booksProvider).value ?? [];
    final bookById = { for (final b in books) b.supabaseId: b };

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
  //
  // Take the 20 most recently active books as the primary reading context.
  // Pass the full list of titles to the Edge Function for exclusion.

  final recentIds   = orderedBookIds.take(20).toList();
  final allTitles   = orderedBookIds
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

  // ── 3. Collect context: weather + health ───────────────────────────────────
  //
  // These are optional — if unavailable the Edge Function still works.
  // Weather enriches the Gemini prompt so it can mention seasonal resonance.
  // Health data (when available on iOS) adds lifestyle context to suggestions.

  final weather     = ref.read(weatherProvider).asData?.value;
  final healthSnap  = ref.read(healthSnapshotProvider).asData?.value;

  final contextPayload = <String, dynamic>{
    if (weather != null) ...{
      'weather':     weather.widgetParam,       // 'sunny', 'rain', …
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

  debugPrint('[Recs] context payload: $contextPayload');

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
      },
    );

    if (result.data == null) {
      debugPrint('[Recs] Edge Function returned null data');
      return [];
    }

    // result.data is already decoded by supabase_flutter
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

  // ── 5. Parse recommendations ───────────────────────────────────────────────

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
      loading: () => const _RecommendationsSkeleton(),
      error: (e, _) {
        debugPrint('[Recs] UI error: $e');
        return const SizedBox.shrink();
      },
      data: (books) {
        if (books.isEmpty) {
          return const _RecommendationsHint(
            "Importa i tuoi highlight Kindle per ricevere suggerimenti"
            " personalizzati basati sui tuoi temi di lettura.",
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(),
              const SizedBox(height: 6),
              _RecommendationsSubtitle(),
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

  static Widget _sectionHeader() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('LIBRI CONSIGLIATI',
                  style: MarginaliaTextStyles.sectionTitle),
              const SizedBox(width: 12),
              const Expanded(
                child:
                    Divider(color: MarginaliaColors.ruleFaint, height: 1),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Consigliati da Marginalia per te (fidati, ti capiamo benissimo)',
            style: GoogleFonts.ebGaramond(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: MarginaliaColors.sienna,
              height: 1.3,
            ),
          ),
        ],
      );
}

// ─── Dynamic subtitle ─────────────────────────────────────────────────────────
//
// Base: "Selezionati da Marginalia in base ai tuoi highlight."
// + meteo se disponibile, + attività fisica se disponibile (iOS + HealthKit).

class _RecommendationsSubtitle extends ConsumerWidget {
  const _RecommendationsSubtitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasWeather  = ref.watch(weatherProvider).asData?.value != null;
    final hasActivity = ref.watch(lastWorkoutLabelProvider) != null ||
        ref.watch(stepCountLabelProvider) != null;

    final String suffix;
    if (hasWeather && hasActivity) {
      suffix = ', al meteo di oggi e alla tua attività fisica recente';
    } else if (hasWeather) {
      suffix = ' e al meteo di oggi';
    } else if (hasActivity) {
      suffix = ' e alla tua attività fisica recente';
    } else {
      suffix = '';
    }

    return Text(
      'Selezionati da Marginalia in base ai tuoi highlight$suffix.',
      style: GoogleFonts.manrope(
        fontSize: 11,
        color: MarginaliaColors.inkFaint,
        height: 1.4,
      ),
    );
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.rec, required this.index});
  final BookRecommendation rec;
  final int index;

  @override
  Widget build(BuildContext context) {
    final meta = [rec.author, rec.year]
        .where((s) => s.isNotEmpty && s != '—')
        .join(' · ');

    return Container(
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
          // Title
          Text(
            rec.title,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: MarginaliaColors.ink,
              height: 1.3,
              letterSpacing: -0.2,
            ),
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
          // AI reason
          Text(
            rec.reason.isNotEmpty
                ? rec.reason
                : 'Consigliato in base ai tuoi gusti di lettura.',
            style: GoogleFonts.ebGaramond(
              fontSize: 14,
              height: 1.65,
              color: rec.reason.isNotEmpty
                  ? MarginaliaColors.ink
                  : MarginaliaColors.inkFaint,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    )
        .animate(delay: (index * 80).ms)
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: 0.04, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }
}

// ─── Hint widget (empty state / error state) ──────────────────────────────────

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
          Row(
            children: [
              Text('LIBRI CONSIGLIATI',
                  style: MarginaliaTextStyles.sectionTitle),
              const SizedBox(width: 12),
              const Expanded(
                child:
                    Divider(color: MarginaliaColors.ruleFaint, height: 1),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Consigliati da Marginalia per te (fidati, ti capiamo benissimo)',
            style: GoogleFonts.ebGaramond(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: MarginaliaColors.sienna,
              height: 1.3,
            ),
          ),
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
          Row(
            children: [
              Text('LIBRI CONSIGLIATI',
                  style: MarginaliaTextStyles.sectionTitle),
              const SizedBox(width: 12),
              const Expanded(
                child:
                    Divider(color: MarginaliaColors.ruleFaint, height: 1),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Consigliati da Marginalia per te (fidati, ti capiamo benissimo)',
            style: GoogleFonts.ebGaramond(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: MarginaliaColors.sienna,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Marginalia sta analizzando i tuoi highlight…',
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
