import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/subscription_status.dart';
import '../services/premium_purchase_service.dart';
import '../services/revenue_cat_purchase_service.dart';
import '../services/subscriptions_api_service.dart';
/// API service bound to the authenticated client.
///
/// `status/` is per-reader and the paywall renders whatever it answers, so
/// this must never fall back to the unauthenticated client — that route
/// would 401 and every gate would read as "locked".
final subscriptionsApiServiceProvider = Provider<SubscriptionsApiService>(
  (ref) {
    final apiClient = ref.watch(authenticatedApiClientProvider);
    return SubscriptionsApiService(dio: apiClient.dio);
  },
);

/// The store purchase seam.
///
/// Chosen at build time: a compiled-in `REVENUECAT_PUBLIC_SDK_KEY` gets the
/// RevenueCat implementation, otherwise a store-less placeholder that reports
/// "not configured". Tests override this provider with a fake.
final purchaseServiceProvider = Provider<PremiumPurchaseService>((ref) {
  const apiKey = String.fromEnvironment('REVENUECAT_PUBLIC_SDK_KEY');
  if (apiKey.isEmpty) {
    return const DisabledPurchaseService();
  }
  return RevenueCatPurchaseService(apiKey: apiKey);
});

/// The reader's premium status and feature access.
///
/// Watched by every gate and the paywall, so "did I just buy premium?" is one
/// refresh away from updating every locked control on screen.
final subscriptionProvider =
    AsyncNotifierProvider<SubscriptionNotifier, SubscriptionStatus>(
      SubscriptionNotifier.new,
    );

/// The current user's RevenueCat app-user id, when signed in.
///
/// Mirror of `subscriptions.services.revenuecat_app_user_id` on the backend:
/// the user's database id, nothing platform-specific.
final revenueCatAppUserIdProvider = Provider<String?>((ref) {
  final user = ref.watch(authProvider).valueOrNull?.user;
  return user == null ? null : '${user.id}';
});

class SubscriptionNotifier extends AsyncNotifier<SubscriptionStatus> {
  SubscriptionsApiService get _service =>
      ref.read(subscriptionsApiServiceProvider);

  @override
  Future<SubscriptionStatus> build() {
    // Scoped to the signed-in account: switching reader must re-read the
    // status, or the previous reader's entitlement would linger on the gates
    // until a manual refresh.
    ref.watch(authProvider.select((auth) => auth.valueOrNull?.user?.id));
    return _service.fetchStatus();
  }

  /// Re-read the status. Safe to call on pull-to-refresh and after a
  /// purchase/restore.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_service.fetchStatus);
  }

  /// Whether the account may use `key` right now.
  ///
  /// Loads and errors fail closed: while the status is unknown the gate shows
  /// *locked*, never an unlocked control that would bounce off the backend.
  bool hasAccess(String key) => state.valueOrNull?.hasAccess(key) ?? false;
}

/// The purchasable plans for the paywall shelf.
///
/// Fetched once and cached with the rest of the app's reads; a pricing change
/// is a server edit, so there is no local source to fall back to.
final plansProvider = FutureProvider<List<SubscriptionPlan>>((ref) {
  // Recomputed per account so a stale price list is not carried across
  // sign-outs, same rule as the status provider above.
  ref.watch(authProvider.select((auth) => auth.valueOrNull?.user?.id));
  return ref.watch(subscriptionsApiServiceProvider).fetchPlans();
});