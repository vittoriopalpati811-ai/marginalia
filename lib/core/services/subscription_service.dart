import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// ─── SubscriptionService ─────────────────────────────────────────────────────
//
// Thin wrapper around RevenueCat purchases_flutter.
//
// SETUP CHECKLIST (one-time, before first TestFlight build):
//   1. Create account at dashboard.revenuecat.com
//   2. Add iOS app → App Store Connect API key
//   3. Create Entitlement:  id = "premium"
//   4. Create Offering:     id = "default"
//   5. Create Package:      Annual, linked to App Store product "marginalia_premium_yearly"
//   6. Copy the PUBLIC API key (starts with "appl_") into [_apiKey] below
//   7. In App Store Connect → Subscriptions: create "marginalia_premium_yearly" €19.99/yr
//
// On Windows / web this service is a no-op stub (RevenueCat uses StoreKit).

class SubscriptionService {
  /// Your RevenueCat public API key.
  /// Replace with the real key from https://app.revenuecat.com/apps
  static const String _apiKey = 'REVENUECAT_PUBLIC_KEY_HERE';

  /// The entitlement you created in RevenueCat dashboard.
  static const String _entitlement = 'premium';

  // ── Platform guard ────────────────────────────────────────────────────────

  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Call once before runApp(), after WidgetsFlutterBinding.ensureInitialized().
  static Future<void> configure() async {
    if (!_supported) return;
    await Purchases.setLogLevel(
      kDebugMode ? LogLevel.debug : LogLevel.error,
    );
    await Purchases.configure(PurchasesConfiguration(_apiKey));
  }

  // ── Identity ─────────────────────────────────────────────────────────────

  /// Links RevenueCat identity to the logged-in Supabase user.
  /// Call after successful login so purchases are attributed correctly.
  static Future<void> logIn(String userId) async {
    if (!_supported) return;
    try {
      await Purchases.logIn(userId);
    } catch (_) {}
  }

  /// Resets to an anonymous RevenueCat identity on logout.
  static Future<void> logOut() async {
    if (!_supported) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }

  // ── Entitlement check ─────────────────────────────────────────────────────

  /// Returns true if the current user has an active "premium" entitlement.
  static Future<bool> isPremium() async {
    if (!_supported) return false; // all premium on desktop (dev convenience)
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(_entitlement);
    } catch (_) {
      return false;
    }
  }

  // ── Purchase ──────────────────────────────────────────────────────────────

  /// Triggers the StoreKit purchase sheet for the annual package.
  /// Returns true if the user is now premium.
  static Future<bool> purchasePremium() async {
    if (!_supported) return false;
    try {
      final offerings = await Purchases.getOfferings();
      // Prefer annual package; fall back to first available.
      final package = offerings.current?.annual ??
          offerings.current?.availablePackages.firstOrNull;
      if (package == null) return false;

      final info = await Purchases.purchasePackage(package);
      return info.customerInfo.entitlements.active.containsKey(_entitlement);
    } on PurchasesErrorCode catch (code) {
      // User cancelled — not an error worth surfacing.
      if (code == PurchasesErrorCode.purchaseCancelledError) return false;
      rethrow;
    } catch (_) {
      return false;
    }
  }

  // ── Restore ───────────────────────────────────────────────────────────────

  /// Restores previous purchases (required by App Store guidelines).
  /// Returns true if premium was restored.
  static Future<bool> restorePurchases() async {
    if (!_supported) return false;
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active.containsKey(_entitlement);
    } catch (_) {
      return false;
    }
  }
}
