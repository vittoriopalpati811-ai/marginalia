// Web stub — purchases_flutter (RevenueCat) is not supported on Flutter web.
// All methods return safe defaults; subscriptions are managed on-device via StoreKit.

class SubscriptionService {
  static Future<void> configure() async {}

  static Future<void> logIn(String userId) async {}

  static Future<void> logOut() async {}

  /// Always returns false on web — premium is gated through the native app.
  static Future<bool> isPremium() async => false;

  static Future<bool> purchasePremium() async => false;

  static Future<bool> restorePurchases() async => false;
}
