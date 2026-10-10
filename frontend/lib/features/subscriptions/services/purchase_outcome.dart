/// Outcome of a premium purchase or restore attempt.
library;

enum PurchaseFlowResult {
  /// The store confirmed the purchase; entitlement may still need a moment
  /// to propagate to the platform backend via webhook.
  success,

  /// The reader closed the store sheet without paying.
  cancelled,

  /// RevenueCat is not configured (no SDK key at build time). The in-store
  /// purchase flow cannot be offered, so the paywall falls back to
  /// explaining how premium is granted.
  notConfigured,

  /// The store rejected the attempt for a real reason.
  failure,
}

class PurchaseOutcome {
  const PurchaseOutcome({
    required this.result,
    this.message,
    this.entitledNow = false,
  });

  const PurchaseOutcome.success({this.entitledNow = false})
    : result = PurchaseFlowResult.success,
      message = null;

  const PurchaseOutcome.cancelled() : this(result: PurchaseFlowResult.cancelled);

  const PurchaseOutcome.notConfigured({this.message})
    : result = PurchaseFlowResult.notConfigured,
      entitledNow = false;

  const PurchaseOutcome.failure(this.message)
    : result = PurchaseFlowResult.failure,
      entitledNow = false;

  final PurchaseFlowResult result;
  final String? message;

  /// Whether RevenueCat reports the `premium` entitlement active already.
  final bool entitledNow;

  bool get success => result == PurchaseFlowResult.success;
  bool get cancelled => result == PurchaseFlowResult.cancelled;
  bool get notConfigured => result == PurchaseFlowResult.notConfigured;
}

/// Human-facing copy for the common failure modes.
abstract final class PremiumStoreMessages {
  static const missingOffering = 'No subscription plans are available yet. '
      'Please try again later.';
  static const noPackages = 'No purchasable plans were returned by the store. '
      'Please try again later.';
}