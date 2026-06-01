// ─── Health Service — Native (iOS / Android) ──────────────────────────────────
//
// Full HealthKit implementation (ACTIVE). Reads today's steps, this week's
// workouts, and the current menstrual-cycle phase — the signals
// dailyHighlightProvider sends as context for the "frase scelta per te". All
// processing is on-device; nothing is uploaded.
//
// Requires (all in place):
//   • health: ^10.2.0 in pubspec.yaml
//   • HealthKit entitlement in ios/Runner/Runner.entitlements (wired into the
//     Runner target by the perl patch in codemagic.yaml)
//   • NSHealthShareUsageDescription / NSHealthUpdateUsageDescription in
//     ios/Runner/Info.plist
//   • HealthKit capability enabled on the App ID

import 'health_service_web.dart' show HealthSnapshot, WorkoutActivity, CyclePhase;

export 'health_service_web.dart'
    show WorkoutActivity, CyclePhase, HealthSnapshot;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:health/health.dart';

// Types we request from HealthKit (read-only).
const _kTypes = [
  HealthDataType.STEPS,
  HealthDataType.WORKOUT,
  HealthDataType.MENSTRUATION_FLOW,
];

class HealthService {
  const HealthService();

  // `Health()` is a factory returning a process-wide singleton, so creating it
  // per call is free and keeps this class const-constructible (used as a
  // top-level `const _service` in health_provider.dart).

  // ── Permissions ────────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    try {
      final granted = await Health().requestAuthorization(
        _kTypes,
        permissions: const [
          HealthDataAccess.READ,
          HealthDataAccess.READ,
          HealthDataAccess.READ,
        ],
      );
      debugPrint('[Health] permissions granted: $granted');
      return granted;
    } catch (e) {
      debugPrint('[Health] requestPermissions error: $e');
      return false;
    }
  }

  // ── Main fetch ─────────────────────────────────────────────────────────

  Future<HealthSnapshot> fetchSnapshot() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekAgo = today.subtract(const Duration(days: 7));

      // Trigger the HealthKit permission sheet on first run (iOS shows it once,
      // then returns immediately). Ignore the result — HealthKit masks read
      // denials for privacy, so we just attempt the fetch and degrade to empty.
      await Health().requestAuthorization(_kTypes, permissions: const [
        HealthDataAccess.READ,
        HealthDataAccess.READ,
        HealthDataAccess.READ,
      ]);

      final data = await Health().getHealthDataFromTypes(
        startTime: weekAgo,
        endTime: now,
        types: _kTypes,
      );

      final steps = _extractSteps(data, today);
      final workouts = _extractWorkouts(data, weekAgo);
      final phase = _extractCyclePhase(data);

      debugPrint(
          '[Health] steps=$steps workouts=${workouts.length} phase=$phase');

      return HealthSnapshot(
        stepsToday: steps,
        workoutsThisWeek: workouts,
        cyclePhase: phase,
        isAvailable: true,
      );
    } catch (e, st) {
      debugPrint('[Health] fetchSnapshot error: $e\n$st');
      return HealthSnapshot.empty;
    }
  }

  // ── Steps ──────────────────────────────────────────────────────────────

  int? _extractSteps(List<HealthDataPoint> data, DateTime today) {
    final stepsPoints = data
        .where((p) =>
            p.type == HealthDataType.STEPS && p.dateFrom.isAfter(today))
        .toList();
    if (stepsPoints.isEmpty) return null;
    int total = 0;
    for (final p in stepsPoints) {
      final val = p.value;
      if (val is NumericHealthValue) total += val.numericValue.toInt();
    }
    return total;
  }

  // ── Workouts ───────────────────────────────────────────────────────────

  List<WorkoutActivity> _extractWorkouts(
      List<HealthDataPoint> data, DateTime since) {
    return data
        .where((p) =>
            p.type == HealthDataType.WORKOUT && p.dateFrom.isAfter(since))
        .map((p) {
          final val = p.value;
          final type = val is WorkoutHealthValue
              ? val.workoutActivityType.name
              : 'Unknown';
          final mins = p.dateTo.difference(p.dateFrom).inMinutes;
          final kcal = val is WorkoutHealthValue
              ? val.totalEnergyBurned?.toDouble()
              : null;
          return WorkoutActivity(
            type: type,
            typeLabel: _italianWorkout(type),
            durationMinutes: mins,
            date: p.dateFrom,
            caloriesBurned: kcal,
          );
        })
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // ── Menstrual cycle ────────────────────────────────────────────────────
  //
  // HealthKit reports daily MENSTRUATION_FLOW values. We infer the phase from
  // the days since the most recent real flow.

  CyclePhase? _extractCyclePhase(List<HealthDataPoint> data) {
    final flowPoints = data
        .where((p) => p.type == HealthDataType.MENSTRUATION_FLOW)
        .toList()
      ..sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
    if (flowPoints.isEmpty) return null;

    final recentFlow = flowPoints.where((p) {
      final v = p.value;
      if (v is MenstruationFlowHealthValue) {
        return v.menstruationFlowValue != MenstruationFlow.unspecified &&
            v.menstruationFlowValue != MenstruationFlow.none;
      }
      return false;
    }).toList();
    if (recentFlow.isEmpty) return null;

    final lastFlowDate = recentFlow.first.dateFrom;
    final daysSince = DateTime.now().difference(lastFlowDate).inDays;
    if (daysSince <= 1) return CyclePhase.menstruation;
    if (daysSince <= 13) return CyclePhase.follicular;
    if (daysSince <= 17) return CyclePhase.ovulation;
    if (daysSince <= 28) return CyclePhase.luteal;
    return CyclePhase.unknown;
  }

  // ── Italian workout labels ─────────────────────────────────────────────

  String _italianWorkout(String hkType) => switch (hkType) {
        'Running' => 'Corsa',
        'Walking' => 'Camminata',
        'Cycling' => 'Ciclismo',
        'Swimming' => 'Nuoto',
        'Yoga' => 'Yoga',
        'Pilates' => 'Pilates',
        'Hiking' => 'Trekking',
        'Strength' => 'Forza',
        'HIIT' => 'HIIT',
        'Dance' => 'Danza',
        'MartialArts' => 'Arti marziali',
        'Tennis' => 'Tennis',
        'Soccer' => 'Calcio',
        'Basketball' => 'Basket',
        'Volleyball' => 'Pallavolo',
        'Rowing' => 'Canottaggio',
        'Skiing' => 'Sci',
        'Snowboarding' => 'Snowboard',
        _ => hkType,
      };
}
