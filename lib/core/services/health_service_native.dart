// ─── Health Service — Native (iOS / Android) ──────────────────────────────────
//
// Full HealthKit implementation, ready to activate.
//
// ⚠️  CURRENTLY STUBBED — the `health` package is not yet in pubspec.yaml.
//     When you're ready to submit to the App Store:
//
//     1. Add to pubspec.yaml:
//          health: ^10.2.0
//
//     2. Replace the stub block below with the real implementation block.
//        Both are included here — just swap the comments.
//
//     3. Complete the ACTIVATION CHECKLIST in health_service.dart.

// ─── Data classes (re-exported from web stub for type consistency) ────────────

export 'health_service_web.dart'
    show WorkoutActivity, CyclePhase, HealthSnapshot;

import 'package:flutter/foundation.dart' show debugPrint;

// ─────────────────────────────────────────────────────────────────────────────
// ██████  STUB BLOCK — active now (package not yet added)  ████████████████████
// ─────────────────────────────────────────────────────────────────────────────

class HealthService {
  const HealthService();

  Future<bool> requestPermissions() async {
    debugPrint('[Health] stub: health package not yet added to pubspec');
    return false;
  }

  Future<HealthSnapshot> fetchSnapshot() async => HealthSnapshot.empty;
}

// ─────────────────────────────────────────────────────────────────────────────
// ██████  REAL BLOCK — uncomment after adding `health: ^10.2.0`  ██████████████
// ─────────────────────────────────────────────────────────────────────────────
//
// import 'package:health/health.dart';
//
// // Types we request from HealthKit
// const _kTypes = [
//   HealthDataType.STEPS,
//   HealthDataType.WORKOUT,
//   HealthDataType.MENSTRUATION_FLOW,
// ];
//
// class HealthService {
//   const HealthService();
//
//   final Health _health = Health();
//
//   // ── Permissions ────────────────────────────────────────────────────────
//
//   Future<bool> requestPermissions() async {
//     try {
//       final granted = await _health.requestAuthorization(
//         _kTypes,
//         permissions: [
//           HealthDataAccess.READ,
//           HealthDataAccess.READ,
//           HealthDataAccess.READ,
//         ],
//       );
//       debugPrint('[Health] permissions granted: $granted');
//       return granted;
//     } catch (e) {
//       debugPrint('[Health] requestPermissions error: $e');
//       return false;
//     }
//   }
//
//   // ── Main fetch ─────────────────────────────────────────────────────────
//
//   Future<HealthSnapshot> fetchSnapshot() async {
//     try {
//       final now   = DateTime.now();
//       final today = DateTime(now.year, now.month, now.day);
//       final weekAgo = today.subtract(const Duration(days: 7));
//
//       final data = await _health.getHealthDataFromTypes(
//         startTime: weekAgo,
//         endTime:   now,
//         types:     _kTypes,
//       );
//
//       final steps    = _extractSteps(data, today);
//       final workouts = _extractWorkouts(data, weekAgo);
//       final phase    = _extractCyclePhase(data);
//
//       debugPrint('[Health] steps=$steps workouts=${workouts.length} phase=$phase');
//
//       return HealthSnapshot(
//         stepsToday:       steps,
//         workoutsThisWeek: workouts,
//         cyclePhase:       phase,
//         isAvailable:      true,
//       );
//     } catch (e, st) {
//       debugPrint('[Health] fetchSnapshot error: $e\n$st');
//       return HealthSnapshot.empty;
//     }
//   }
//
//   // ── Steps ──────────────────────────────────────────────────────────────
//
//   int? _extractSteps(List<HealthDataPoint> data, DateTime today) {
//     final stepsPoints = data
//         .where((p) =>
//             p.type == HealthDataType.STEPS &&
//             p.dateFrom.isAfter(today))
//         .toList();
//
//     if (stepsPoints.isEmpty) return null;
//
//     int total = 0;
//     for (final p in stepsPoints) {
//       final val = p.value;
//       if (val is NumericHealthValue) total += val.numericValue.toInt();
//     }
//     return total;
//   }
//
//   // ── Workouts ───────────────────────────────────────────────────────────
//
//   List<WorkoutActivity> _extractWorkouts(
//       List<HealthDataPoint> data, DateTime since) {
//     return data
//         .where((p) =>
//             p.type == HealthDataType.WORKOUT &&
//             p.dateFrom.isAfter(since))
//         .map((p) {
//           final val  = p.value;
//           final type = val is WorkoutHealthValue
//               ? val.workoutActivityType.name
//               : 'Unknown';
//           final mins = p.dateTo.difference(p.dateFrom).inMinutes;
//           final kcal = val is WorkoutHealthValue
//               ? val.totalEnergyBurned?.toDouble()
//               : null;
//           return WorkoutActivity(
//             type:             type,
//             typeLabel:        _italianWorkout(type),
//             durationMinutes:  mins,
//             date:             p.dateFrom,
//             caloriesBurned:   kcal,
//           );
//         })
//         .toList()
//       ..sort((a, b) => b.date.compareTo(a.date));
//   }
//
//   // ── Menstrual cycle ────────────────────────────────────────────────────
//   //
//   // HealthKit reports daily MENSTRUATION_FLOW values (none/light/medium/heavy).
//   // We infer the cycle phase from the most recent 35 days of flow data.
//   //
//   //  • If flow recorded today or yesterday → menstruation
//   //  • If last flow was 5-14 days ago       → follicular
//   //  • If last flow was 14-17 days ago       → ovulation window
//   //  • If last flow was 18-28 days ago       → luteal
//   //  • Otherwise                              → unknown
//
//   CyclePhase? _extractCyclePhase(List<HealthDataPoint> data) {
//     final flowPoints = data
//         .where((p) => p.type == HealthDataType.MENSTRUATION_FLOW)
//         .toList()
//       ..sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
//
//     if (flowPoints.isEmpty) return null;
//
//     // Check if there's actual flow (not MenstruationFlowNone)
//     final recentFlow = flowPoints.where((p) {
//       final v = p.value;
//       if (v is MenstruationFlowHealthValue) {
//         return v.menstruationFlowValue != MenstruationFlow.unspecified &&
//                v.menstruationFlowValue != MenstruationFlow.none;
//       }
//       return false;
//     }).toList();
//
//     if (recentFlow.isEmpty) return null;
//
//     final lastFlowDate = recentFlow.first.dateFrom;
//     final daysSince = DateTime.now().difference(lastFlowDate).inDays;
//
//     if (daysSince <= 1)  return CyclePhase.menstruation;
//     if (daysSince <= 13) return CyclePhase.follicular;
//     if (daysSince <= 17) return CyclePhase.ovulation;
//     if (daysSince <= 28) return CyclePhase.luteal;
//     return CyclePhase.unknown;
//   }
//
//   // ── Italian workout labels ─────────────────────────────────────────────
//
//   String _italianWorkout(String hkType) => switch (hkType) {
//     'Running'          => 'Corsa',
//     'Walking'          => 'Camminata',
//     'Cycling'          => 'Ciclismo',
//     'Swimming'         => 'Nuoto',
//     'Yoga'             => 'Yoga',
//     'Pilates'          => 'Pilates',
//     'Hiking'           => 'Trekking',
//     'Strength'         => 'Forza',
//     'HIIT'             => 'HIIT',
//     'Dance'            => 'Danza',
//     'MartialArts'      => 'Arti marziali',
//     'Tennis'           => 'Tennis',
//     'Soccer'           => 'Calcio',
//     'Basketball'       => 'Basket',
//     'Volleyball'       => 'Pallavolo',
//     'Rowing'           => 'Canottaggio',
//     'Skiing'           => 'Sci',
//     'Snowboarding'     => 'Snowboard',
//     _                  => hkType,
//   };
// }
