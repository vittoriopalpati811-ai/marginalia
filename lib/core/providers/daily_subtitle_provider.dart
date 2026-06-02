// ─── Daily Subtitle Provider ──────────────────────────────────────────────────
//
// The line under the daily phrase ("perché questa frase è per te"). It is
// WEIGHTED on the whole moment — the time of day, the calendar (with timings:
// something coming up, a full day ahead or behind you, something just finished),
// and the body (steps, today's workout, menstrual-cycle phase) — and ties that
// to why these words land right now. Not a fact dump, not generic filler.
//
// DESIGN
//  • On-device only: nothing leaves the phone, so it is composed locally from
//    written template banks (no LLM). Every line is concrete — it names the
//    event, the count, the hour-frame — so it reads observed, not generated.
//  • Time of day is a real axis: morning frames forward ("prima di partire"),
//    evening frames toward closing ("alle spalle", "per chiudere").
//  • Calendar timings drive salience: an imminent event > a full day > a
//    just-finished event > a later event.
//  • Always present: even with zero signals the hour alone yields a grounded
//    line, so the note never vanishes.
//  • One variant per day (day-stable seed) and gender-neutral Italian (no
//    participle/adjective agreeing with the reader; agreement falls on "il
//    corpo / la mente / la giornata"). Cycle branch only for gender == 'female'.
//
// PRIVACY: the cycle phase is woven in ONLY for locally-stored gender 'female'
// (genderProvider — never uploaded). Calendar event titles are read transiently
// and never persisted.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar_provider.dart';
import 'health_provider.dart';
import 'onboarding_provider.dart';

final dailySubtitleProvider = Provider.autoDispose<String?>((ref) {
  final health = ref.watch(healthSnapshotProvider).asData?.value;
  final cal = ref.watch(calendarSnapshotProvider).asData?.value;
  final gender = ref.watch(genderProvider);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  // Day-stable variation seed (changes day to day, steady through the day).
  final seed = now.year * 372 + now.month * 31 + now.day;

  // ── Body signals ───────────────────────────────────────────────────────────
  final rawSteps = health?.stepsToday;
  final steps = (rawSteps != null && rawSteps >= 500) ? rawSteps : null;
  final stepsText = steps != null ? _thousands(steps) : null;

  String? workout;
  if (health != null) {
    for (final w in health.workoutsThisWeek) {
      if (w.date.year == today.year &&
          w.date.month == today.month &&
          w.date.day == today.day) {
        workout = w.typeLabel.toLowerCase();
        break;
      }
    }
  }

  CyclePhase? phase;
  if (gender == 'female' && (health?.hasCycle ?? false)) {
    phase = health!.cyclePhase;
  }

  // ── Calendar signals (with timings) ─────────────────────────────────────────
  final count = cal?.events.length ?? 0;
  final next = cal?.nextAfter(now);
  final last = cal?.lastBefore(now);
  final imminent =
      next?.start != null && next!.start!.difference(now).inMinutes <= 150;
  final justFinished =
      last?.start != null && now.difference(last!.start!).inMinutes <= 120;

  return _compose(
    seed: seed,
    when: _timeWord(now.hour, seed),
    winding: now.hour >= 18 || now.hour < 5,
    steps: steps,
    stepsText: stepsText,
    workout: workout,
    phase: phase,
    eventCount: count,
    next: next,
    last: last,
    imminent: imminent,
    justFinished: justFinished,
  );
});

// ─── Composer ─────────────────────────────────────────────────────────────────
// Picks the single most salient lead (cycle care → imminent event → full day →
// just-finished → workout → lots of steps → uplifting cycle → later event →
// still day → moderate steps → the hour alone) and renders it through the
// time-of-day frame. Always returns a line.

