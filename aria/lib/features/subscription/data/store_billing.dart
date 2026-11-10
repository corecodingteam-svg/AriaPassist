import 'dart:io';

import 'package:aria/features/subscription/domain/plan.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

enum PurchaseOutcome { purchased, cancelled, pending }

/// Play Billing / App Store purchases (via RevenueCat). Entitlement is
/// never decided here: the store → RevenueCat → webhook → Postgres path
/// updates the Circle's plan, which the app then syncs.
abstract interface class StoreBilling {
  bool get available;
  Future<void> identify(String userId);
  Future<PurchaseOutcome> purchase(
    Plan plan,
    BillingPeriod period, {
    required String circleId,
  });
  Future<void> restore();

  /// Store page to cancel / change payment method.
  Future<String?> managementUrl();
}

/// Builds without RevenueCat keys (dev, tests): store purchases are off;
/// trials and promo codes (server-side) still work.
class UnavailableStoreBilling implements StoreBilling {
  const UnavailableStoreBilling();
  @override
  bool get available => false;
  @override
  Future<void> identify(String userId) async {}
  @override
  Future<PurchaseOutcome> purchase(
    Plan plan,
    BillingPeriod period, {
    required String circleId,
  }) => throw StateError('Store purchases are not set up in this build');
  @override
  Future<void> restore() async {}
  @override
  Future<String?> managementUrl() async => null;
}

/// Products: `aria_<plan>_<month|year>`; RevenueCat offering id = plan code
/// with monthly/annual packages.
class RevenueCatStoreBilling implements StoreBilling {
  RevenueCatStoreBilling({required this.androidKey, required this.iosKey});
  final String androidKey;
  final String iosKey;
  bool _configured = false;

  String get _key => Platform.isIOS ? iosKey : androidKey;

  @override
  bool get available => _key.isNotEmpty;

  @override
  Future<void> identify(String userId) async {
    if (!available) return;
    if (!_configured) {
      await Purchases.configure(
        PurchasesConfiguration(_key)..appUserID = userId,
      );
      _configured = true;
    } else {
      await Purchases.logIn(userId);
    }
  }

  @override
  Future<PurchaseOutcome> purchase(
    Plan plan,
    BillingPeriod period, {
    required String circleId,
  }) async {
    // The webhook reads this to know which Circle the plan is for.
    await Purchases.setAttributes({'circle_id': circleId});
    final offerings = await Purchases.getOfferings();
    final offering = offerings.all[plan.code] ?? offerings.current;
    final want = 'aria_${plan.code}_${period.name}';
    final package = offering == null
        ? null
        : (period == BillingPeriod.month
                  ? offering.monthly
                  : offering.annual) ??
              offering.availablePackages
                  .where((p) => p.storeProduct.identifier.startsWith(want))
                  .firstOrNull;
    if (package == null) throw StateError('No store product for $want');
    try {
      await Purchases.purchase(PurchaseParams.package(package));
      return PurchaseOutcome.purchased;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseOutcome.cancelled;
      }
      if (code == PurchasesErrorCode.paymentPendingError) {
        return PurchaseOutcome.pending;
      }
      rethrow;
    }
  }

  @override
  Future<void> restore() async {
    if (available) await Purchases.restorePurchases();
  }

  @override
  Future<String?> managementUrl() async {
    if (!available) return null;
    try {
      return (await Purchases.getCustomerInfo()).managementURL;
    } on Object catch (e) {
      debugPrint('managementURL failed: $e');
      return null;
    }
  }
}
