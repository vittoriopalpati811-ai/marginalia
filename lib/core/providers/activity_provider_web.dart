import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'highlights_provider_web.dart';

// ─── Activity providers — web ────────────────────────────────────────────────
//
// Mirrors the native surface so the shared "Activity" heatmaps compile and work
// on the Chrome dev target. Reading activity is derived from the Supabase-backed
// highlights list; review activity has no web log (the recall loop is
// native-gated), so it resolves to an empty map.

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _windowStart() {
  final today = _dateOnly(DateTime.now());
  return today.subtract(const Duration(days: 7 * 53));
}

/// Highlights added per local day, from the Supabase highlights list.
final readingDaysProvider =
    FutureProvider<Map<DateTime, int>>((ref) async {
  final all = await ref.watch(allHighlightsProvider.future);
  final start = _windowStart();
  final counts = <DateTime, int>{};
  for (final h in all) {
    final added = h.addedAt;
    if (added == null || added.isBefore(start)) continue;
    final day = _dateOnly(added);
    counts[day] = (counts[day] ?? 0) + 1;
  }
  return counts;
});

/// No review log on web — the recall ritual is offline-first / native-only.
final reviewActivityProvider =
    FutureProvider<Map<DateTime, int>>((ref) async => const {});
