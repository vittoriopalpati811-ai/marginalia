import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../models/highlight_native.dart';
import '../models/daily_activity_native.dart';
import 'isar_provider_native.dart';
import 'auth_provider.dart';

// ─── Activity providers — native / offline-first ─────────────────────────────
//
// Two date-keyed activity maps that drive the profile "Activity" heatmaps. Both
// are read straight from Isar with zero network, mirroring the rest of the
// offline-first stack.
//
//   • [readingDaysProvider]    — how many highlights were ADDED on each local
//     day (reading activity), derived from Highlight.addedAt.
//   • [reviewActivityProvider] — how many cards were REVIEWED on each local day,
//     read from the DailyActivity log (reviewedCount).
//
// Keys are date-only midnights so a UI can look up `map[DateTime(y, m, d)]`
// directly. Values are clamped to the trailing ~53 weeks the heatmap renders, so
// the maps stay small even for a multi-year library.

/// Local midnight of the day [d] falls in (date-only).
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The inclusive lower bound the heatmaps care about: 53 weeks back from today,
/// snapped to the start of that day. Everything older is irrelevant to the grid.
DateTime _windowStart() {
  final today = _dateOnly(DateTime.now());
  return today.subtract(const Duration(days: 7 * 53));
}

/// Highlights added per local day → reading activity. Counts every highlight
/// whose [addedAt] falls within the heatmap window. Highlights with no date are
/// skipped (they can't be placed on a calendar).
final readingDaysProvider =
    FutureProvider<Map<DateTime, int>>((ref) async {
  final isar = ref.watch(isarProvider);
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return const {};

  final start = _windowStart();
  final rows = await isar.highlights
      .filter()
      .userIdEqualTo(userId)
      .addedAtIsNotNull()
      .addedAtGreaterThan(start, include: true)
      .findAll();

  final counts = <DateTime, int>{};
  for (final h in rows) {
    final added = h.addedAt;
    if (added == null) continue;
    final day = _dateOnly(added);
    counts[day] = (counts[day] ?? 0) + 1;
  }
  return counts;
});

/// Cards reviewed per local day → review activity, from the DailyActivity log.
/// A day with a finished session but a zero count still surfaces as 1 so it
/// reads as "reviewed" on the heatmap.
final reviewActivityProvider =
    FutureProvider<Map<DateTime, int>>((ref) async {
  final isar = ref.watch(isarProvider);
  final userId = ref.watch(currentUserProvider)?.id ?? 'local';

  final start = _windowStart();
  final rows = await isar.dailyActivitys
      .filter()
      .userIdEqualTo(userId)
      .dayGreaterThan(start, include: true)
      .findAll();

  final counts = <DateTime, int>{};
  for (final r in rows) {
    final count = r.reviewedCount > 0
        ? r.reviewedCount
        : (r.reviewedComplete ? 1 : 0);
    if (count <= 0) continue;
    counts[_dateOnly(r.day)] = count;
  }
  return counts;
});
