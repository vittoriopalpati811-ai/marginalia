// ─── Weather Service ──────────────────────────────────────────────────────────
//
// Fetches current weather using:
//   1. ip-api.com  — IP-based geolocation (no permission, no key, works on web)
//   2. Open-Meteo  — Weather data (no API key, WMO codes)
//
// Both APIs are free and work from Dart `http` (already in pubspec).
// No geolocation permission is requested — coordinates come from IP.
// Accuracy: city-level, sufficient for weather and for the Scriptable widget.
//
// Dependencies: http (already in pubspec.yaml) ✓

import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

// ─── Data classes ─────────────────────────────────────────────────────────────

enum WeatherCondition {
  clear,   // sole
  cloudy,  // nuvoloso
  rain,    // pioggia
  snow,    // neve
  fog,     // nebbia
  storm,   // temporale
}

class WeatherData {
  const WeatherData({
    required this.condition,
    required this.conditionLabel,
    required this.temperatureCelsius,
    required this.cityName,
    required this.latitude,
    required this.longitude,
    required this.emoji,
    required this.widgetParam, // value passed to widget-highlight Edge Function
  });

  final WeatherCondition condition;
  final String conditionLabel;  // Italian label
  final double temperatureCelsius;
  final String cityName;
  final double latitude;
  final double longitude;
  final String emoji;
  final String widgetParam; // 'sunny' | 'rain' | 'cloudy' | 'snow' | 'clear'

  int get temperatureRounded => temperatureCelsius.round();

  @override
  String toString() =>
      'WeatherData($conditionLabel ${temperatureRounded}°C @ $cityName)';
}

// ─── Service ──────────────────────────────────────────────────────────────────

class WeatherService {
  const WeatherService();

  /// Fetch current weather. Returns null on any network error.
  Future<WeatherData?> fetchWeather() async {
    try {
      // Step 1: IP geolocation → lat, lon, city
      final geo = await _fetchGeoFromIp();
      if (geo == null) {
        debugPrint('[Weather] IP geolocation failed');
        return null;
      }

      // Step 2: Open-Meteo → weather code + temperature
      final weather = await _fetchOpenMeteo(geo.$1, geo.$2);
      if (weather == null) {
        debugPrint('[Weather] Open-Meteo fetch failed');
        return null;
      }

      final (lat, lon, city) = geo;
      final (wmoCode, tempC) = weather;

      final condition = _wmoToCondition(wmoCode);
      final result = WeatherData(
        condition:         condition,
        conditionLabel:    _italianLabel(condition),
        temperatureCelsius: tempC,
        cityName:          city,
        latitude:          lat,
        longitude:         lon,
        emoji:             _conditionEmoji(condition),
        widgetParam:       _widgetParam(condition),
      );

      debugPrint('[Weather] $result');
      return result;
    } catch (e, st) {
      debugPrint('[Weather] unexpected error: $e\n$st');
      return null;
    }
  }

  // ── Step 1: IP geolocation ────────────────────────────────────────────────
  // ip-api.com: free, 45 req/min, no key. Returns JSON with lat/lon/city.

  Future<(double lat, double lon, String city)?> _fetchGeoFromIp() async {
    try {
      final res = await http
          .get(Uri.parse(
              'http://ip-api.com/json?fields=lat,lon,city,status'))
          .timeout(const Duration(seconds: 6));

      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['status'] != 'success') return null;

      final lat  = (j['lat']  as num).toDouble();
      final lon  = (j['lon']  as num).toDouble();
      final city = j['city']  as String? ?? '';
      return (lat, lon, city);
    } catch (_) {
      return null;
    }
  }

  // ── Step 2: Open-Meteo ────────────────────────────────────────────────────
  // Completely free, no API key. Returns current weather_code + temperature.

  Future<(int wmoCode, double tempC)?> _fetchOpenMeteo(
      double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&current=weather_code,temperature_2m'
        '&timezone=auto',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final j       = jsonDecode(res.body) as Map<String, dynamic>;
      final current = j['current'] as Map<String, dynamic>?;
      if (current == null) return null;

      final wmo  = (current['weather_code'] as num?)?.toInt() ?? 0;
      final temp = (current['temperature_2m'] as num?)?.toDouble() ?? 0.0;
      return (wmo, temp);
    } catch (_) {
      return null;
    }
  }

  // ── WMO code → condition ──────────────────────────────────────────────────
  // WMO Weather Interpretation Codes (WW):
  // https://open-meteo.com/en/docs#weathervariables

  WeatherCondition _wmoToCondition(int code) {
    if (code == 0 || code == 1)                          return WeatherCondition.clear;
    if (code == 2 || code == 3)                          return WeatherCondition.cloudy;
    if (code >= 45 && code <= 48)                        return WeatherCondition.fog;
    if (code >= 51 && code <= 67)                        return WeatherCondition.rain;
    if (code >= 71 && code <= 77)                        return WeatherCondition.snow;
    if (code >= 80 && code <= 82)                        return WeatherCondition.rain;
    if (code >= 85 && code <= 86)                        return WeatherCondition.snow;
    if (code >= 95 && code <= 99)                        return WeatherCondition.storm;
    return WeatherCondition.clear;
  }

  String _italianLabel(WeatherCondition c) => switch (c) {
    WeatherCondition.clear  => 'Sereno',
    WeatherCondition.cloudy => 'Nuvoloso',
    WeatherCondition.rain   => 'Pioggia',
    WeatherCondition.snow   => 'Neve',
    WeatherCondition.fog    => 'Nebbia',
    WeatherCondition.storm  => 'Temporale',
  };

  String _conditionEmoji(WeatherCondition c) => switch (c) {
    WeatherCondition.clear  => '☀️',
    WeatherCondition.cloudy => '☁️',
    WeatherCondition.rain   => '🌧️',
    WeatherCondition.snow   => '❄️',
    WeatherCondition.fog    => '🌫️',
    WeatherCondition.storm  => '⛈️',
  };

  /// Maps to the values expected by the widget-highlight Edge Function.
  String _widgetParam(WeatherCondition c) => switch (c) {
    WeatherCondition.clear  => 'sunny',
    WeatherCondition.cloudy => 'cloudy',
    WeatherCondition.rain   => 'rain',
    WeatherCondition.snow   => 'snow',
    WeatherCondition.fog    => 'cloudy',
    WeatherCondition.storm  => 'rain',
  };
}
