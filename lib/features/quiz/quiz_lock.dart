// ─── Daily-ritual 08:00 lock (Quiz + Ripasso) ────────────────────────────────
//
// The daily Quiz and the daily Ripasso are once-a-day rituals: after you finish
// one, it stays locked until 08:00 the NEXT morning. We persist a single
// completion timestamp per activity in SharedPreferences (no Isar model, no
// build_runner regen).
//
// 08:00 reset: completing at any time of day T locks until the next calendar
// day's 08:00 — so finishing at 23:00 and at 02:00 both unlock the following
// 08:00.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _prefKey(String activity) => '${activity}_last_completed_at';

Future<void> _markDone(String activity) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefKey(activity), DateTime.now().toIso8601String());
}

/// Pure helper: given the stored completion ISO string, returns the unlock
/// moment (08:00 the morning AFTER completion) if still locked, else null.
DateTime? lockedUntilFrom(String? completedIso, {DateTime? now}) {
  if (completedIso == null) return null;
  final completed = DateTime.tryParse(completedIso);
  if (completed == null) return null;
  final unlockAt = DateTime(completed.year, completed.month, completed.day)
      .add(const Duration(days: 1, hours: 8));
  final reference = now ?? DateTime.now();
  return reference.isBefore(unlockAt) ? unlockAt : null;
}

Future<DateTime?> _lockedUntil(String activity) async {
  final prefs = await SharedPreferences.getInstance();
  return lockedUntilFrom(prefs.getString(_prefKey(activity)));
}

// ── Quiz ─────────────────────────────────────────────────────────────────────

Future<void> markQuizCompletedNow() => _markDone('quiz');

/// Back-compat alias kept for existing call sites.
DateTime? quizLockedUntilFrom(String? completedIso, {DateTime? now}) =>
    lockedUntilFrom(completedIso, now: now);

Future<DateTime?> quizLockedUntil() => _lockedUntil('quiz');

/// Locked-until time for the daily quiz, or null when available. Invalidate
/// after completing a quiz so entry points re-evaluate.
final quizLockProvider = FutureProvider<DateTime?>((ref) => quizLockedUntil());

// ── Ripasso ──────────────────────────────────────────────────────────────────

Future<void> markRipassoCompletedNow() => _markDone('ripasso');

Future<DateTime?> ripassoLockedUntil() => _lockedUntil('ripasso');

/// Locked-until time for the daily ripasso, or null when available. Invalidate
/// after a review so entry points re-evaluate.
final ripassoLockProvider =
    FutureProvider<DateTime?>((ref) => ripassoLockedUntil());
