import 'package:flutter_test/flutter_test.dart';
import 'package:marginalia/core/review/sm2.dart';

void main() {
  final now = DateTime(2026, 6, 8);

  group('SM-2 successful recall ladder', () {
    test('new card graded good → 1 day, reps 1, ease grows', () {
      final r = scheduleSm2(
        easeFactor: kDefaultEaseFactor,
        intervalDays: 0,
        repetitions: 0,
        grade: ReviewGrade.good,
        now: now,
      );
      expect(r.intervalDays, 1);
      expect(r.repetitions, 1);
      expect(r.easeFactor, closeTo(2.6, 1e-9));
      expect(r.dueAt, DateTime(2026, 6, 9));
    });

    test('second good → 6 days', () {
      final r = scheduleSm2(
        easeFactor: 2.6,
        intervalDays: 1,
        repetitions: 1,
        grade: ReviewGrade.good,
        now: now,
      );
      expect(r.intervalDays, 6);
      expect(r.repetitions, 2);
    });

    test('third good → round(prevInterval * newEase)', () {
      final r = scheduleSm2(
        easeFactor: 2.7,
        intervalDays: 6,
        repetitions: 2,
        grade: ReviewGrade.good,
        now: now,
      );
      expect(r.easeFactor, closeTo(2.8, 1e-9));
      expect(r.intervalDays, (6 * 2.8).round()); // 17
      expect(r.repetitions, 3);
    });
  });

  test('hard advances but decays the ease factor', () {
    final r = scheduleSm2(
      easeFactor: kDefaultEaseFactor,
      intervalDays: 0,
      repetitions: 0,
      grade: ReviewGrade.hard,
      now: now,
    );
    expect(r.intervalDays, 1);
    expect(r.repetitions, 1);
    expect(r.easeFactor, closeTo(2.36, 1e-9));
  });

  test('forgot resets interval + repetitions and decays ease', () {
    final r = scheduleSm2(
      easeFactor: 2.5,
      intervalDays: 17,
      repetitions: 3,
      grade: ReviewGrade.forgot,
      now: now,
    );
    expect(r.intervalDays, 1);
    expect(r.repetitions, 0);
    expect(r.easeFactor, closeTo(2.18, 1e-9));
    expect(r.dueAt, DateTime(2026, 6, 9));
  });

  test('ease factor never drops below the 1.3 floor', () {
    var ef = kDefaultEaseFactor;
    for (var i = 0; i < 20; i++) {
      ef = scheduleSm2(
        easeFactor: ef,
        intervalDays: 1,
        repetitions: 0,
        grade: ReviewGrade.forgot,
        now: now,
      ).easeFactor;
    }
    expect(ef, kMinEaseFactor);
  });
}
