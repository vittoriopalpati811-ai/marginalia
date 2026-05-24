// ─── Daily Highlight Provider ─────────────────────────────────────────────────
//
// Uses Groq (Llama 3.3 70B) via the `pick-daily-highlight` Edge Function to
// select the most contextually resonant highlight from the user's library.
//
// Context factors: time of day, weather, steps, workout, cycle phase.
//
// Falls back to a date-seeded deterministic pick if the Edge Function fails.
// Cached until midnight so Groq is called at most once per day.

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/highlight.dart';
import '../providers/auth_provider.dart';
import '../providers/highlights_provider.dart';
import '../providers/weather_provider.dart';
import '../providers/health_provider.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────

final dailyHighlightProvider = FutureProvider.autoDispose<Highlight?>((ref) async {
  // Cache until midnight — Groq is called at most once per day per session.
  final link = ref.keepAlive();
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day + 1);
  Future.delayed(midnight.difference(now), link.close);

  // ── 1. Get all highlights ──────────────────────────────────────────────────
  final List<Highlight> all;
  try {
    all = await ref.read(allHighlightsProvider.future);
  } catch (e) {
    debugPrint('[DailyHL] allHighlightsProvider error: $e');
    return null;
  }

  if (all.isEmpty) return null;

  // With fewer than 3 highlights there's no real choice to make — just return.
  if (all.length < 3) return all.first;

  // ── 2. Build a diverse sample (max 40 highlights sent to Groq) ────────────
  //
  // Prefer favorites (they carry stronger personal meaning) but include a
  // healthy mix of regular highlights so Groq has real variety to choose from.

  final favs   = all.where((h) => h.isFavorite).toList();
  final others = (all.where((h) => !h.isFavorite).toList()..shuffle());

  final sample = <Highlight>[
    ...favs.take(20),
    ...others.take(20),
  ]..shuffle();

  final limited = sample.take(40).toList();

  // ── 3. Collect context ─────────────────────────────────────────────────────

  final weather    = ref.read(weatherProvider).asData?.value;
  final healthSnap = ref.read(healthSnapshotProvider).asData?.value;

  final contextPayload = <String, dynamic>{
    'hour': now.hour,
    if (weather != null) ...{
      'weather':     weather.widgetParam,
      'weatherCity': weather.cityName,
      'weatherTemp': weather.temperatureRounded,
    },
    if (healthSnap != null && healthSnap.isAvailable) ...{
      if (healthSnap.stepsToday != null)
        'stepsToday': healthSnap.stepsToday,
      if (healthSnap.workoutsThisWeek.isNotEmpty)
        'lastWorkout': healthSnap.workoutsThisWeek.first.typeLabel,
      if (healthSnap.hasCycle && healthSnap.cyclePhase != null)
        'cyclePhase': healthSnap.cyclePhase!.name,
    },
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
        return limited[selectedIndex];
      }
    }
  } catch (e) {
    debugPrint('[DailyHL] Edge Function error: $e');
  }

  // ── 5. Fallback: deterministic date-seeded pick ────────────────────────────
  //
  // Changes every day but is stable within a day (same highlight shown
  // consistently even without network).

  debugPrint('[DailyHL] using date-seeded fallback');
  final seed = now.year * 10000 + now.month * 100 + now.day;
  return all[seed % all.length];
});
