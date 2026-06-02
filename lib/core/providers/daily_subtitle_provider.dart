// ─── Daily Subtitle Provider ──────────────────────────────────────────────────
//
// Produces ONE warm, elegant Italian sentence shown under the daily phrase that
// makes the reader feel the phrase was chosen for *them* — coddling + motivating
// from whatever on-device context signals are available (steps, today's workout,
// menstrual-cycle phase, today's calendar). No emojis: the app is minimalist.
//
// PRIVACY: the cycle phase is woven in ONLY for users whose locally-stored
// gender is 'female' (see genderProvider — never uploaded). For everyone else
// the cycle is never mentioned. All the source providers return null/empty off
// iOS, so on web / Windows this simply yields null and the subtitle disappears.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar_provider.dart';
import 'health_provider.dart';
import 'onboarding_provider.dart';

final dailySubtitleProvider = Provider.autoDispose<String?>((ref) {
  final health = ref.watch(healthSnapshotProvider).asData?.value;
  final todayTitles =
      ref.watch(calendarSnapshotProvider).asData?.value.todayTitles ??
          const <String>[];
  final gender = ref.watch(genderProvider);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // ── Gather optional facts ──────────────────────────────────────────────────
  final body = <String>[];

  // Steps — only worth mentioning from 500 up.
  final steps = health?.stepsToday;
  if (steps != null && steps >= 500) {
    final stepsText = _thousands(steps);
    final km = steps * 0.00075;
    final kmText = km >= 1 ? ' (~${_oneDecimal(km)} km)' : '';
    body.add('hai camminato $stepsText passi$kmText');
  }

  // Workout done TODAY (first matching this week's list).
  String? workoutLabel;
  if (health != null) {
    for (final w in health.workoutsThisWeek) {
      if (w.date.year == today.year &&
          w.date.month == today.month &&
          w.date.day == today.day) {
        workoutLabel = w.typeLabel.toLowerCase();
        break;
      }
    }
  }
  if (workoutLabel != null) {
    body.add('hai fatto $workoutLabel');
  }

  // Cycle — ONLY for female users with real cycle data. Never for anyone else.
  CyclePhase? cyclePhase;
  if (gender == 'female' && (health?.hasCycle ?? false)) {
    cyclePhase = health!.cyclePhase;
    final phaseLabel = switch (cyclePhase) {
      CyclePhase.menstruation => 'fase mestruale',
      CyclePhase.follicular => 'fase follicolare',
      CyclePhase.ovulation => 'ovulazione',
      CyclePhase.luteal => 'fase luteale',
      _ => null,
    };
    if (phaseLabel != null) body.add('sei nella $phaseLabel');
  }

  final event = todayTitles.isNotEmpty ? todayTitles.first.trim() : null;
  final hasEvent = event != null && event.isNotEmpty;

  // ── No signals at all → no subtitle (it just disappears). ──────────────────
  if (body.isEmpty && !hasEvent) return null;

  // ── Calendar-led variant: an event with no body facts → a gentler framing
  //    that leads with the event instead of a fact + closer. ────────────────
  if (body.isEmpty && hasEvent) {
    return 'Dopo «$event», questa frase è per farti respirare.';
  }

  // ── Compose the body facts, weave any calendar event, then a warm closer. ──
  var sentence = body.join(' e ');
  if (hasEvent) sentence = '$sentence, dopo «$event»';
  sentence = _capitalize(sentence);
  sentence = '$sentence ${_closer(cyclePhase, workoutLabel, steps)}';
  return sentence;
});

// ── Warm closer chosen by the dominant signal ────────────────────────────────
String _closer(CyclePhase? cyclePhase, String? workoutToday, int? steps) {
  if (cyclePhase == CyclePhase.menstruation || cyclePhase == CyclePhase.luteal) {
    return '— una pausa che ti coccola.';
  }
  if (workoutToday != null || (steps != null && steps >= 8000)) {
    return '— questo momento è per darti slancio.';
  }
  if (workoutToday == null && steps != null && steps < 2000) {
    return '— concediti questa pausa.';
  }
  return '— scelto per il tuo momento.';
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Italian-style thousands separator using a dot (e.g. 6200 → "6.200").
String _thousands(int value) => value
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');

/// One-decimal string with an Italian decimal comma (e.g. 4.65 → "4,7").
String _oneDecimal(double value) =>
    value.toStringAsFixed(1).replaceAll('.', ',');

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
