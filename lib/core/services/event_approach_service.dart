// ─── Event Approach Service — platform barrel ─────────────────────────────────
//
// Persists how the user tends to feel before something on their calendar, used
// ONLY locally to tailor the daily-phrase tone when an event is coming up.
// Mirrors GenderService's "tiny file in the app docs dir" approach:
//   • iOS/Android/Windows → event_approach_service_native.dart  (dart:io file)
//   • Web                 → event_approach_service_web.dart      (localStorage)
//
// PRIVACY: stored ONLY on-device and NEVER uploaded. Valid values are
// 'calm' | 'focused' | 'anxious'.

export 'event_approach_service_web.dart'
    if (dart.library.io) 'event_approach_service_native.dart';
