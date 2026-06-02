// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

// ─── GenderService — Web stub ─────────────────────────────────────────────────
//
// Persists the user-selected gender to localStorage, mirroring how LocaleService
// behaves on web. Same API as the native implementation.
//
// PRIVACY: stored ONLY in the browser's localStorage — never uploaded. Values
// are 'female' | 'male' | 'unspecified'.

class GenderService {
  static const _key = 'marginalia.gender';

  /// Returns the stored gender value (trimmed), or null if none is stored.
  static Future<String?> read() async {
    try {
      final value = html.window.localStorage[_key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {}
    return null;
  }

  /// Persists the chosen gender value for future launches.
  static Future<void> write(String value) async {
    try {
      html.window.localStorage[_key] = value;
    } catch (_) {}
  }
}
