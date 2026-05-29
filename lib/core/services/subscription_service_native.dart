// ─── SubscriptionService (native stub) ───────────────────────────────────────
//
// TEMPORARILY NEUTRALIZED — 2026-05-29.
//
// This file used to wrap RevenueCat's `purchases_flutter`. It has been reduced
// to a no-op stub (identical API surface to subscription_service_web.dart)
// because:
//   • The RevenueCat API key was never set — it was the literal placeholder
//     'REVENUECAT_PUBLIC_KEY_HERE', so every call was inert anyway.
//   • The paywall is explicitly NOT in the MVP (see CLAUDE.md §5).
//   • `purchases_flutter ^7.x` ships an old `PurchasesHybridCommon` pod whose
//     Swift source fails to compile against the Codemagic runner's Xcode 26.4
//     StoreKit SDK ("'SubscriptionPeriod' is ambiguous for type lookup"),
//     which broke the TestFlight `Build IPA` step (build #7, commit 4d0c51d).
//
// Removing the dependency drops the offending pod from the iOS build with zero
// loss of *functional* capability (the key was a placeholder).
//
// TO RESTORE when wiring a real paywall:
//   1. Un-comment `purchases_flutter` in pubspec.yaml (pick a version whose
//      bundled PurchasesHybridCommon compiles on the then-current Xcode).
//   2. Restore the original RevenueCat implementation of this file from git
//      history — it lives in every commit up to and including 4d0c51d
//      (`git show 4d0c51d:lib/core/services/subscription_service_native.dart`).
//   3. Replace the placeholder key + follow the dashboard.revenuecat.com
//      setup checklist that was in that original file.

class SubscriptionService {
  static Future<void> configure() async {}

  static Future<void> logIn(String userId) async {}

  static Future<void> logOut() async {}

  /// Always false while the paywall is disabled — premium is not gated yet.
  static Future<bool> isPremium() async => false;

  static Future<bool> purchasePremium() async => false;

  static Future<bool> restorePurchases() async => false;
}
