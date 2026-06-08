// ─── Health Service — platform barrel ────────────────────────────────────────
//
// Exports the correct implementation depending on the platform:
//   • iOS/Android  → health_service_native.dart  (HealthKit / Health Connect)
//   • Web/Windows  → health_service_web.dart      (stub — returns empty data)
//
// ACTIVATION CHECKLIST (do when ready for App Store):
//   1. Add to pubspec.yaml dependencies:
//        health: ^10.2.0
//   2. Uncomment the import in health_service_native.dart
//   3. Enable HealthKit in Xcode (or codemagic.yaml):
//        Xcode → Target → Signing & Capabilities → + HealthKit
//   4. Add to ios/Runner/Info.plist (GDPR / App Store requirement):
//        <key>NSHealthShareUsageDescription</key>
//        <string>Scripta uses your step count and workout data to
//        personalize your daily reading highlight. This data is never
//        uploaded.</string>
//        <key>NSHealthUpdateUsageDescription</key>
//        <string>Scripta does not modify your health data.</string>
//   5. (Optional) For Codemagic — add to codemagic.yaml xcode_scheme or
//      entitlements: com.apple.developer.healthkit = true
//
// NOTE — GDPR Article 9 (special category health data):
//   Health data (steps, workouts, menstrual cycle) is processed entirely
//   on-device. It is never uploaded to Supabase or any third party.
//   The Info.plist strings above reflect this truthfully.

export 'health_service_web.dart'
    if (dart.library.io) 'health_service_native.dart';
