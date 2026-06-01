// ─── Health Service — Native (iOS / Android) ──────────────────────────────────
//
// HealthKit step count for the "frase scelta per te" daily-highlight context.
// Read-only, on-device — nothing is uploaded.
//
// Scope note: we read TODAY'S STEPS via getTotalStepsInInterval — the canonical,
// version-stable health API. Workout and menstrual-cycle types were attempted
// but their value classes differ across `health` package versions
// (MENSTRUATION_FLOW / MenstruationFlowHealthValue aren't in 10.2.0), so they're
// intentionally left out to keep the build stable. Steps is the primary signal;
// the daily phrase also uses weather, calendar, and time of day.
//
// Requires: health: ^10.2.0, the HealthKit entitlement (Runner.entitlements,
// wired in codemagic.yaml), the NSHealth*UsageDescription strings in Info.plist,
// and the HealthKit capability on the App ID.

import 'health_service_web.dart' show HealthSnapshot, WorkoutActivity, CyclePhase;

export 'health_service_web.dart'
    show WorkoutActivity, CyclePhase, HealthSnapshot;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:health/health.dart';

class HealthService {
  const HealthService();

  static const _types = [HealthDataType.STEPS];

  // `Health()` is a factory returning a process-wide singleton, so creating it
  // per call is free and keeps this class const-constructible.

  Future<bool> requestPermissions() async {
    try {
      final granted = await Health().requestAuthorization(
        _types,
        permissions: const [HealthDataAccess.READ],
      );
      debugPrint('[Health] permissions granted: $granted');
      return granted;
    } catch (e) {
      debugPrint('[Health] requestPermissions error: $e');
      return false;
    }
  }

  Future<HealthSnapshot> fetchSnapshot() async {
    try {
      // Prompt for Health read access on first run (iOS shows the sheet once).
      await Health().requestAuthorization(
        _types,
        permissions: const [HealthDataAccess.READ],
      );

      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final steps = await Health().getTotalStepsInInterval(midnight, now);

      debugPrint('[Health] stepsToday=$steps');

      return HealthSnapshot(
        stepsToday: steps,
        workoutsThisWeek: const <WorkoutActivity>[],
        cyclePhase: null,
        isAvailable: true,
      );
    } catch (e, st) {
      debugPrint('[Health] fetchSnapshot error: $e\n$st');
      return HealthSnapshot.empty;
    }
  }
}
