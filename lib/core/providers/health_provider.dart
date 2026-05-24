// ─── Health Provider ──────────────────────────────────────────────────────────
//
// Exposes HealthKit data (steps, workouts, menstrual cycle) via Riverpod.
// On web / Windows returns empty stubs — no permissions, no errors.
//
// Usage:
//   final snap = ref.watch(healthSnapshotProvider);
//   snap.when(data: (s) => s.stepsToday ?? 0, …)
//
// The provider is NOT auto-triggered — call ref.refresh(healthSnapshotProvider)
// when the user grants permissions from SettingsScreen.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/health_service.dart';

export '../services/health_service.dart'
    show HealthSnapshot, WorkoutActivity, CyclePhase;

const _service = HealthService();

/// Request HealthKit / Health Connect permissions.
/// Returns true if granted. Safe to call multiple times.
Future<bool> requestHealthPermissions() => _service.requestPermissions();

/// Today's steps, this week's workouts, current cycle phase.
/// Refreshed on demand (e.g. when app comes to foreground).
final healthSnapshotProvider =
    FutureProvider.autoDispose<HealthSnapshot>((ref) async {
  // Keep alive for 10 min to avoid re-fetching on every screen transition.
  final link = ref.keepAlive();
  Future.delayed(const Duration(minutes: 10), link.close);

  return _service.fetchSnapshot();
});

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
