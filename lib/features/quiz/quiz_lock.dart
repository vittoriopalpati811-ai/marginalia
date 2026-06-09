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

import 'dart:convert';

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

// ── Ripasso session results (today's recap) ──────────────────────────────────
//
// When the once-a-day session finishes we persist its grade tallies, so both
// the finished screen and the locked entry card can show "your results for
// today" until the next 08:00 reset (same window as the lock itself).

const _ripassoResultsKey = 'ripasso_results_v1';

/// Today's session results — valid only while the daily lock window from the
/// completion moment is still active (i.e. until the next 08:00).
class RipassoResults {
  const RipassoResults({
    required this.cards,
    required this.forgot,
    required this.hard,
    required this.good,
    required this.completedAt,
  });

  final int cards;
  final int forgot;
  final int hard;
  final int good;
  final DateTime completedAt;
}

Future<void> saveRipassoResults({
  required int cards,
  required int forgot,
  required int hard,
  required int good,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
      _ripassoResultsKey,
      jsonEncode({
        'cards': cards,
        'forgot': forgot,
        'hard': hard,
        'good': good,
        'at': DateTime.now().toIso8601String(),
      }));
}

Future<RipassoResults?> todayRipassoResults() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_ripassoResultsKey);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final atIso = decoded['at'] as String?;
    final at = atIso == null ? null : DateTime.tryParse(atIso);
    if (at == null) return null;
    // Stale once the lock window from that completion has passed (next 08:00).
    if (lockedUntilFrom(atIso) == null) return null;
    return RipassoResults(
      cards: (decoded['cards'] as num?)?.toInt() ?? 0,
      forgot: (decoded['forgot'] as num?)?.toInt() ?? 0,
      hard: (decoded['hard'] as num?)?.toInt() ?? 0,
      good: (decoded['good'] as num?)?.toInt() ?? 0,
      completedAt: at,
    );
  } catch (_) {
    return null;
  }
}

/// Today's ripasso recap, or null when none (not done yet / past the reset).
/// Invalidate after a session completes so entry points refresh.
final ripassoResultsProvider =
    FutureProvider<RipassoResults?>((ref) => todayRipassoResults());
