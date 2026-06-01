// ─── Health Service — Native (iOS / Android) ──────────────────────────────────
//
// Reads HealthKit signals for the "frase scelta per te" daily-highlight context:
//   • TODAY'S STEPS  via getTotalStepsInInterval (version-stable).
//   • MENSTRUAL-CYCLE PHASE inferred from MENSTRUATION_FLOW samples.
//
// Read-only, on-device — nothing is uploaded. The cycle phase is derived locally
// and only its coarse label (menstruation / follicular / ovulation / luteal) is
// passed to the edge function; raw health samples never leave the device.
//
// Requires: health: >=11.1.1 <12 (11.x adds HealthDataType.MENSTRUATION_FLOW and
// keeps the Health() singleton + getTotalStepsInInterval; 12.x drops the
// singleton). Plus the HealthKit entitlement (Runner.entitlements, wired in
// codemagic.yaml), the NSHealth*UsageDescription strings in Info.plist, and the
// HealthKit capability on the App ID. Menstrual flow is a standard HKCategoryType
// — no extra clinical-records entitlement is needed.

import 'health_service_web.dart' show HealthSnapshot, WorkoutActivity, CyclePhase;

export 'health_service_web.dart'
    show WorkoutActivity, CyclePhase, HealthSnapshot;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:health/health.dart';

class HealthService {
  const HealthService();

  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.MENSTRUATION_FLOW,
    HealthDataType.WORKOUT,
  ];
  static const _permissions = [
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  // `Health()` is a factory returning a process-wide singleton, so creating it
  // per call is free and keeps this class const-constructible.

  Future<bool> requestPermissions() async {
    try {
      final granted = await Health().requestAuthorization(
        _types,
        permissions: _permissions,
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
      await Health().requestAuthorization(_types, permissions: _permissions);

      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);

      // Steps and cycle are independent: isolate each so one failing (e.g. the
      // user granted steps but not cycle) never wipes the other signal.
      int? steps;
      try {
        steps = await Health().getTotalStepsInInterval(midnight, now);
      } catch (e) {
        debugPrint('[Health] steps error: $e');
      }

      CyclePhase? cyclePhase;
      try {
        cyclePhase = await _fetchCyclePhase(now);
      } catch (e) {
        debugPrint('[Health] cycle error: $e');
      }

      var workouts = const <WorkoutActivity>[];
      try {
        workouts = await _fetchWorkouts(now);
      } catch (e) {
        debugPrint('[Health] workouts error: $e');
      }

      debugPrint('[Health] stepsToday=$steps '
          'cyclePhase=${cyclePhase?.name} workouts=${workouts.length}');

      return HealthSnapshot(
        stepsToday: steps,
        workoutsThisWeek: workouts,
        cyclePhase: cyclePhase,
        isAvailable: true,
      );
    } catch (e, st) {
      debugPrint('[Health] fetchSnapshot error: $e\n$st');
      return HealthSnapshot.empty;
    }
  }

  // ── Cycle-phase inference ───────────────────────────────────────────────────
  //
  // HealthKit exposes menstrual *flow* samples, not a ready phase. We read the
  // last 120 days of MENSTRUATION_FLOW, find the most recent period's start day
  // (first day of the latest run of flow days, tolerating a 1-day gap), and map
  // the days elapsed onto the canonical four phases using a typical 28-day
  // cycle. This is an approximation — good enough to gently colour the daily
  // phrase, never presented as medical fact. Returns null when there's no data
  // or it's too stale (>40 days) to be meaningful.

  Future<CyclePhase?> _fetchCyclePhase(DateTime now) async {
    final start = now.subtract(const Duration(days: 120));
    final points = await Health().getHealthDataFromTypes(
      types: const [HealthDataType.MENSTRUATION_FLOW],
      startTime: start,
      endTime: now,
    );
    if (points.isEmpty) return null;

    // Collapse samples to the distinct calendar days that had any flow logged.
    final days = <DateTime>{};
    for (final p in points) {
      final d = p.dateFrom;
      days.add(DateTime(d.year, d.month, d.day));
    }
    final sorted = days.toList()..sort();
    if (sorted.isEmpty) return null;

    // Walk back from the most recent flow day through consecutive days (≤2-day
    // gap tolerated for sparse logging) to find this period's start.
    var periodStart = sorted.last;
    for (var i = sorted.length - 1; i > 0; i--) {
      if (sorted[i].difference(sorted[i - 1]).inDays <= 2) {
        periodStart = sorted[i - 1];
      } else {
        break;
      }
    }

    final today = DateTime(now.year, now.month, now.day);
    final daysSince = today.difference(periodStart).inDays;
    final flowToday = days.contains(today);

    if (flowToday || daysSince <= 5) return CyclePhase.menstruation;
    if (daysSince <= 12) return CyclePhase.follicular;
    if (daysSince <= 16) return CyclePhase.ovulation;
    if (daysSince <= 40) return CyclePhase.luteal;
    return null; // last period too long ago — don't guess
  }

  // ── Workouts ────────────────────────────────────────────────────────────────
  //
  // Last 7 days of WORKOUT sessions. Like steps and cycle, this stays on-device
  // and is only distilled into the daily-phrase "tone" (a recent workout → a more
  // energetic phrase). Raw workout data never leaves the device.

  Future<List<WorkoutActivity>> _fetchWorkouts(DateTime now) async {
    final start = now.subtract(const Duration(days: 7));
    final points = await Health().getHealthDataFromTypes(
      types: const [HealthDataType.WORKOUT],
      startTime: start,
      endTime: now,
    );

    final workouts = <WorkoutActivity>[];
    for (final p in points) {
      final value = p.value;
      if (value is! WorkoutHealthValue) continue;
      final type = value.workoutActivityType.name;
      final minutes = p.dateTo.difference(p.dateFrom).inMinutes;
      workouts.add(WorkoutActivity(
        type: type,
        typeLabel: _workoutLabel(type),
        durationMinutes: minutes < 0 ? 0 : minutes,
        date: p.dateFrom,
        caloriesBurned: value.totalEnergyBurned?.toDouble(),
      ));
    }
    workouts.sort((a, b) => b.date.compareTo(a.date)); // most recent first
    return workouts;
  }

  // Short Italian label for common workout types; unknown types fall back to a
  // title-cased version of the raw HealthKit name.
  String _workoutLabel(String type) {
    const map = {
      'RUNNING': 'Corsa',
      'WALKING': 'Camminata',
      'CYCLING': 'Ciclismo',
      'SWIMMING': 'Nuoto',
      'YOGA': 'Yoga',
      'FUNCTIONAL_STRENGTH_TRAINING': 'Forza funzionale',
      'TRADITIONAL_STRENGTH_TRAINING': 'Pesi',
      'HIGH_INTENSITY_INTERVAL_TRAINING': 'HIIT',
      'PILATES': 'Pilates',
      'HIKING': 'Escursione',
      'DANCE': 'Danza',
      'ELLIPTICAL': 'Ellittica',
      'ROWING': 'Vogatore',
      'CORE_TRAINING': 'Core',
    };
    final label = map[type];
    if (label != null) return label;
    final words = type.toLowerCase().replaceAll('_', ' ').trim();
    return words.isEmpty
        ? 'Allenamento'
        : words[0].toUpperCase() + words.substring(1);
  }
}
