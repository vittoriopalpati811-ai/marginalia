// ─── Widget sync provider ──────────────────────────────────────────────────────
//
// Bridges live app data to the iOS home-screen widgets. Watching this provider
// (done once from the app root) wires three reactive pushes:
//
//   • allHighlightsProvider  → WidgetService.update()      (daily phrase widget)
//   • readingSessionsProvider→ WidgetService.updateStats() (stats widget)
//   • readingGoalProvider    → WidgetService.updateStats() (stats widget)
//
// Each push is a no-op on platforms without home_widget (web/Windows) and is
// internally guarded, so this can never crash the app. The widget therefore
// shows REAL data (refreshed on every app open / data change), not a placeholder.
//
// The stat formulas below intentionally mirror the private helpers in
// features/stats/stats_screen.dart so the widget's numbers match the in-app
// Stats screen exactly. Keep them in sync if those ever change.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/highlight.dart';
import '../services/widget_service.dart';
import 'highlights_provider.dart';
import '../../features/stats/stats_screen.dart'
    show readingGoalProvider, readingSessionsProvider;

/// Side-effecting provider: watch it once (e.g. from the app root) to keep the
/// iOS widgets continuously in sync with the user's data.
final widgetSyncProvider = Provider<void>((ref) {
  // ── Daily phrase ──────────────────────────────────────────────────────────
  ref.listen<AsyncValue<List<Highlight>>>(
    allHighlightsProvider,
    (_, next) {
      next.whenData((highlights) {
        if (highlights.isEmpty) return;
        final maps = highlights
            .map((h) => <String, dynamic>{
                  'body': h.content,
                  'book_title': h.bookTitle ?? '',
                  'author': h.bookAuthor ?? '',
                })
            .toList();
        WidgetService.update(maps);
      });
    },
    fireImmediately: true,
  );

  // ── Reading stats ────────────────────────────────────────────────────────
  void pushStats() {
    final sessions = ref.read(readingSessionsProvider).value;
    if (sessions == null) return;
    final goal = ref.read(readingGoalProvider).value;
    WidgetService.updateStats(
      streak: _streakDays(sessions),
      monthMinutes: _totalMinutesThisMonth(sessions),
      yearBooks: _countDistinctBooks(sessions),
      yearGoal: goal ?? 0,
    );
  }

  ref.listen(readingSessionsProvider, (_, __) => pushStats(), fireImmediately: true);
  ref.listen(readingGoalProvider, (_, __) => pushStats(), fireImmediately: true);
});

// ─── Stat formulas (mirror of stats_screen.dart private helpers) ─────────────

/// Distinct books with at least one session (all-time, matching the in-app
/// goal-progress count).
int _countDistinctBooks(List<Map<String, dynamic>> sessions) {
  final keys = <String>{};
  for (final s in sessions) {
    final id = s['book_id'] as String?;
    final title = (s['book_title'] as String?)?.toLowerCase().trim();
    final key = id ?? title ?? '';
    if (key.isEmpty) continue;
    keys.add(key);
  }
  return keys.length;
}

/// Consecutive days, ending today or yesterday, with at least one session.
int _streakDays(List<Map<String, dynamic>> sessions) {
  if (sessions.isEmpty) return 0;
  final days = <DateTime>{};
  for (final s in sessions) {
    final dateStr = s['session_date'] as String?;
    if (dateStr == null) continue;
    final d = DateTime.tryParse(dateStr);
    if (d == null) continue;
    days.add(DateTime(d.year, d.month, d.day));
  }
  if (days.isEmpty) return 0;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var cursor = today;
  if (!days.contains(today)) {
    cursor = today.subtract(const Duration(days: 1));
    if (!days.contains(cursor)) return 0;
  }

  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Sum of minutes_read for sessions in the current calendar month.
int _totalMinutesThisMonth(List<Map<String, dynamic>> sessions) {
  final now = DateTime.now();
  var total = 0;
  for (final s in sessions) {
    final dateStr = s['session_date'] as String?;
    if (dateStr == null) continue;
    final d = DateTime.tryParse(dateStr);
    if (d == null) continue;
    if (d.year != now.year || d.month != now.month) continue;
    total += ((s['minutes_read'] as num?) ?? 0).toInt();
  }
  return total;
}
