// ─── Daily Subtitle Provider ──────────────────────────────────────────────────
//
// Produces ONE warm, ARTICULATE Italian reflection shown under the daily phrase
// that makes the reader feel the phrase was chosen for *them* — it interprets
// the moment (it does not just list facts) and ties it to why these words are
// for them today. Built from whatever on-device context is available (steps,
// today's workout, menstrual-cycle phase, today's calendar). No emojis.
//
// DESIGN
//  • On-device only: health signals never leave the phone, so the text is
//    composed locally from rich template banks (no LLM, no network). The banks
//    are interpretive — "il corpo chiede di rallentare" rather than "X passi".
//  • One variant per day: a day-stable seed picks a phrasing, so it stays put
//    through the day (like the 3-hour phrase) but changes day to day.
//  • Gender-neutral Italian: avoids participles/adjectives that would agree with
//    the reader ("ti sei mosso/a"); uses invariable forms or agreement with
//    "il corpo / la mente / le energie", so it reads correctly for anyone. The
//    cycle branch is reached ONLY for gender == 'female'.
//
// PRIVACY: the cycle phase is woven in ONLY for users whose locally-stored
// gender is 'female' (see genderProvider — never uploaded). All source providers
// return null/empty off iOS; rather than vanish there (or before any data is
// available), the provider falls back to a warm, signal-free line so the daily
// card always carries its "chosen for you" note.

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

  // ── Gather raw signals ─────────────────────────────────────────────────────
  final rawSteps = health?.stepsToday;
  final steps = (rawSteps != null && rawSteps >= 500) ? rawSteps : null;
  final stepsText = steps != null ? _thousands(steps) : null;
  final km = steps != null ? steps * 0.00075 : 0.0;
  final kmText = km >= 1 ? '${_oneDecimal(km)} km' : null;

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

  // Cycle — ONLY for female users with real cycle data. Never for anyone else.
  CyclePhase? phase;
  if (gender == 'female' && (health?.hasCycle ?? false)) {
    phase = health!.cyclePhase;
  }

  final rawEvent = todayTitles.isNotEmpty ? todayTitles.first.trim() : null;
  final event = (rawEvent != null && rawEvent.isNotEmpty)
      ? (rawEvent.length > 42 ? '${rawEvent.substring(0, 41)}…' : rawEvent)
      : null;

  final hasAny =
      steps != null || workout != null || phase != null || event != null;

  // Day-stable variation seed (changes day to day, steady through the day).
  final seed = now.year * 372 + now.month * 31 + now.day;

  // The "why this phrase is for you" line is the emotional core of the daily
  // card, so it must NOT just vanish. With no on-device signals (early in the
  // day, health/calendar permission not granted, or off iOS) fall back to a
  // warm, signal-free reflection instead of returning null.
  if (!hasAny) {
    return const [
      'Questa frase è scelta per te, per il momento in cui sei oggi.',
      'Un pensiero scelto per accompagnarti oggi, qualunque sia la tua giornata.',
      'Queste parole sono qui per te, proprio adesso: uno spazio che è soltanto tuo.',
      'La frase di oggi è scelta apposta per il tuo momento.',
    ][seed % 4];
  }

  return _compose(
    seed: seed,
    steps: steps,
    stepsText: stepsText,
    kmText: kmText,
    workout: workout,
    phase: phase,
    event: event,
  );
});

// ─── Composer ─────────────────────────────────────────────────────────────────

