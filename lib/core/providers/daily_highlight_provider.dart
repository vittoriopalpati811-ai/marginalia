// ─── Daily Highlight Provider ─────────────────────────────────────────────────
//
// Uses Groq (Llama 3.3 70B) via the `pick-daily-highlight` Edge Function to
// select the most contextually resonant highlight from the user's library.
//
// NOT autoDispose — the result is stable for the entire app session (doesn't
// change when the user navigates away and back). It auto-refreshes after 3 hours
// by invalidating itself via a Timer. Force-refresh via ref.invalidate() after
// import.
//
// Context factors: time of day, weather, steps, workout, cycle phase.
// Falls back to a date+hour-seeded deterministic pick if the Edge Function fails.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/highlight.dart';
import '../providers/auth_provider.dart';
import '../providers/highlights_provider.dart';
import '../providers/weather_provider.dart';
import '../providers/health_provider.dart';
import '../providers/calendar_provider.dart';

// ─── 3-hour stability cache ─────────────────────────────────────────────────
//
// The chosen phrase must stay STABLE for a 3-hour window regardless of
// pull-to-refresh, scroll, or re-watch — the user should NOT get a new phrase
// every time they swipe to refresh. This module-level cache lives OUTSIDE the
// provider's state, so it survives `ref.invalidate(dailyHighlightProvider)`:
// once a phrase is chosen for a 3h bucket it's reused until the bucket rolls
// over (or the 3h self-invalidate timer fires).
String? _cachedBucketKey;
int? _cachedHighlightId;

String _bucketKey(DateTime now) =>
    '${now.year}-${now.month}-${now.day}-${now.hour ~/ 3}';

// ─── Provider ─────────────────────────────────────────────────────────────────
//
// Regular (non-autoDispose) FutureProvider so it is never torn down by
// navigation. Riverpod keeps the computed value alive as long as the app runs.

