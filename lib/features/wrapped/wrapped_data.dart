// ─── Reading Wrapped — client-side aggregator ────────────────────────────────
//
// A Spotify-Wrapped-style recap, computed ENTIRELY on-device from the local
// Isar highlights/books + the offline review streak. No backend, no LLM — every
// number and every line is derived deterministically from the user's own data,
// so it works offline and never produces "AI slop".
//
// Three cadences (the default is WEEKLY):
//   • WeeklyWrapped  — the last 7 days (the headline ritual).
//   • MonthlyWrapped — the last 30 days.
//   • AllTimeWrapped — everything ever highlighted.
//
// The heavy lifting is one pass over the user's highlights, bucketed by the
// chosen [WrappedPeriod]. The result is an immutable [WrappedData] the viewer
// renders into story cards. Aggregation is exposed through
// [wrappedDataProvider], a family keyed by period.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/book.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/review_provider.dart';

// ─── Period ──────────────────────────────────────────────────────────────────

enum WrappedPeriod { week, month, allTime }

extension WrappedPeriodX on WrappedPeriod {
  /// The inclusive lower bound (date-only midnight) for "in period". Null for
  /// [WrappedPeriod.allTime] (no lower bound — everything counts).
  DateTime? startFrom(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case WrappedPeriod.week:
        return today.subtract(const Duration(days: 6)); // last 7 days incl. today
      case WrappedPeriod.month:
        return today.subtract(const Duration(days: 29)); // last 30 days
      case WrappedPeriod.allTime:
        return null;
    }
  }
}

// ─── Reading personality ─────────────────────────────────────────────────────
//
// A deterministic, templated "reading personality" derived from the spread of
// the user's highlights — NOT an LLM call. We classify by two cheap signals:
//   • breadth  — how many distinct books the highlights span, and
//   • intensity — average highlights per active day.
// The result maps to a stable enum the viewer turns into a localized label +
// one-line description. Same data always yields the same persona.

enum ReadingPersonality {
  theMarginalia, // balanced, the house default
  theDevourer, // many highlights, few books — tears through a book
  theCollector, // many books, lighter touch each — a broad reader
  theDeepDiver, // one or two books, deeply annotated
  theDabbler, // a gentle handful — just getting started
  theMarathoner, // read on many distinct days — consistent ritual
}

// ─── Aggregated result ───────────────────────────────────────────────────────

class WrappedBookStat {
  const WrappedBookStat({
    required this.title,
    required this.author,
    required this.count,
  });
  final String title;
  final String author;
  final int count;
}

class WrappedData {
  const WrappedData({
    required this.period,
    required this.generatedAt,
    required this.highlightsInPeriod,
    required this.highlightsTotal,
    required this.booksInPeriod,
    required this.booksTotal,
    required this.daysRead,
    required this.busiestDay,
    required this.busiestDayCount,
    required this.topBook,
    required this.standoutHighlight,
    required this.standoutBookTitle,
    required this.standoutBookAuthor,
    required this.reviewStreak,
    required this.personality,
  });

  final WrappedPeriod period;
  final DateTime generatedAt;

  /// Highlights added within the period (for all-time this equals the total).
  final int highlightsInPeriod;

  /// Highlights ever captured — the lifetime number (for the "of N total" line).
  final int highlightsTotal;

  /// Distinct books touched within the period.
  final int booksInPeriod;

  /// Distinct books in the whole library.
  final int booksTotal;

  /// Distinct calendar days the user highlighted within the period.
  final int daysRead;

  /// The weekday (1 = Mon … 7 = Sun) with the most highlights in period, or
  /// null when there is no dated activity.
  final int? busiestDay;
  final int busiestDayCount;

  /// Most-highlighted book within the period (with its highlight count), or null.
  final WrappedBookStat? topBook;

  /// A standout highlight from the period — a strong, substantial passage chosen
  /// deterministically (longest among the longer half, seeded by the period).
  final String? standoutHighlight;
  final String? standoutBookTitle;
  final String? standoutBookAuthor;

  /// Current offline review (Ripasso) streak, in consecutive days.
  final int reviewStreak;

  final ReadingPersonality personality;

  /// True when there is essentially nothing to celebrate for this period — the
  /// viewer shows a gentle "nothing yet" state instead of empty cards.
  bool get isEmpty => highlightsInPeriod == 0 && reviewStreak == 0;
}

// ─── Aggregator ──────────────────────────────────────────────────────────────

