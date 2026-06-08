import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// ─── LocaleService ────────────────────────────────────────────────────────────
//
// Persists the user-selected locale code (e.g. "it", "en") to a tiny file
// in the app documents directory. Reads it back at startup so the app
// restores the last chosen language across sessions.
//
// Platform note: uses dart:io directly — fine for iOS, Android, Windows.
// Web has no onboarding language step, so this file is never called there.

class LocaleService {
  static const _filename = '.marginalia_locale';

  static const _supported = [Locale('it'), Locale('en')];

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_filename');
  }

  /// Returns the user's explicitly-chosen locale if one was stored; otherwise
  /// resolves the locale from the DEVICE language.
  ///
  /// Marginalia is English-predominant (international rollout), so a fresh
  /// install with no saved choice opens in English for everyone EXCEPT phones
  /// whose primary language is Italian — those open in Italian. Once the user
  /// picks a language (onboarding / settings) that choice is persisted and wins.
  static Future<Locale> getLocale() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final code = (await f.readAsString()).trim();
        final match = _supported.where((l) => l.languageCode == code).firstOrNull;
        if (match != null) return match;
      }
    } catch (_) {}
    return deviceDefault();
  }

  /// English-predominant device default: Italian only when the device's primary
  /// language is Italian, English in every other case. Pure + never throws, so
  /// it is safe to call from startup before the widget tree exists.
  static Locale deviceDefault() {
    try {
      final device = PlatformDispatcher.instance.locale;
      if (device.languageCode == 'it') return const Locale('it');
    } catch (_) {}
    return const Locale('en');
  }

  /// Persists the chosen locale code for future launches.
  static Future<void> setLocale(Locale locale) async {
    try {
      final f = await _file();
      await f.writeAsString(locale.languageCode);
    } catch (_) {}
  }
}
