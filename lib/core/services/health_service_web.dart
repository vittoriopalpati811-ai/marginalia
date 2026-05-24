// ─── Health Service — Web stub ────────────────────────────────────────────────
//
// HealthKit is not available on web or Windows.
// This stub returns empty/null data so the app compiles on all platforms.

import 'package:flutter/foundation.dart' show debugPrint;

// ─── Data classes (shared between web stub and native) ────────────────────────

/// A single workout session.
class WorkoutActivity {
  const WorkoutActivity({
    required this.type,
    required this.typeLabel,
    required this.durationMinutes,
    required this.date,
    this.caloriesBurned,
  });

  final String type;         // HK type string, e.g. 'Running'
  final String typeLabel;    // Italian label, e.g. 'Corsa'
  final int durationMinutes;
  final DateTime date;
  final double? caloriesBurned;
}

/// Menstrual cycle phase inferred from HealthKit data.
enum CyclePhase {
  menstruation,  // Mestruazioni
  follicular,    // Fase follicolare
  ovulation,     // Ovulazione
  luteal,        // Fase luteale
  unknown,       // Dati insufficienti
}

/// Snapshot of today's health metrics.
class HealthSnapshot {
  const HealthSnapshot({
    this.stepsToday,
    this.workoutsThisWeek = const [],
    this.cyclePhase,
    this.isAvailable = false,
  });

  /// Total steps walked today. Null if unavailable.
  final int? stepsToday;

  /// Workouts recorded in the last 7 days.
  final List<WorkoutActivity> workoutsThisWeek;

  /// Current menstrual cycle phase. Null if no cycle data or user skips it.
  final CyclePhase? cyclePhase;

  /// True only on iOS with HealthKit permission granted.
  final bool isAvailable;

  bool get hasSteps    => stepsToday != null;
  bool get hasWorkouts => workoutsThisWeek.isNotEmpty;
  bool get hasCycle    => cyclePhase != null && cyclePhase != CyclePhase.unknown;

  static const empty = HealthSnapshot();
}

// ─── Service ──────────────────────────────────────────────────────────────────

class HealthService {
  const HealthService();

  /// Always returns false on web/Windows.
  Future<bool> requestPermissions() async {
    debugPrint('[Health] HealthKit not available on this platform');
    return false;
  }

  /// Always returns an empty snapshot on web/Windows.
  Future<HealthSnapshot> fetchSnapshot() async {
    return HealthSnapshot.empty;
  }
}
