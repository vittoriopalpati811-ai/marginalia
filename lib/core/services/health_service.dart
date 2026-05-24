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
//   4. Add to ios/Runner/Info.plist:
//        <key>NSHealthShareUsageDescription</key>
//        <string>Marginalia usa i tuoi dati di salute per personalizzare
//        gli highlight del giorno in base alla tua attività.</string>
//        <key>NSHealthUpdateUsageDescription</key>
//        <string>Marginalia non modifica i tuoi dati di salute.</string>
//   5. (Optional) For Codemagic — add to codemagic.yaml xcode_scheme or
//      entitlements: com.apple.developer.healthkit = true

export 'health_service_web.dart'
    if (dart.library.io) 'health_service_native.dart';
