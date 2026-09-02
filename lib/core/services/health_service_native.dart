// ─── Health Service — DISABLED (Apple Guideline 2.5.1) ────────────────────────
//
// This used to read steps, sleep, workouts and cycle phase from HealthKit to
// tint the daily phrase. App Review rejected the app for it on 2026-09-02:
//
//   "The app's binary includes references to HealthKit components, but the app
//    does not appear to include any primary features that require health or
//    fitness data."
//
// That is a fair reading. The phrase-selection tone was a garnish, not a
// feature — we had even told App Review the app "works fully if access is
// declined", which is exactly the argument against keeping the entitlement.
// Apple asked for HealthKit to be removed from the binary, the entitlement, the
// Info.plist keys AND any third-party call into HealthKit, so the `health`
// package is gone from pubspec.yaml too: a linked framework is a reference,
// whether or not a line of our code runs.
//
// The TYPES stay, identical to the web stub, so every caller
// (daily_highlight_provider, daily_subtitle_provider, recommendations_section)
// keeps compiling and simply sees an empty snapshot — the same thing they
// already saw whenever the reader declined the permission.
//
// ⚠️ Do NOT re-add `health` or the HealthKit entitlement to the iOS app without
// a primary, user-visible health feature to justify them; it is a guaranteed
// 2.5.1 rejection. The ANDROID port is a separate copy and can keep Health
// Connect: Google reviews that under its own declaration.

import 'package:flutter/foundation.dart' show debugPrint;

// ─── Data classes (mirrored in health_service_web.dart) ───────────────────────

/// A single workout session.
class WorkoutActivity {
  const WorkoutActivity({
    required this.type,
    required this.typeLabel,
    required this.durationMinutes,
    required this.date,
    this.caloriesBurned,
  });

  final String type;
  final String typeLabel;
  final int durationMinutes;
  final DateTime date;
  final double? caloriesBurned;
}

/// Menstrual cycle phase. Kept so the snapshot shape is stable; nothing
/// populates it any more.
enum CyclePhase {
  menstruation,
  follicular,
  ovulation,
  luteal,
  unknown,
}

/// Snapshot of today's health metrics. Always empty since 2026-09-02.
class HealthSnapshot {
  const HealthSnapshot({
    this.stepsToday,
    this.workoutsThisWeek = const [],
    this.cyclePhase,
    this.sleepHoursLastNight,
    this.isAvailable = false,
  });

  final int? stepsToday;
  final List<WorkoutActivity> workoutsThisWeek;
  final CyclePhase? cyclePhase;
  final double? sleepHoursLastNight;
  final bool isAvailable;

  bool get hasSteps    => stepsToday != null;
  bool get hasWorkouts => workoutsThisWeek.isNotEmpty;
  bool get hasCycle    => cyclePhase != null && cyclePhase != CyclePhase.unknown;
  bool get hasSleep    => sleepHoursLastNight != null;

  static const empty = HealthSnapshot();
}

// ─── Service ──────────────────────────────────────────────────────────────────

class HealthService {
  const HealthService();

  /// No permission is requested: the app no longer links HealthKit.
  Future<bool> requestPermissions() async {
    debugPrint('[Health] disabled — HealthKit removed (App Review 2.5.1)');
    return false;
  }

  /// Always empty. Callers already handle this: it is what they received
  /// whenever the reader declined the permission.
  Future<HealthSnapshot> fetchSnapshot() async => HealthSnapshot.empty;
}
