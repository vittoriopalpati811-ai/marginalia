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

/// One of today's calendar events, with enough timing to reason about whether
/// it's coming up or already behind us.
class CalendarEvent {
  const CalendarEvent({required this.title, this.start, this.isAllDay = false});

  final String title;
  final DateTime? start; // null for all-day / undated events
  final bool isAllDay;
}

class CalendarSnapshot {
  const CalendarSnapshot({this.todayTitles = const [], this.events = const []});

  /// Titles of events happening today (de-duplicated, max 5).
  final List<String> todayTitles;

  /// Today's events with timing, earliest first (timed before all-day).
  final List<CalendarEvent> events;

  bool get isNotEmpty => todayTitles.isNotEmpty;

  /// The soonest event that starts AFTER [from] (a timed event still ahead).
  CalendarEvent? nextAfter(DateTime from) {
    for (final e in events) {
      if (!e.isAllDay && e.start != null && e.start!.isAfter(from)) return e;
    }
    return null;
  }

  /// The most recent timed event that already started by [from].
  CalendarEvent? lastBefore(DateTime from) {
    CalendarEvent? last;
    for (final e in events) {
      if (!e.isAllDay && e.start != null && !e.start!.isAfter(from)) last = e;
    }
    return last;
  }
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
      final collected = <CalendarEvent>[];
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
          if (!seen.add(title.toLowerCase())) continue; // de-dupe by title
          collected.add(CalendarEvent(
            title: title,
            start: event.start, // TZDateTime is a DateTime subclass
            isAllDay: event.allDay ?? false,
          ));
          if (collected.length >= 12) break;
        }
        if (collected.length >= 12) break;
      }

      // Earliest first; timed events before all-day; undated last.
      collected.sort((a, b) {
        if (a.isAllDay != b.isAllDay) return a.isAllDay ? 1 : -1;
        final sa = a.start, sb = b.start;
        if (sa == null && sb == null) return 0;
        if (sa == null) return 1;
        if (sb == null) return -1;
        return sa.compareTo(sb);
      });

      final titles = collected.take(5).map((e) => e.title).toList();
      return CalendarSnapshot(todayTitles: titles, events: collected);
    } catch (e) {
      debugPrint('[Calendar] error: $e');
      return const CalendarSnapshot();
    }
  }
}