String _compose({
  required int seed,
  int? steps,
  String? stepsText,
  String? kmText,
  String? workout,
  CyclePhase? phase,
  String? event,
}) {
  String pick(List<String> v) => v[seed % v.length];

  // A short, self-contained clause appended when there is a calendar event and
  // the event is not already the lead signal. Kept grammatically independent so
  // it can follow any base sentence cleanly.
  String withEvent(String base) {
    if (event == null) return base;
    final tail = [
      ' E con «$event» tra gli impegni di oggi, te lo meriti ancora di più.',
      ' Soprattutto oggi, con «$event» nel mezzo.',
      ' E dopo «$event», ancora di più.',
    ][(seed ~/ 7) % 3];
    return '$base$tail';
  }

  // 1. Cycle (female only) — the most tender, takes precedence.
  switch (phase) {
    case CyclePhase.menstruation:
      return withEvent(pick([
        'Sei nei giorni del ciclo in cui il corpo chiede di rallentare: questa frase è scelta per accoglierti con dolcezza, non per spingerti.',
        'Nei giorni delle mestruazioni va bene andare piano — il pensiero di oggi è qui per starti vicino, senza chiederti nulla in cambio.',
        'Il tuo corpo sta facendo un lavoro silenzioso e prezioso: queste parole vogliono soltanto prendersi cura di te, un respiro alla volta.',
      ]));
    case CyclePhase.luteal:
      return withEvent(pick([
        'Nella fase luteale l\'energia si raccoglie e tutto può pesare un po\' di più: questa frase è scelta per farti compagnia, con calma.',
        'Sei in fase luteale, quando il ritmo naturale invita a rientrare verso di sé — lascia che queste parole ti accompagnino piano.',
        'Sono i giorni in cui la sensibilità si fa più acuta: il pensiero di oggi è qui per coccolarti, non per metterti fretta.',
      ]));
    case CyclePhase.follicular:
      return withEvent(pick([
        'Sei nella fase follicolare, quando le energie tornano a salire: un momento perfetto per lasciarti ispirare da questa frase.',
        'La fase follicolare porta slancio e voglia di ricominciare — queste parole sono scelte per assecondare quella spinta, che è tutta tua.',
      ]));
    case CyclePhase.ovulation:
      return withEvent(pick([
        'Intorno all\'ovulazione la vitalità tocca il suo picco: la frase di oggi è qui per darti ancora più luce.',
        'Sono i giorni più luminosi del ciclo, pieni di energia — lascia che questa frase la incanali in qualcosa di tuo.',
      ]));
    case CyclePhase.unknown:
    case null:
      break; // no usable phase → fall through to the other signals
  }

  // 2. Workout today.
  if (workout != null) {
    final withSteps = stepsText != null ? ' e i $stepsText passi' : '';
    return withEvent(pick([
      'Dopo $workout$withSteps di oggi, il corpo è appagato e la mente più libera: questa frase è il tuo spazio per ricaricarti davvero.',
      'Oggi hai messo in movimento il corpo — $workout$withSteps: queste parole sono la pausa buona che ti spetta.',
      'Con $workout$withSteps alle spalle, concediti questa frase come una piccola ricompensa, pensata su misura per te.',
    ]));
  }

  // 3. A lot of walking.
  if (steps != null && steps >= 8000) {
    final kmPart = kmText != null ? ', quasi $kmText' : '';
    return withEvent(pick([
      '$stepsText passi$kmPart: oggi hai dato molto. Questa frase è la tua tregua, scelta apposta per te.',
      'Hai camminato parecchio, $stepsText passi$kmPart — lascia che questo pensiero sia il punto in cui ti fermi a respirare.',
    ]));
  }

  // 4. A still, sedentary day.
  if (steps != null && steps < 2000) {
    return withEvent(pick([
      'Oggi il corpo è rimasto tranquillo, e va bene così: questa frase è un piccolo invito a rallentare e respirare.',
      'Una giornata più ferma del solito — queste parole sono qui per regalarti comunque un momento che è soltanto tuo.',
    ]));
  }

  // 5. A moderate, in-motion day.
  if (steps != null) {
    return withEvent(pick([
      'Con i tuoi $stepsText passi, oggi hai tenuto un buon ritmo: questa frase è la pausa che lo completa.',
      '$stepsText passi finora, una giornata in movimento — lascia che queste parole siano il tuo momento di quiete.',
    ]));
  }

  // 6. Only a calendar event to go on.
  if (event != null) {
    return pick([
      'Con «$event» tra i pensieri di oggi, questa frase è scelta per ritagliarti uno spazio che è soltanto tuo.',
      'Dopo «$event», il pensiero di oggi vuole essere la tua piccola parentesi di calma.',
    ]);
  }

  // 7. Safety fallback (shouldn't be reached given hasAny).
  return 'Qualunque sia stata la tua giornata, queste parole sono qui per te, proprio adesso.';
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Italian-style thousands separator using a dot (e.g. 6200 → "6.200").
String _thousands(int value) => value
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');

/// One-decimal string with an Italian decimal comma (e.g. 4.65 → "4,7").
String _oneDecimal(double value) =>
    value.toStringAsFixed(1).replaceAll('.', ',');
