import 'package:purchases_flutter/purchases_flutter.dart';

import 'premium_purchase_service.dart';
import 'purchase_outcome.dart';

/// RevenueCat-backed [PremiumPurchaseService].
///
/// Throws itself away into the "not configured" mode when no SDK key is
/// provided, so an app built without store keys still compiles, runs and
/// gates correctly — it just cannot complete a store purchase.
class RevenueCatPurchaseService implements PremiumPurchaseService {
  RevenueCatPurchaseService({required String apiKey}) : _apiKey = apiKey;

  final String _apiKey;
  bool _configured = false;

  @override
  bool get isConfigured => _apiKey.isNotEmpty;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    if (_apiKey.isEmpty) {
      throw const PremiumStoreNotConfiguredException();
    }
    await Purchases.configure(PurchasesConfiguration(_apiKey));
    _configured = true;
  }

  @override
  Future<void> identify(String appUserId) async {
    if (!isConfigured) return;
    await _ensureConfigured();
    await Purchases.logIn(appUserId);
  }

  @override
  Future<void> clearIdentity() async {
    if (!isConfigured) return;
    await _ensureConfigured();
    await Purchases.logOut();
  }

  @override
  Future<PurchaseOutcome> purchase() async {
    if (!isConfigured) {
      return const PurchaseOutcome.notConfigured();
    }
    try {
      await _ensureConfigured();
      final offerings = await Purchases.getOfferings();
      final offering = offerings.current;
      if (offering == null) {
        return const PurchaseOutcome.notConfigured(
          message: PremiumStoreMessages.missingOffering,
        );
      }
      final package = offering.monthly ?? offering.availablePackages.firstOrNull;
      if (package == null) {
        return const PurchaseOutcome.notConfigured(
          message: PremiumStoreMessages.noPackages,
        );
      }
      final result = await Purchases.purchase(
        PurchaseParams.package(package),
      );
      final entitledNow = result.customerInfo.entitlements.active
          .containsKey(entitlementId);
      return PurchaseOutcome.success(entitledNow: entitledNow);
    } on PurchasesError catch (e) {
      if (e.code == PurchasesErrorCode.purchaseCancelledError) {
        return const PurchaseOutcome.cancelled();
      }
      return PurchaseOutcome.failure('${e.message} (${e.code.name})');
    } on PremiumStoreNotConfiguredException {
      return const PurchaseOutcome.notConfigured();
    } catch (e) {
      return PurchaseOutcome.failure(e.toString());
    }
  }

  @override
  Future<PurchaseOutcome> restore() async {
    if (!isConfigured) {
      return const PurchaseOutcome.notConfigured();
    }
    try {
      await _ensureConfigured();
      final customerInfo = await Purchases.restorePurchases();
      final entitledNow = customerInfo.entitlements.active
          .containsKey(entitlementId);
      return PurchaseOutcome.success(entitledNow: entitledNow);
    } on PurchasesError catch (e) {
      return PurchaseOutcome.failure('${e.message} (${e.code.name})');
    } on PremiumStoreNotConfiguredException {
      return const PurchaseOutcome.notConfigured();
    } catch (e) {
      return PurchaseOutcome.failure(e.toString());
    }
  }
}

/// Identifies the `premium` entitlement the platform backend mirrors.
const entitlementId = 'premium';

/// Thrown when operations reach for the store without a configured SDK key.
class PremiumStoreNotConfiguredException implements Exception {
  const PremiumStoreNotConfiguredException();

  @override
  String toString() => 'PremiumStoreNotConfiguredException';
}