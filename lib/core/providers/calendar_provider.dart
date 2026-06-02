// ─── Calendar Provider ────────────────────────────────────────────────────────
//
// Exposes today's calendar event titles via Riverpod, mirroring
// health_provider's shape. Used by dailyHighlightProvider to enrich the
// "frase scelta per te" context. autoDispose + kept alive 10 min to avoid
// re-prompting / re-fetching on every screen transition.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/calendar_service.dart';

export '../services/calendar_service.dart' show CalendarSnapshot, CalendarEvent;

const _service = CalendarService();

final calendarSnapshotProvider =
    FutureProvider.autoDispose<CalendarSnapshot>((ref) async {
  final link = ref.keepAlive();
  Future.delayed(const Duration(minutes: 10), link.close);
  return _service.fetchTodayEvents();
});
