import 'package:flutter_test/flutter_test.dart';
import 'package:scripta/core/providers/health_provider.dart';

// The cycle phase is the one piece of special-category data the app still uses,
// and it now comes from a date the reader typed rather than from HealthKit
// (removed for Apple Guideline 2.5.1). That makes the arithmetic the ONLY thing
// standing between a typo and months of wrongly-tinted phrases, so it is worth
// pinning down — especially the two cases where the right answer is "say
// nothing" rather than a guess.

void main() {
  // A fixed "today" so these never drift with the clock.
  final today = DateTime(2026, 9, 2);
  String daysAgo(int n, {int length = 28}) {
    final d = today.subtract(Duration(days: n));
    final s = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return '$s|$length';
  }

  CyclePhase? phase(String? raw) => cyclePhaseFromSetting(raw, now: today);

  group('nothing to say', () {
    test('no setting at all', () {
      expect(phase(null), isNull);
      expect(phase(''), isNull);
      expect(phase('   '), isNull);
    });

    test('unparseable input is ignored rather than guessed at', () {
      expect(phase('not-a-date|28'), isNull);
      expect(phase('|'), isNull);
    });

    test('a date in the future is a mis-tap, not a prediction', () {
      final tomorrow = today.add(const Duration(days: 1));
      expect(phase('${tomorrow.year}-0${tomorrow.month}-0${tomorrow.day}|28'),
          isNull);
    });

    test('an abandoned entry stops colouring phrases after three cycles', () {
      expect(phase(daysAgo(28 * 3)), isNotNull, reason: 'still inside 3 cycles');
      expect(phase(daysAgo(28 * 3 + 1)), isNull);
    });

    test('an implausible cycle length is refused', () {
      expect(phase(daysAgo(2, length: 10)), isNull);
      expect(phase(daysAgo(2, length: 60)), isNull);
    });
  });

  group('a 28-day cycle', () {
    test('the first five days are menstruation', () {
      expect(phase(daysAgo(0)), CyclePhase.menstruation);
      expect(phase(daysAgo(4)), CyclePhase.menstruation);
    });

    test('then follicular, up to two days before ovulation', () {
      expect(phase(daysAgo(5)), CyclePhase.follicular);
      expect(phase(daysAgo(11)), CyclePhase.follicular);
    });

    test('ovulation sits around day 14', () {
      expect(phase(daysAgo(12)), CyclePhase.ovulation);
      expect(phase(daysAgo(14)), CyclePhase.ovulation);
      expect(phase(daysAgo(16)), CyclePhase.ovulation);
    });

    test('and the rest is luteal', () {
      expect(phase(daysAgo(17)), CyclePhase.luteal);
      expect(phase(daysAgo(27)), CyclePhase.luteal);
    });

    test('it rolls forward instead of expiring after one month', () {
      expect(phase(daysAgo(28)), CyclePhase.menstruation);
      expect(phase(daysAgo(28 + 20)), CyclePhase.luteal);
    });
  });

  group('a shorter cycle moves ovulation with it', () {
    // 24 days → ovulation ≈ day 10, not day 14.
    test('ovulation follows the length, not a hardcoded 14', () {
      expect(phase(daysAgo(10, length: 24)), CyclePhase.ovulation);
      expect(phase(daysAgo(14, length: 24)), CyclePhase.luteal);
      expect(phase(daysAgo(14, length: 28)), CyclePhase.ovulation);
    });
  });
}
