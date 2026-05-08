import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../constants/product_catalog.dart';

/// Front door to all in-app purchases.  Wraps the `in_app_purchase` plugin
/// (StoreKit on iOS, Google Play Billing on Android) behind a single,
/// process-wide [ChangeNotifier] so the Shop screen — and any other surface
/// that needs to know about products, prices, or in-flight purchases — can
/// just listen to one source of truth.
///
/// Lifecycle: call [initialize] once at app boot.  After that, the service
/// owns the plugin's purchase stream and routes every update through
/// [_onPurchaseUpdates] → server-side `redeemPurchase` → store-side
/// `completePurchase`.  A purchase is only acknowledged once the Cloud
/// Function returns successfully — if the redeem call fails, the purchase
/// is left in `pendingCompletePurchase` so the store re-delivers it on
/// next app open and we retry, instead of a user paying for credits the
/// server never granted.
///
/// Receipt data (`verificationData.serverVerificationData`) is forwarded
/// to the CF unchanged; for now the CF only deduplicates by transaction
/// ID, but the full receipt is available so a later commit can layer in
/// proper App Store / Play Developer API validation without a client
/// change.
class BillingService extends ChangeNotifier {
  BillingService._();
  static final BillingService instance = BillingService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool _initialized = false;
  bool _isAvailable = false;
  bool _isLoadingProducts = false;
  Map<String, ProductDetails> _products = const {};
  final Set<String> _purchasingIds = <String>{};
  String? _lastError;

  /// True after [initialize] confirmed the store is reachable.  When false,
  /// the Shop should disable its real-purchase CTAs and surface a hint.
  bool get isAvailable => _isAvailable;

  /// True while the initial `queryProductDetails` round-trip is in flight.
  bool get isLoadingProducts => _isLoadingProducts;

  /// All products that resolved successfully on the last query.  IDs not
  /// configured in either store will be missing from this map; the Shop
  /// should fall back to [ProductDefinition.displayPrice] for those.
  Map<String, ProductDetails> get products => Map.unmodifiable(_products);

  /// True while the user-initiated purchase for [productId] is in flight
  /// (between [buy] being called and the purchase stream resolving with
  /// either a credit grant or a failure).
  bool isPurchasing(String productId) => _purchasingIds.contains(productId);

  /// Last user-visible error from any billing operation.  Cleared on the
  /// next successful action; the Shop reads this to show a toast.
  String? get lastError => _lastError;

