// ─── Daily-rhythm Provider (was: Health Provider) ─────────────────────────────
//
// This used to expose HealthKit — steps, sleep, workouts, cycle. Apple rejected
// the app for linking HealthKit without a primary health feature (Guideline
// 2.5.1, 2026-09-02), so the sensors are gone.
//
// What survives is the part the reader was actually promised: the daily phrase
// can follow their cycle IF THEY CHOOSE TO SAY SO. The phase is now computed
// on-device from a date they typed in Settings (see [cycleProvider] and
// [CycleService]) — nothing is read from the phone, nothing is inferred, and
// deleting the date turns it off completely.
//
// The snapshot shape is unchanged so every consumer
// (daily_highlight_provider, daily_subtitle_provider, recommendations_section)
// keeps working; steps/sleep/workouts are simply always null now.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/health_service.dart';
import 'onboarding_provider.dart';

export '../services/health_service.dart'
    show HealthSnapshot, WorkoutActivity, CyclePhase;

/// The current cycle phase, or null when the reader has not told us — which is
/// the default and stays the default until they fill it in.
///
/// Watches [cycleProvider], so editing the date in Settings updates the phrase
/// personalisation immediately, with no restart and no refresh call.
final healthSnapshotProvider =
    FutureProvider.autoDispose<HealthSnapshot>((ref) async {
  final raw = ref.watch(cycleProvider);
  return HealthSnapshot(cyclePhase: cyclePhaseFromSetting(raw));
});

/// Parses `yyyy-MM-dd|length` and works out where today falls in that cycle.
///
/// Thresholds are the ones the HealthKit path used for a 28-day cycle
/// (menstruation ≤5, follicular ≤12, ovulation ≤16, luteal after), rescaled
/// around ovulation ≈ length − 14 so a 24- or 34-day cycle lands sensibly too.
///
/// Two deliberate refusals to guess:
///   * a date in the FUTURE (a mis-tap in the picker) yields null rather than
///     nonsense;
///   * a date more than three cycles old is treated as abandoned — a stale
///     entry must not keep colouring phrases for months. The reader either
///     updates it or the personalisation quietly stops.
CyclePhase? cyclePhaseFromSetting(String? raw, {DateTime? now}) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parts = raw.split('|');
  final start = DateTime.tryParse(parts.first.trim());
  if (start == null) return null;
  final length = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 28) : 28;
  if (length < 20 || length > 40) return null;

  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final startDay = DateTime(start.year, start.month, start.day);
  final elapsed = today.difference(startDay).inDays;
  if (elapsed < 0) return null;
  if (elapsed > length * 3) return null;

  final day = elapsed % length;
  final ovulation = (length - 14).clamp(8, length - 3);
  if (day <= 4) return CyclePhase.menstruation;
  if (day < ovulation - 2) return CyclePhase.follicular;
  if (day <= ovulation + 2) return CyclePhase.ovulation;
  return CyclePhase.luteal;
}

/// Convenience: step count string for UI ("4 823 passi" or null)
final stepCountLabelProvider = Provider.autoDispose<String?>((ref) {
  final snap = ref.watch(healthSnapshotProvider);
  return snap.when(
    data: (s) {
      if (s.stepsToday == null) return null;
      // Italian thousands separator
      final formatted = s.stepsToday!
          .toString()
          .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
      return '$formatted passi oggi';
    },
    loading: () => null,
    error:   (_, __) => null,
  );
});

/// Convenience: last workout label for UI ("Corsa · 42 min ieri")
final lastWorkoutLabelProvider = Provider.autoDispose<String?>((ref) {
  final snap = ref.watch(healthSnapshotProvider);
  return snap.when(
    data: (s) {
      if (s.workoutsThisWeek.isEmpty) return null;
      final w    = s.workoutsThisWeek.first;
      final days = DateTime.now().difference(w.date).inDays;
      final when = days == 0 ? 'oggi' : days == 1 ? 'ieri' : '$days giorni fa';
      return '${w.typeLabel} · ${w.durationMinutes} min $when';
    },
    loading: () => null,
    error:   (_, __) => null,
  );
});

/// Italian cycle phase label ("Fase follicolare", "Ovulazione", …)
final cyclePhaseLabelProvider = Provider.autoDispose<String?>((ref) {
  final snap = ref.watch(healthSnapshotProvider);
  return snap.when(
    data: (s) {
      if (!s.hasCycle) return null;
      return switch (s.cyclePhase!) {
        CyclePhase.menstruation => 'Mestruazioni',
        CyclePhase.follicular   => 'Fase follicolare',
        CyclePhase.ovulation    => 'Ovulazione',
        CyclePhase.luteal       => 'Fase luteale',
        CyclePhase.unknown      => null,
      };
    },
    loading: () => null,
    error:   (_, __) => null,
  );
});
