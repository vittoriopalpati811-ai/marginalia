// ─── SM-2 spaced-repetition engine ─────────────────────────────────────────────
//
// Pure, dependency-free implementation of the classic SuperMemo-2 algorithm,
// adapted to a 3-button grading surface (the user is recalling a saved
// highlight, not self-grading a flashcard, so a 6-point scale is heavier than
// the ritual warrants).
//
// Grades map to SM-2 "quality":
//   forgot → 2   (q < 3  → relearn: repetitions reset, interval back to 1 day)
//   hard   → 3   (q ≥ 3  → advances, but the ease factor decays)
//   good   → 5   (q ≥ 3  → advances, ease factor grows)
//
// State per highlight: easeFactor, intervalDays, repetitions, dueAt. All of it
// lives locally on the Isar Highlight (offline-first) — this engine is the only
// place the scheduling math is computed, and it never touches the network.

import 'dart:math' as math;

/// How well the reader recalled a highlight. The integer is the SM-2 "quality".
enum ReviewGrade {
  forgot(2),
  hard(3),
  good(5);

  const ReviewGrade(this.quality);
  final int quality;
}

/// The default ease factor for a brand-new card, per SM-2.
const double kDefaultEaseFactor = 2.5;

/// The floor SM-2 never lets the ease factor drop below.
const double kMinEaseFactor = 1.3;

/// The next schedule for a highlight after grading it.
class Sm2Result {
  const Sm2Result({
    required this.easeFactor,
    required this.intervalDays,
    required this.repetitions,
    required this.dueAt,
  });

  final double easeFactor;
  final int intervalDays;
  final int repetitions;
  final DateTime dueAt;
}

/// Computes the next schedule for a card given its current state and the grade.
///
/// [easeFactor] / [intervalDays] / [repetitions] are the card's current values
/// (use [kDefaultEaseFactor], 0, 0 for a never-reviewed card). [now] is the
/// reference instant (injected so this stays pure + unit-testable). The returned
/// [Sm2Result.dueAt] is `now` + the new interval in whole days.
Sm2Result scheduleSm2({
  required double easeFactor,
  required int intervalDays,
  required int repetitions,
  required ReviewGrade grade,
  required DateTime now,
}) {
  final q = grade.quality;

  // 1) Update the ease factor (applies on every grade, including a lapse, so a
  //    repeatedly-hard card keeps decaying toward the 1.3 floor).
  final delta = 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02);
  final newEase = math.max(kMinEaseFactor, easeFactor + delta);

  int newReps;
  int newInterval;

  if (q < 3) {
    // Lapse → relearn from the start: see it again tomorrow.
    newReps = 0;
    newInterval = 1;
  } else {
    // Successful recall → advance along the SM-2 interval ladder.
    if (repetitions <= 0) {
      newInterval = 1;
    } else if (repetitions == 1) {
      newInterval = 6;
    } else {
      newInterval = math.max(1, (intervalDays * newEase).round());
    }
    newReps = repetitions + 1;
  }

  return Sm2Result(
    easeFactor: newEase,
    intervalDays: newInterval,
    repetitions: newReps,
    dueAt: DateTime(now.year, now.month, now.day).add(Duration(days: newInterval)),
  );
}
