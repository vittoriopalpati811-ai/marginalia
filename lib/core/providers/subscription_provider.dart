import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/subscription_service.dart';

// ─── SubscriptionNotifier ─────────────────────────────────────────────────────

class SubscriptionNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => SubscriptionService.isPremium();

  /// Opens the StoreKit purchase sheet.
  /// Returns true if the user is now premium.
  Future<bool> purchase() async {
    state = const AsyncValue.loading();
    try {
      final ok = await SubscriptionService.purchasePremium();
      state = AsyncValue.data(ok);
      return ok;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Restores previous App Store purchases.
  Future<bool> restore() async {
    state = const AsyncValue.loading();
    try {
      final ok = await SubscriptionService.restorePurchases();
      state = AsyncValue.data(ok);
      return ok;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Refreshes the entitlement status from RevenueCat.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await SubscriptionService.isPremium());
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final subscriptionProvider =
    AsyncNotifierProvider<SubscriptionNotifier, bool>(
  SubscriptionNotifier.new,
);

/// Convenience sync provider — false while loading / on error.
/// Use this for gate checks so they default to showing the paywall rather than
/// crashing on a null check.
final isPremiumProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionProvider).asData?.value ?? false;
});
