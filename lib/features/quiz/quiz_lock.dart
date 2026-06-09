// ─── Daily-quiz 08:00 lock ───────────────────────────────────────────────────
//
// The daily quiz is a once-a-day ritual: after you finish it, the entry stays
// locked until 08:00 the next morning — mirroring Ripasso (see review_screen's
// 08:00 countdown). We persist only a single completion timestamp in
// SharedPreferences, deliberately avoiding a new Isar model (which would force a
// build_runner regen).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kQuizCompletedKey = 'quiz_last_completed_at';

/// Records that the daily quiz was completed now (local time).
Future<void> markQuizCompletedNow() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kQuizCompletedKey, DateTime.now().toIso8601String());
}

/// Pure helper: given the stored completion ISO string, returns the moment the
/// quiz unlocks (08:00 the morning AFTER completion) if it's still locked, else
/// null. Completing at any time of day T locks until the next calendar day's
/// 08:00, so finishing at 23:00 and at 02:00 both unlock the following 08:00.
DateTime? quizLockedUntilFrom(String? completedIso, {DateTime? now}) {
  if (completedIso == null) return null;
  final completed = DateTime.tryParse(completedIso);
  if (completed == null) return null;
  final unlockAt = DateTime(completed.year, completed.month, completed.day)
      .add(const Duration(days: 1, hours: 8));
  final reference = now ?? DateTime.now();
  return reference.isBefore(unlockAt) ? unlockAt : null;
}

/// Returns the unlock time if the daily quiz is currently locked, else null.
Future<DateTime?> quizLockedUntil() async {
  final prefs = await SharedPreferences.getInstance();
  return quizLockedUntilFrom(prefs.getString(_kQuizCompletedKey));
}

/// Locked-until time for the daily quiz, or null when it's available. Invalidate
/// this after completing a quiz so entry points re-evaluate.
final quizLockProvider = FutureProvider<DateTime?>((ref) async {
  return quizLockedUntil();
});
