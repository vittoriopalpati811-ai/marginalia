import 'dart:io';
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
  static const _default = Locale('it');

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_filename');
  }

  /// Returns the stored locale, or the default (Italian) if none is stored.
  static Future<Locale> getLocale() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final code = (await f.readAsString()).trim();
        final match = _supported.where((l) => l.languageCode == code).firstOrNull;
        if (match != null) return match;
      }
    } catch (_) {}
    return _default;
  }

  /// Persists the chosen locale code for future launches.
  static Future<void> setLocale(Locale locale) async {
    try {
      final f = await _file();
      await f.writeAsString(locale.languageCode);
    } catch (_) {}
  }
}
