import 'purchase_outcome.dart';

/// The store purchase seam for premium access.
///
/// The paywall talks to this interface, never to a vendor SDK directly, so the
/// UI is a plain Dart workflow and can be exercised in widget tests with a
/// fake. The RevenueCat-backed implementation is selected when an SDK key is
/// compiled in; otherwise a [DisabledPurchaseService] answers "not configured"
/// and the paywall explains how premium is granted instead of pretending to
/// open a store sheet.
abstract interface class PremiumPurchaseService {
  /// Whether an in-store purchase flow can actually run on this build.
  bool get isConfigured;

  /// Bind the platform account to the store customer (`revenuecat_app_user_id`
  /// on the backend: the user's database id). Idempotent; call before the
  /// first purchase so renewal webhooks resolve to the right account.
  Future<void> identify(String appUserId);

  /// Drop the store session when the reader signs out, so the next reader's
  /// purchases cannot land on the previous customer.
  Future<void> clearIdentity();

  /// Buy the default premium plan. Returns without throwing; failures are
  /// outcomes.
  Future<PurchaseOutcome> purchase();

  /// Restore already-purchased entitlements (new device / reinstall).
  Future<PurchaseOutcome> restore();
}

/// Store-less service used when no SDK key was provided at build time.
///
/// Keeps the app fully functional off the store shelves: gates render, the
/// backend status is the authority, and only the buy-flow itself is
/// unavailable, reported through [PurchaseOutcome.notConfigured].
class DisabledPurchaseService implements PremiumPurchaseService {
  const DisabledPurchaseService();

  @override
  bool get isConfigured => false;

  @override
  Future<void> identify(String appUserId) async {}

  @override
  Future<void> clearIdentity() async {}

  @override
  Future<PurchaseOutcome> purchase() =>
      Future.value(const PurchaseOutcome.notConfigured());

  @override
  Future<PurchaseOutcome> restore() =>
      Future.value(const PurchaseOutcome.notConfigured());
}