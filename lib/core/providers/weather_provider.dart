// ─── Weather Provider ─────────────────────────────────────────────────────────
//
// Provides current weather data (condition, temperature, city).
// Works on web and iOS — uses IP-based geolocation, no permissions required.
//
// Cache strategy: keepAlive for 30 min so the widget doesn't re-fetch on
// every scroll. The autoDispose timer is reset when the provider is re-watched.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/weather_service.dart';

export '../services/weather_service.dart' show WeatherData, WeatherCondition;

// Singleton service — stateless, can be shared.
final _weatherService = const WeatherService();

/// Current weather. Null if unavailable (no network, geolocation blocked).
/// Auto-refreshes when the cache is 30 minutes old.
final weatherProvider = FutureProvider.autoDispose<WeatherData?>((ref) async {
  // Keep the result alive for 30 min so scrolling doesn't re-trigger fetches.
  final link = ref.keepAlive();
  Future.delayed(const Duration(minutes: 30), link.close);

  return _weatherService.fetchWeather();
});

/// Convenience: just the widget-param string ('sunny', 'rain', etc.)
/// used by the Scriptable widget URL builder.
final weatherWidgetParamProvider = Provider.autoDispose<String>((ref) {
  final async = ref.watch(weatherProvider);
  return async.when(
    data:    (w) => w?.widgetParam ?? 'clear',
    loading: () => 'clear',
    error:   (_, __) => 'clear',
  );
});