final dailyHighlightProvider = FutureProvider<Highlight?>((ref) async {
  // ── Auto-invalidate after 3 hours ─────────────────────────────────────────
  //
  // When the timer fires the provider is invalidated; next time the library
  // screen is visited Groq is called again with fresh context.
  Timer(const Duration(hours: 3), () {
    try {
      ref.invalidateSelf();
    } catch (_) {
      // Provider may already be gone (app closed) — safe to ignore.
    }
  });

  // ── 1. Get all highlights ──────────────────────────────────────────────────
  final List<Highlight> all;
  try {
    all = await ref.read(allHighlightsProvider.future);
  } catch (e) {
    debugPrint('[DailyHL] allHighlightsProvider error: $e');
    return null;
  }

  if (all.isEmpty) return null;
  if (all.length < 3) return all.first;

  // ── 3-hour stability ───────────────────────────────────────────────────────
  final now       = DateTime.now();
  final bucketKey = _bucketKey(now);

  // Already chose for this 3h bucket? Reuse it (survives pull-to-refresh / scroll
  // / re-watch) as long as that highlight still exists in the library.
  if (_cachedBucketKey == bucketKey && _cachedHighlightId != null) {
    for (final h in all) {
      if (h.id == _cachedHighlightId) {
        debugPrint('[DailyHL] reusing pick for bucket $bucketKey');
        return h;
      }
    }
  }

  // Records the chosen highlight for this bucket so subsequent runs are stable.
  Highlight remember(Highlight h) {
    _cachedBucketKey = bucketKey;
    _cachedHighlightId = h.id;
    return h;
  }

  // ── 2. Build a diverse sample (max 40 highlights sent to Groq) ────────────
  //
  // Prefer favorites (stronger personal meaning) but include a healthy mix so
  // Groq has real variety to choose from. The sample is shuffled once here and
  // is stable for this computation run (won't change on re-watch).

  final favs   = all.where((h) => h.isFavorite).toList();
  final others = (List<Highlight>.from(all.where((h) => !h.isFavorite))
    ..shuffle());

  final sample = <Highlight>[
    ...favs.take(20),
    ...others.take(20),
  ]..shuffle();

  final limited = sample.take(40).toList();

  // ── 3. Collect context ─────────────────────────────────────────────────────

  final weather    = ref.read(weatherProvider).asData?.value;
  final healthSnap = ref.read(healthSnapshotProvider).asData?.value;
  // Reading this also kicks off the fetch so today's events are cached for the
  // next 3-hour refresh even if they aren't ready on the very first run.
  final calendar   = ref.read(calendarSnapshotProvider).asData?.value;

  // Privacy by design: distil health signals (steps + menstrual-cycle phase)
  // into an abstract, NON-health "tone" hint ON-DEVICE. Only this coarse mood
  // word is sent to the picker — raw health data never leaves the device, so
  // the "your health data stays on your phone" promise holds. The cycle still
  // shapes the chosen highlight, just privately.
  String? tone;
  if (healthSnap != null && healthSnap.isAvailable) {
    final phase = healthSnap.cyclePhase?.name;
    final steps = healthSnap.stepsToday;
    final today = DateTime(now.year, now.month, now.day);
    final workedOutToday = healthSnap.workoutsThisWeek.any((w) =>
        w.date.year == today.year &&
        w.date.month == today.month &&
        w.date.day == today.day);
    if (phase == 'menstruation' || phase == 'luteal') {
      tone = 'gentle';
    } else if (phase == 'follicular' || phase == 'ovulation') {
      tone = 'uplifting';
    } else if (workedOutToday) {
      tone = 'uplifting'; // a workout today → an energetic, propositive tone
    } else if (steps != null && steps >= 8000) {
      tone = 'uplifting';
    } else if (steps != null && steps < 2000) {
      tone = 'reflective';
    }
  }

  final contextPayload = <String, dynamic>{
    'hour': now.hour,
    if (weather != null) ...{
      'weather':     weather.widgetParam,
      'weatherCity': weather.cityName,
      'weatherTemp': weather.temperatureRounded,
    },
    // Only an abstract, non-health mood word — see the tone derivation above.
    if (tone != null) 'tone': tone,
    if (calendar != null && calendar.isNotEmpty)
      'calendarEvents': calendar.todayTitles,
  };

  // ── 4. Call Edge Function ──────────────────────────────────────────────────

  final service = ref.read(supabaseServiceProvider);

  try {
    final payload = limited.map((h) => {
      'content':   h.content.length > 220
          ? '${h.content.substring(0, 220)}…'
          : h.content,
      'bookTitle': h.bookTitle ?? '',
    }).toList();

    final result = await service.client.functions.invoke(
      'pick-daily-highlight',
      body: {
        'highlights': payload,
        'context':    contextPayload,
      },
    );

    if (result.data != null) {
      final data = result.data is Map<String, dynamic>
          ? result.data as Map<String, dynamic>
          : jsonDecode(result.data as String) as Map<String, dynamic>;

      final idx = data['selectedIndex'];
      final selectedIndex = idx is int
          ? idx
          : int.tryParse(idx?.toString() ?? '');

      if (selectedIndex != null &&
          selectedIndex >= 0 &&
          selectedIndex < limited.length) {
        debugPrint('[DailyHL] Groq selected index $selectedIndex');
        return remember(limited[selectedIndex]);
      }
    }
  } catch (e) {
    debugPrint('[DailyHL] Edge Function error: $e');
  }

  // ── 5. Fallback: hour-seeded deterministic pick ────────────────────────────
  //
  // Changes every 3 hours (aligned to the timer above) and is stable within
  // that window even without network. Uses the same 3-hour bucket as the timer.

  debugPrint('[DailyHL] using hour-seeded fallback');
  final seed = now.year * 100000 + now.month * 1000 + now.day * 10 + (now.hour ~/ 3);
  return remember(all[seed % all.length]);
});