String _compose({
  required int seed,
  required String when,
  required bool winding,
  int? steps,
  String? stepsText,
  String? workout,
  CyclePhase? phase,
  required int eventCount,
  CalendarEvent? next,
  CalendarEvent? last,
  required bool imminent,
  required bool justFinished,
}) {
  String pick(List<String> v) => v[seed % v.length];
  String ev(CalendarEvent e) => '«${_clip(e.title)}»';

  // 1. Cycle, tender phases — care comes first.
  if (phase == CyclePhase.menstruation) {
    return pick([
      '$when, nei giorni del ciclo in cui il corpo chiede spazio: questa frase è qui per accoglierti, senza chiederti nulla.',
      '$when, mentre il corpo fa il suo lavoro silenzioso — prenditi questa frase con calma, è pensata per te.',
    ]);
  }
  if (phase == CyclePhase.luteal) {
    return pick([
      '$when, in una fase del ciclo più raccolta: questa frase è qui per starti vicino, piano.',
      '$when, con la sensibilità un po\' più accesa di questi giorni — lascia che questa frase ti faccia compagnia.',
    ]);
  }

  // 2. Something coming up within a couple of hours.
  if (imminent && next != null) {
    return pick([
      '$when, e tra poco ${ev(next)}: prenditi questa frase prima di rientrare nel ritmo.',
      '$when, con ${ev(next)} che si avvicina — un attimo per te adesso, prima di tutto il resto.',
    ]);
  }

  // 3. A full day — framed as ahead or behind by whether events remain.
  if (eventCount >= 3) {
    if (next != null) {
      return pick([
        '$when, con una giornata piena davanti — $eventCount impegni in agenda: questa frase è il tuo momento prima di partire.',
        '$when, e $eventCount appuntamenti che ti aspettano: ritagliati questa frase prima di entrarci.',
      ]);
    }
    return pick([
      '$when, dopo una giornata piena da $eventCount impegni: questa frase è la pausa per scaricare tutto.',
      '$when, con $eventCount impegni ormai alle spalle — respira, questa frase è la tua quiete.',
    ]);
  }

  // 4. Just finished something.
  if (justFinished && last != null) {
    return pick([
      '$when, appena dopo ${ev(last)}: questa frase è il tuo modo per tornare a te.',
      '$when, con ${ev(last)} ormai alle spalle — respira, questa frase è per te.',
    ]);
  }

  // 5. The body moved today.
  if (workout != null) {
    return pick([
      '$when, con $workout ormai alle spalle: lascia che questa frase chiuda il cerchio in calma.',
      '$when, e oggi il corpo si è mosso — questa frase è la ricompensa tranquilla che ti spetta.',
    ]);
  }

  // 6. A lot of walking.
  if (steps != null && steps >= 8000) {
    return pick([
      '$when, dopo i $stepsText passi di oggi: questa frase è la tua tregua, scelta per te.',
      '$when, con tanta strada già fatta oggi — fermati un attimo qui, su queste parole.',
    ]);
  }

  // 7. Cycle, bright phases.
  if (phase == CyclePhase.follicular || phase == CyclePhase.ovulation) {
    return pick([
      '$when, con le energie in risalita di questi giorni: questa frase è benzina buona, prendila.',
      '$when, in una fase luminosa del ciclo — lascia che questa frase assecondi lo slancio.',
    ]);
  }

  // 8. Something later today (not imminent).
  if (next != null) {
    return pick([
      '$when, e più tardi ti aspetta ${ev(next)}: intanto questa frase è uno spazio solo tuo.',
      '$when, con ${ev(next)} ancora davanti — prenditi prima questo momento, è per te.',
    ]);
  }

  // 9. A still day — gentle, always-optional nudge to move.
  if (steps != null && steps < 2000) {
    return pick([
      '$when, e oggi i passi sono stati pochi: va bene così. Se ti va, due passi lenti più tardi; intanto questa frase è per te.',
      '$when, con una giornata più ferma del solito: nessuna fretta — questa frase è un invito a rallentare e, quando vorrai, a muoverti piano.',
    ]);
  }

  // 10. A moderate, in-motion day.
  if (steps != null) {
    return pick([
      '$when, con i tuoi $stepsText passi di oggi: questa frase è la pausa che completa il ritmo.',
      '$when, a giornata in movimento — lascia che queste parole siano il tuo momento di quiete.',
    ]);
  }

  // 11. Nothing but the hour — morning opens, evening closes.
  if (winding) {
    return pick([
      '$when, questa frase è un pensiero scelto per chiudere la giornata con te.',
      '$when, lascia che queste parole siano l\'ultimo gesto di cura di oggi.',
    ]);
  }
  return pick([
    '$when, questa frase è il primo piccolo gesto di cura della giornata.',
    '$when, queste parole sono scelte per il momento in cui sei adesso.',
  ]);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Sentence-opening time-of-day phrase (a couple of variants per band, picked
/// day-stably). Lower-cases naturally after a comma in the templates above.
String _timeWord(int hour, int seed) {
  final List<String> opts;
  if (hour >= 5 && hour < 10) {
    opts = ['Di prima mattina', 'Stamattina'];
  } else if (hour >= 10 && hour < 13) {
    opts = ['In mattinata', 'A metà mattina'];
  } else if (hour >= 13 && hour < 18) {
    opts = ['Nel pomeriggio', 'Oggi pomeriggio'];
  } else if (hour >= 18 && hour < 22) {
    opts = ['Stasera', 'A fine giornata'];
  } else {
    opts = ['A quest\'ora', 'A giornata ormai conclusa'];
  }
  return opts[seed % opts.length];
}

/// Trim an event title so the subtitle stays one tidy line.
String _clip(String s) => s.length > 36 ? '${s.substring(0, 35)}…' : s;

/// Italian-style thousands separator using a dot (e.g. 6200 → "6.200").
String _thousands(int value) => value
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
