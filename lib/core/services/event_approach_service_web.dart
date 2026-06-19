// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

// ─── EventApproachService — Web stub ──────────────────────────────────────────
//
// Persists how the user tends to feel before a scheduled event to localStorage,
// mirroring GenderService on web. Same API as the native implementation.
//
// PRIVACY: stored ONLY in the browser's localStorage — never uploaded. Values
// are 'calm' | 'focused' | 'anxious'.

class EventApproachService {
  static const _key = 'marginalia.event_approach';

  /// Returns the stored value (trimmed), or null if none is stored.
  static Future<String?> read() async {
    try {
      final value = html.window.localStorage[_key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {}
    return null;
  }

  /// Persists the chosen value for future launches.
  static Future<void> write(String value) async {
    try {
      html.window.localStorage[_key] = value;
    } catch (_) {}
  }
}