/// Computes the [WrappedData] for [period] from the in-memory highlight + book
/// lists. Pure and synchronous so it is trivially testable and deterministic.
WrappedData aggregateWrapped({
  required WrappedPeriod period,
  required List<Highlight> highlights,
  required List<Book> books,
  required int reviewStreak,
  required DateTime now,
}) {
  final start = period.startFrom(now);

  bool inPeriod(DateTime? when) {
    if (start == null) return true; // all-time
    if (when == null) return false; // undated → only counts for all-time
    return !when.isBefore(start);
  }

  // ── One pass: bucket the in-period highlights ────────────────────────────
  final periodHighlights = <Highlight>[];
  final perBook = <String, int>{}; // key "title␟author" → count
  final perBookMeta = <String, WrappedBookStat>{};
  final perWeekday = <int, int>{}; // 1..7 → count
  final activeDays = <DateTime>{};

  for (final h in highlights) {
    if (!inPeriod(h.addedAt)) continue;
    periodHighlights.add(h);

    final title = (h.bookTitle ?? '').trim();
    final author = (h.bookAuthor ?? '').trim();
    if (title.isNotEmpty) {
      final key = '$title␟$author';
      perBook[key] = (perBook[key] ?? 0) + 1;
      perBookMeta[key] = WrappedBookStat(
        title: title,
        author: author,
        count: perBook[key]!,
      );
    }

    final when = h.addedAt;
    if (when != null) {
      perWeekday[when.weekday] = (perWeekday[when.weekday] ?? 0) + 1;
      activeDays.add(DateTime(when.year, when.month, when.day));
    }
  }

  // ── Most-highlighted book in period ──────────────────────────────────────
  WrappedBookStat? topBook;
  if (perBook.isNotEmpty) {
    final topKey = perBook.entries.reduce((a, b) {
      if (b.value != a.value) return b.value > a.value ? b : a;
      // Tie-break deterministically by key so the result is stable.
      return a.key.compareTo(b.key) <= 0 ? a : b;
    }).key;
    topBook = perBookMeta[topKey];
  }

  // ── Busiest weekday ──────────────────────────────────────────────────────
  int? busiestDay;
  var busiestDayCount = 0;
  if (perWeekday.isNotEmpty) {
    final top = perWeekday.entries.reduce((a, b) {
      if (b.value != a.value) return b.value > a.value ? b : a;
      return a.key <= b.key ? a : b; // earlier weekday wins ties
    });
    busiestDay = top.key;
    busiestDayCount = top.value;
  }

  // ── Standout highlight ───────────────────────────────────────────────────
  // Pick a substantial passage: take highlights of a sensible reading length,
  // prefer the longer half, then choose deterministically (seeded by period +
  // count) so the same week always surfaces the same quote — never random churn,
  // never an LLM. Falls back to the single longest if the library is tiny.
  Highlight? standout;
  final candidates = periodHighlights
      .where((h) => h.content.trim().length >= 40)
      .toList()
    ..sort((a, b) => b.content.trim().length.compareTo(a.content.trim().length));
  if (candidates.isNotEmpty) {
    // Restrict to the stronger (longer) half, then index by a stable seed.
    final pool = candidates.take((candidates.length / 2).ceil()).toList();
    final seed = (period.index * 31 + periodHighlights.length) % pool.length;
    standout = pool[seed];
  } else if (periodHighlights.isNotEmpty) {
    standout = periodHighlights.reduce(
        (a, b) => a.content.length >= b.content.length ? a : b);
  }

  // ── Distinct books in period vs. total ───────────────────────────────────
  final booksInPeriod = perBook.length;

  // ── Reading personality (deterministic, templated) ───────────────────────
  final daysRead = activeDays.length;
  final personality = _derivePersonality(
    highlightCount: periodHighlights.length,
    distinctBooks: booksInPeriod,
    daysRead: daysRead,
    period: period,
  );

  return WrappedData(
    period: period,
    generatedAt: now,
    highlightsInPeriod: periodHighlights.length,
    highlightsTotal: highlights.length,
    booksInPeriod: booksInPeriod,
    booksTotal: books.length,
    daysRead: daysRead,
    busiestDay: busiestDay,
    busiestDayCount: busiestDayCount,
    topBook: topBook,
    standoutHighlight: standout?.content.trim(),
    standoutBookTitle: standout?.bookTitle,
    standoutBookAuthor: standout?.bookAuthor,
    reviewStreak: reviewStreak,
    personality: personality,
  );
}

ReadingPersonality _derivePersonality({
  required int highlightCount,
  required int distinctBooks,
  required int daysRead,
  required WrappedPeriod period,
}) {
  if (highlightCount == 0) return ReadingPersonality.theDabbler;

  // Consistency wins first: many distinct active days reads as a steady ritual.
  // (For all-time this threshold is naturally higher.)
  final marathonDays = period == WrappedPeriod.week ? 5 : 12;
  if (daysRead >= marathonDays) return ReadingPersonality.theMarathoner;

  final avgPerBook =
      distinctBooks == 0 ? highlightCount.toDouble() : highlightCount / distinctBooks;

  // Deep diver: a lot of attention concentrated on one or two books.
  if (distinctBooks <= 2 && highlightCount >= 8) {
    return ReadingPersonality.theDeepDiver;
  }
  // Devourer: heavy highlighting, still fairly focused.
  if (avgPerBook >= 6 && highlightCount >= 12) {
    return ReadingPersonality.theDevourer;
  }
  // Collector: reading broadly across many books.
  if (distinctBooks >= 4) {
    return ReadingPersonality.theCollector;
  }
  // A gentle handful → still warming up.
  if (highlightCount < 5) return ReadingPersonality.theDabbler;

  return ReadingPersonality.theMarginalia;
}

// ─── Provider ────────────────────────────────────────────────────────────────

/// The Wrapped recap for [period], aggregated from local Isar. autoDispose +
/// family so each cadence is computed lazily and cached while the viewer is open.
final wrappedDataProvider =
    FutureProvider.autoDispose.family<WrappedData, WrappedPeriod>(
  (ref, period) async {
    final highlights = await ref.watch(allHighlightsProvider.future);
    final books = await ref.watch(booksProvider.future);

    var streak = 0;
    try {
      final reviewState = await ref.watch(reviewStateProvider.future);
      streak = reviewState.currentStreak;
    } catch (_) {
      // Review state is best-effort; a missing streak just shows 0.
    }

    return aggregateWrapped(
      period: period,
      highlights: highlights,
      books: books,
      reviewStreak: streak,
      now: DateTime.now(),
    );
  },
);