  /// Wires up the plugin and loads product details from the store.  Safe
  /// to call multiple times — subsequent calls are no-ops.  On platforms
  /// where the store is unavailable (Linux, web, simulator without an
  /// account), [isAvailable] stays false and the rest of the API is
  /// inert; callers don't need to branch.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _isAvailable = await _iap.isAvailable();
    } catch (e) {
      debugPrint('[Billing] isAvailable threw: $e');
      _isAvailable = false;
    }
    notifyListeners();

    if (!_isAvailable) {
      debugPrint('[Billing] store unavailable; Shop will be inert');
      return;
    }

    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) {
        debugPrint('[Billing] purchase stream error: $e');
        _lastError = e.toString();
        notifyListeners();
      },
    );

    await _loadProducts();
  }

  /// Re-runs the product details query.  Used by the Shop's pull-to-refresh
  /// affordance and by any caller that wants a fresh snapshot of localised
  /// pricing (e.g. after the user changed their App Store region).
  Future<void> reloadProducts() async {
    if (!_isAvailable) return;
    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    _isLoadingProducts = true;
    _lastError = null;
    notifyListeners();

    try {
      final response = await _iap.queryProductDetails(ProductCatalog.allIds);
      _products = {for (final p in response.productDetails) p.id: p};
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
          '[Billing] products not found in store (configure in App Store '
          'Connect / Play Console): ${response.notFoundIDs}',
        );
      }
      if (response.error != null) {
        debugPrint('[Billing] product query error: ${response.error}');
        _lastError = response.error!.message;
      }
    } catch (e) {
      debugPrint('[Billing] product query threw: $e');
      _lastError = e.toString();
    }

    _isLoadingProducts = false;
    notifyListeners();
  }

  /// Kicks off a consumable purchase for [productId].  All the actual work
  /// happens asynchronously on the plugin's [purchaseStream] — the returned
  /// Future completes as soon as the OS purchase sheet is shown, not when
  /// the purchase is finalised.  Use [isPurchasing] / listen to this
  /// notifier to track completion.
  Future<void> buy(String productId) async {
    final product = _products[productId];
    if (product == null) {
      debugPrint('[Billing] buy($productId) — product not loaded');
      _lastError = 'Product unavailable. Please try again.';
      notifyListeners();
      return;
    }
    _purchasingIds.add(productId);
    _lastError = null;
    notifyListeners();

    try {
      final param = PurchaseParam(productDetails: product);
      await _iap.buyConsumable(purchaseParam: param);
    } catch (e) {
      debugPrint('[Billing] buyConsumable($productId) threw: $e');
      _purchasingIds.remove(productId);
      _lastError = e.toString();
      notifyListeners();
    }
  }

  /// Asks the store to re-deliver any past purchases that this device
  /// hasn't yet finished consuming.  Useful as a recovery affordance: if a
  /// user's redeem CF call failed mid-purchase, hitting Restore on the
  /// Shop will replay the pending transaction and re-attempt the redeem.
  Future<void> restore() async {
    if (!_isAvailable) return;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[Billing] restorePurchases threw: $e');
      _lastError = e.toString();
      notifyListeners();
    }
  }

  /// Single sink for plugin purchase updates.  Drives every state
  /// transition for an in-flight purchase: success → redeem → complete,
  /// failure → record error + complete (so the OS doesn't keep re-firing
  /// it), pending → wait for the next event.
  Future<void> _onPurchaseUpdates(List<PurchaseDetails> updates) async {
    for (final p in updates) {
      switch (p.status) {
        case PurchaseStatus.pending:
          // Still in flight on the OS side — wait for the next event.
          break;

        case PurchaseStatus.error:
          debugPrint(
            '[Billing] purchase error for ${p.productID}: ${p.error}',
          );
          _purchasingIds.remove(p.productID);
          _lastError = p.error?.message ?? 'Purchase failed';
          notifyListeners();
          if (p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }
          break;

        case PurchaseStatus.canceled:
          _purchasingIds.remove(p.productID);
          notifyListeners();
          if (p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final granted = await _redeem(p);
          _purchasingIds.remove(p.productID);
          if (granted && p.pendingCompletePurchase) {
            // Only acknowledge with the store after we've credited the
            // user.  If the redeem call failed, leaving the purchase
            // pending lets the OS re-deliver it on next launch so we can
            // retry — strictly better than acknowledging and losing it.
            await _iap.completePurchase(p);
          }
          notifyListeners();
          break;
      }
    }
  }

  /// Forwards a successful purchase to the `redeemPurchase` Cloud Function.
  /// Returns true on a 2xx response, false on any failure (which leaves
  /// the OS-side purchase pending so we can retry on the next app open).
  Future<bool> _redeem(PurchaseDetails p) async {
    try {
      final platform = Platform.isIOS || Platform.isMacOS ? 'apple' : 'google';
      await FirebaseFunctions.instance.httpsCallable('redeemPurchase').call(
        <String, dynamic>{
          'platform': platform,
          'productId': p.productID,
          'transactionId': p.purchaseID ?? '',
          'verificationSource': p.verificationData.source,
          'serverVerificationData':
              p.verificationData.serverVerificationData,
          'localVerificationData':
              p.verificationData.localVerificationData,
        },
      );
      return true;
    } catch (e) {
      debugPrint('[Billing] redeem CF failed for ${p.productID}: $e');
      _lastError =
          'Purchase succeeded but credits failed to apply. Pull to refresh '
          'or hit Restore on the Shop.';
      return false;
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}
