// ─── Gender Service — platform barrel ─────────────────────────────────────────
//
// Persists the user-selected gender locally so the daily-phrase personalisation
// can gently tailor its tone. Mirrors LocaleService's "tiny file in the app docs
// dir" approach, split per-platform like HealthService:
//   • iOS/Android/Windows → gender_service_native.dart  (dart:io file)
//   • Web                 → gender_service_web.dart      (localStorage)
//
// PRIVACY: gender is PRIVACY-SENSITIVE special-category data. It is stored ONLY
// on-device and is NEVER uploaded to Supabase or any server. Valid values are
// 'female' | 'male' | 'unspecified'.

export 'gender_service_web.dart'
    if (dart.library.io) 'gender_service_native.dart';
