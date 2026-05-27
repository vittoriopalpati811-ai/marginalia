// Web onboarding state — persisted to localStorage so the user only sees
// the onboarding flow once per browser. Was previously a no-op stub that
// always returned true → onboarding never appeared on web.

// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

class OnboardingService {
  static const _key = 'marginalia.onboarding.complete';

  static Future<bool> isComplete() async {
    try {
      return html.window.localStorage[_key] == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> markComplete() async {
    try {
      html.window.localStorage[_key] = '1';
    } catch (_) {}
  }

  static Future<void> resetComplete() async {
    try {
      html.window.localStorage.remove(_key);
    } catch (_) {}
  }
}
