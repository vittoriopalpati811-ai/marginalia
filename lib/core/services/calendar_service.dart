// ─── Calendar Service ─────────────────────────────────────────────────────────
//
// Reads TODAY's calendar event titles on-device (EventKit on iOS, Calendar
// Provider on Android) so they can flavour the "frase scelta per te" daily
// highlight. EventKit needs no entitlement / App-ID capability — only the
// NSCalendarsUsageDescription / NSCalendarsFullAccessUsageDescription strings
// in Info.plist + a runtime permission prompt.
//
// On web / Windows (and on any failure or denied permission) it returns an
// empty snapshot so callers degrade gracefully — the highlight selection just
// falls back to the other context signals (hour, weather, …).
//
// PRIVACY: event titles are used only as transient context for the on-device /
// edge-function highlight pick. They are never persisted.

import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:device_calendar/device_calendar.dart';

class CalendarSnapshot {
  const CalendarSnapshot({this.todayTitles = const []});

  /// Titles of events happening today (de-duplicated, max 5).
  final List<String> todayTitles;

  bool get isNotEmpty => todayTitles.isNotEmpty;
}

class CalendarService {
  const CalendarService();

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<CalendarSnapshot> fetchTodayEvents() async {
    if (!_supported) return const CalendarSnapshot();

    try {
      final plugin = DeviceCalendarPlugin();

      var permission = await plugin.hasPermissions();
      if (permission.data != true) {
        permission = await plugin.requestPermissions();
        if (permission.data != true) return const CalendarSnapshot();
      }

      final calendarsResult = await plugin.retrieveCalendars();
      final calendars = calendarsResult.data;
      if (calendars == null || calendars.isEmpty) {
        return const CalendarSnapshot();
      }

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));

      final seen = <String>{};
      final titles = <String>[];
      for (final calendar in calendars) {
        final id = calendar.id;
        if (id == null) continue;
        final events = await plugin.retrieveEvents(
          id,
          RetrieveEventsParams(startDate: start, endDate: end),
        );
        for (final event in events.data ?? const <Event>[]) {
          final title = event.title?.trim();
          if (title == null || title.isEmpty) continue;
          if (seen.add(title.toLowerCase())) titles.add(title);
          if (titles.length >= 5) return CalendarSnapshot(todayTitles: titles);
        }
      }
      return CalendarSnapshot(todayTitles: titles);
    } catch (e) {
      debugPrint('[Calendar] error: $e');
      return const CalendarSnapshot();
    }
  }
}
