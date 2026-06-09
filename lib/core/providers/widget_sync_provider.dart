// ─── Widget sync provider ──────────────────────────────────────────────────────
//
// Bridges live app data to the iOS home-screen widgets. Watching this provider
// (done once from the app root) wires three reactive pushes:
//
//   • allHighlightsProvider  → WidgetService.update()      (daily phrase widget)
//   • readingSessionsProvider→ WidgetService.updateStats() (stats widget)
//   • readingGoalProvider    → WidgetService.updateStats() (stats widget)
//
// On top of those data-driven pushes, the widgets are ALSO re-pushed whenever
// the app comes back to the foreground (AppLifecycleState.resumed) and whenever
// the wall-clock day rolls over while the app is open. This matters because the
// chosen phrase and the stats are computed against DateTime.now():
//
//   • the phrase is scored on time-of-day / weekday / live weather,
//   • the streak is "consecutive days ending today",
//   • "this month" minutes reset on the 1st.
//
// Without a resume / day-rollover re-push the widget would freeze on whatever
// was written the first time the app was opened and never reflect a new day, a
// new time slot, or stats logged on another device — which is exactly the
// reported "frase scelta per te stays stale" bug.
//
// Each push is a no-op on platforms without home_widget (web/Windows) and is
// internally guarded, so this can never crash the app. The widget therefore
// shows REAL data (refreshed on every app open / resume / data change / new
// day), not a placeholder.
//
// The stat formulas below intentionally mirror the private helpers in
// features/stats/stats_screen.dart so the widget's numbers match the in-app
// Stats screen exactly. Keep them in sync if those ever change.

import 'dart:async';

import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/highlight.dart';
import '../services/widget_service.dart';
import '../services/watch_service.dart';
import 'highlights_provider.dart';
import 'daily_highlight_provider.dart';
import '../../features/stats/stats_screen.dart'
    show readingGoalProvider, readingSessionsProvider;

/// Side-effecting provider: watch it once (e.g. from the app root) to keep the
/// iOS widgets continuously in sync with the user's data.
// Latest values mirrored to the Apple Watch. updateApplicationContext keeps only
// the most recent snapshot, so phrase and stats arrive on separate async events
// but we always send the full known set.
String _watchText = '', _watchBook = '', _watchAuthor = '';
int _watchStreak = 0, _watchMonthMin = 0;
void _pushWatch() {
  WatchService.send(
    text: _watchText,
    book: _watchBook,
    author: _watchAuthor,
    monthMinutes: _watchMonthMin,
    streak: _watchStreak,
  );
}

final widgetSyncProvider = Provider<void>((ref) {
  // ── Daily phrase ──────────────────────────────────────────────────────────
  //
  // Pushes the SAME highlight the Library tab shows to the widget, so the two
  // never disagree. [dailyHighlightProvider] is the single source of truth for
  // "the phrase chosen for the user" (Groq pick + 3h-stable cache, with a
  // deterministic fallback); we forward its exact content/book/author to the
  // widget verbatim instead of letting the widget re-select locally.
  //
  // The raw [allHighlightsProvider] list is still passed as a last-resort
  // fallback: if the chosen highlight isn't ready (provider still loading or
  // the library is empty) WidgetService falls back to its local keyword pick so
  // the widget is never left blank. This runs on every data change (via the
  // listener below) and on a bare app-resume / day-rollover, where the chosen
  // phrase may have rolled to a new 3h bucket even though no provider re-emits.
  Future<void> pushPhrase() async {
    List<Highlight> highlights = const [];
    try {
      highlights = await ref.read(allHighlightsProvider.future);
    } catch (_) {}
    final maps = highlights
        .map((h) => <String, dynamic>{
              'body': h.content,
              'book_title': h.bookTitle ?? '',
              'author': h.bookAuthor ?? '',
            })
        .toList();

    // Resolve the app's chosen highlight, then push its exact fields. Awaiting
    // the future (rather than reading the cached .value, which is null when the
    // autoDispose provider has been disposed on resume) ensures the push always
    // reflects the real pick instead of pushing stale/empty data.
    Highlight? chosen;
    try {
      chosen = await ref.read(dailyHighlightProvider.future);
    } catch (_) {}
    if (chosen == null && maps.isEmpty) return;
    final wh = await WidgetService.update(
      maps,
      chosenText: chosen?.content,
      chosenBook: chosen?.bookTitle,
      chosenAuthor: chosen?.bookAuthor,
    );
    if (wh != null) {
      _watchText = wh.text;
      _watchBook = wh.bookTitle;
      _watchAuthor = wh.author;
      _pushWatch();
    }
  }

  ref.listen<AsyncValue<List<Highlight>>>(
    allHighlightsProvider,
    (_, next) => next.whenData((_) => pushPhrase()),
    fireImmediately: true,
  );

  // ── Reading stats ────────────────────────────────────────────────────────
  //
  // Recomputes streak / month-minutes against DateTime.now() each call, so a
  // resume or day-rollover re-push reflects the new day even when the session
  // data itself is unchanged.
  Future<void> pushStats() async {
    List<Map<String, dynamic>>? sessions;
    try {
      sessions = await ref.read(readingSessionsProvider.future);
    } catch (_) {}
    if (sessions == null) return;
    int? goal;
    try {
      goal = await ref.read(readingGoalProvider.future);
    } catch (_) {}
    final streak = _streakDays(sessions);
    final monthMinutes = _totalMinutesThisMonth(sessions);
    WidgetService.updateStats(
      streak: streak,
      monthMinutes: monthMinutes,
      yearBooks: _countDistinctBooks(sessions),
      yearGoal: goal ?? 0,
    );
    _watchStreak = streak;
    _watchMonthMin = monthMinutes;
    _pushWatch();
  }

  ref.listen(readingSessionsProvider, (_, __) => pushStats(), fireImmediately: true);
  ref.listen(readingGoalProvider, (_, __) => pushStats(), fireImmediately: true);

  // ── App-resume + day-rollover re-push ─────────────────────────────────────
  //
  // Re-push BOTH widgets when the app returns to the foreground, and once when a
  // new calendar day begins while the app is left open. The push helpers are
  // no-ops off iOS, so this machinery is harmless on web/Windows. Everything is
  // torn down when the provider is disposed (e.g. on sign-out) to avoid leaks.
  void pushAll() {
    pushPhrase();
    pushStats();
  }

  final observer = _WidgetSyncObserver(onResumed: pushAll);
  WidgetsBinding.instance.addObserver(observer);

  // A new day changes the chosen phrase (time/weekday keywords), the streak and
  // the "this month" total. A coarse hourly tick is enough to catch the rollover
  // for an app left open across midnight; if the day hasn't changed it's a no-op.
  var lastDay = _dayOf(DateTime.now());
  final dayTimer = Timer.periodic(const Duration(hours: 1), (_) {
    final today = _dayOf(DateTime.now());
    if (today != lastDay) {
      lastDay = today;
      pushAll();
    }
  });

  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(observer);
    dayTimer.cancel();
  });
});

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

// ─── Lifecycle observer ──────────────────────────────────────────────────────
//
// Fires [onResumed] each time the app returns to the foreground so the widgets
// are refreshed against the current time / weather / day on every app open.
class _WidgetSyncObserver with WidgetsBindingObserver {
  _WidgetSyncObserver({required this.onResumed});

  final void Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}

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
