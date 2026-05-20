import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;

// ─── WidgetHighlight ─────────────────────────────────────────────────────────
//
// Snapshot of the highlight that was pushed to the iOS home screen widget.

class WidgetHighlight {
  final String text;
  final String bookTitle;
  final String author;
  final String timeGreeting; // "Buongiorno", "Buona sera", …
  final String weatherMood;  // "sunny" | "rain" | "cloudy" | "snow" | "clear"

  const WidgetHighlight({
    required this.text,
    required this.bookTitle,
    required this.author,
    required this.timeGreeting,
    required this.weatherMood,
  });
}

// ─── WidgetService ───────────────────────────────────────────────────────────
//
// Picks the best highlight for the current moment (time, day, weather) and
// writes it to the iOS home-screen widget via the home_widget package.
//
// App Group ID must match the one configured in Xcode for both the Runner
// target and the MarginaliaWidget extension target.

class WidgetService {
  static const _appGroupId = 'group.marginalia.widget';
  static const _iOSWidgetName = 'MarginaliaWidget';

  // ── Initialise ────────────────────────────────────────────────────────────

  static Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
    } catch (e) {
      // home_widget is a no-op on platforms that don't support it (e.g. Windows)
      debugPrint('[WidgetService] init skipped: $e');
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Select the best highlight and push it to the iOS home-screen widget.
  /// Returns the selected [WidgetHighlight] so the caller can preview it.
  static Future<WidgetHighlight?> update(
    List<Map<String, dynamic>> highlights,
  ) async {
    if (highlights.isEmpty) return null;

    final now = DateTime.now();
    final weather = await _fetchWeather();
    final best = _selectBest(highlights, now, weather);
    if (best == null) return null;

    final text = best['body'] as String? ?? '';
    final bookTitle = best['book_title'] as String? ?? '';
    final author = best['author'] as String? ?? '';
    final greeting = _greeting(now.hour);

    final snapshot = WidgetHighlight(
      text: text,
      bookTitle: bookTitle,
      author: author,
      timeGreeting: greeting,
      weatherMood: weather,
    );

    await _push(snapshot, now);
    return snapshot;
  }

  // ── Push to widget ────────────────────────────────────────────────────────

  static Future<void> _push(WidgetHighlight h, DateTime now) async {
    try {
      await HomeWidget.saveWidgetData<String>('w_text', _clip(h.text, 260));
      await HomeWidget.saveWidgetData<String>('w_book', h.bookTitle);
      await HomeWidget.saveWidgetData<String>('w_author', h.author);
      await HomeWidget.saveWidgetData<String>('w_greeting', h.timeGreeting);
      await HomeWidget.saveWidgetData<String>('w_weather', h.weatherMood);
      await HomeWidget.saveWidgetData<String>('w_updated', now.toIso8601String());
      await HomeWidget.updateWidget(iOSName: _iOSWidgetName);
    } catch (e) {
      debugPrint('[WidgetService] push failed: $e');
    }
  }

  // ── Highlight selection algorithm ─────────────────────────────────────────
  //
  // Each highlight is scored against keyword pools derived from:
  //   • time of day  (morning / work / afternoon / evening / night)
  //   • day of week  (weekday / weekend / Monday / Friday)
  //   • weather      (sunny / rain / cloudy / snow)
  //
  // Shorter highlights get a bonus — widget space is limited and a single
  // compact sentence lands better than a truncated long passage.

  static Map<String, dynamic>? _selectBest(
    List<Map<String, dynamic>> highlights,
    DateTime now,
    String weather,
  ) {
    final keywords = [
      ..._timeKeywords(now.hour),
      ..._dayKeywords(now.weekday),
      ..._weatherKeywords(weather),
    ];

    Map<String, dynamic>? best;
    int bestScore = -1;

    for (final h in highlights) {
      final text = (h['body'] as String? ?? '').toLowerCase();
      var score = 0;

      for (final kw in keywords) {
        if (text.contains(kw)) score++;
      }

      // Brevity bonus
      final len = text.length;
      if (len < 280) score += 3;
      if (len < 160) score += 4;

      if (score > bestScore) {
        bestScore = score;
        best = h;
      }
    }

    return best ?? highlights.first;
  }

  static List<String> _timeKeywords(int hour) {
    if (hour >= 5 && hour < 9) {
      return ['morning', 'begin', 'start', 'sun', 'light', 'dawn', 'fresh', 'hope', 'awake'];
    } else if (hour >= 9 && hour < 12) {
      return ['work', 'think', 'focus', 'learn', 'create', 'mind', 'idea', 'knowledge', 'build'];
    } else if (hour >= 12 && hour < 17) {
      return ['afternoon', 'moment', 'discover', 'read', 'page', 'story', 'time', 'world'];
    } else if (hour >= 17 && hour < 21) {
      return ['evening', 'reflect', 'memory', 'home', 'peace', 'rest', 'feel', 'heart', 'grateful'];
    } else {
      return ['night', 'dream', 'sleep', 'silence', 'quiet', 'dark', 'deep', 'secret', 'wonder'];
    }
  }

  static List<String> _dayKeywords(int weekday) {
    if (weekday >= 6) {
      // Weekend
      return ['leisure', 'rest', 'slow', 'calm', 'creative', 'explore', 'wander', 'free', 'play'];
    } else if (weekday == 1) {
      // Monday
      return ['begin', 'start', 'week', 'energy', 'motivation', 'goal', 'possible', 'new'];
    } else if (weekday == 5) {
      // Friday
      return ['end', 'done', 'celebrate', 'joy', 'tired', 'relief', 'earned', 'weekend'];
    } else {
      return ['focus', 'achieve', 'progress', 'discipline', 'routine', 'steady'];
    }
  }

  static List<String> _weatherKeywords(String weather) {
    switch (weather) {
      case 'rain':
        return ['rain', 'melancholy', 'quiet', 'inside', 'warm', 'comfort', 'still', 'grey'];
      case 'sunny':
        return ['sun', 'light', 'bright', 'joy', 'life', 'nature', 'walk', 'beautiful', 'open'];
      case 'cloudy':
        return ['grey', 'think', 'uncertain', 'change', 'cloud', 'wonder', 'soft'];
      case 'snow':
        return ['cold', 'winter', 'still', 'white', 'silence', 'pure', 'frozen'];
      default:
        return [];
    }
  }

  static String _greeting(int hour) {
    if (hour >= 5 && hour < 12) return 'Buongiorno';
    if (hour >= 12 && hour < 17) return 'Buon pomeriggio';
    if (hour >= 17 && hour < 21) return 'Buona sera';
    return 'Buona notte';
  }

  static String _clip(String text, int max) {
    if (text.length <= max) return text;
    return '${text.substring(0, max).trimRight()}…';
  }

  // ── Weather fetch ─────────────────────────────────────────────────────────
  //
  // wttr.in provides IP-based weather with no API key required.
  // Returns one of: "sunny" | "cloudy" | "rain" | "snow" | "clear"

  static Future<String> _fetchWeather() async {
    try {
      final res = await http
          .get(Uri.parse('https://wttr.in/?format=j1'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return 'clear';

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final conditions = json['current_condition'] as List<dynamic>;
      final code =
          int.tryParse(conditions.first['weatherCode'] as String? ?? '113') ??
              113;
      return _mapWeatherCode(code);
    } catch (_) {
      return 'clear';
    }
  }

  // wttr.in weather codes — subset of WMO codes
  static String _mapWeatherCode(int code) {
    if (code == 113) return 'sunny';           // Clear / Sunny
    if (code <= 119) return 'cloudy';          // Partly / Mostly cloudy
    if (code <= 260) return 'cloudy';          // Fog / Overcast
    if (code <= 350) return 'rain';            // Drizzle / Rain
    if (code <= 395) return 'snow';            // Snow / Sleet / Blizzard
    return 'clear';
  }
}
