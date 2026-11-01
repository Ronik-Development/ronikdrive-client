import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

// Exact immutable base-plan IDs saved in Play Console. Product suffixes describe
// billing intervals; they are not necessarily the store's base-plan IDs.
const googlePlaySubscriptionBasePlanIds = <String, String>{
  'ronikdrive.basic.monthly': 'monthly',
  'ronikdrive.basic.yearly': 'basic-yearly',
  'ronikdrive.pro.monthly': 'pro-monthly',
  'ronikdrive.pro.yearly': 'pro-yearly',
  'ronikdrive.ultra.monthly': 'ultra-monthly',
  'ronikdrive.ultra.yearly': 'ultra-yearly',
};
final googlePlaySubscriptionProductIds = Set<String>.unmodifiable(
  googlePlaySubscriptionBasePlanIds.keys,
);

class GooglePlaySubscriptionProduct {
  const GooglePlaySubscriptionProduct({
    required this.id,
    required this.tier,
    required this.interval,
    required this.title,
    required this.capacity,
    required this.localizedPrice,
  });
  final String id;
  final String tier;
  final String interval;
  final String title;
  final String capacity;
  final String localizedPrice;
  bool get isYearly => interval == 'yearly';
  String get description => '$capacity of encrypted cloud storage.';
}

enum GooglePlayPurchasePhase {
  idle,
  loading,
  ready,
  purchasing,
  pending,
  verifying,
  restoring,
  complete,
  restored,
  canceled,
  error,
}

class GooglePlayPurchaseState {
  const GooglePlayPurchaseState({
    this.phase = GooglePlayPurchasePhase.idle,
    this.message,
    this.products = const [],
    this.hasExistingSubscription = false,
    this.currentProductId,
  });
  final GooglePlayPurchasePhase phase;
  final String? message;
  final List<GooglePlaySubscriptionProduct> products;
  final bool hasExistingSubscription;

  /// Present only for a single native owned purchase verified for this account.
  final String? currentProductId;
  bool get busy => switch (phase) {
    GooglePlayPurchasePhase.loading ||
    GooglePlayPurchasePhase.purchasing ||
    GooglePlayPurchasePhase.pending ||
    GooglePlayPurchasePhase.verifying ||
    GooglePlayPurchasePhase.restoring => true,
    _ => false,
  };
}

abstract class GooglePlayPurchaseApi {
  Stream<GooglePlayPurchaseState> get states;
  GooglePlayPurchaseState get currentState;
  Future<void> initialize();
  Future<void> purchase(String productId);
  Future<void> restorePurchases();
  Future<void> dispose();
}

typedef GooglePlayCallable =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, Object?> payload,
    );

/// Play is a payment source. Only the authenticated backend can grant storage;
/// neither a local purchase event nor a successful browser return unlocks it.
class FirebaseGooglePlayPurchaseApi implements GooglePlayPurchaseApi {
  FirebaseGooglePlayPurchaseApi({
    required FirebaseAuth auth,
    FirebaseFunctions? functions,
    InAppPurchase? store,
    GooglePlayCallable? callable,
    this.deadline = const Duration(seconds: 20),
  }) : _auth = auth,
       _ownerUid = auth.currentUser?.uid,
       _store = store ?? InAppPurchase.instance,
       _callableOverride = callable,
       _functions =
           functions ??
           (callable == null
               ? FirebaseFunctions.instanceFor(
                   app: auth.app,
                   region: 'europe-west1',
                 )
               : null) {
    _subscription = _store.purchaseStream.listen(
      (purchases) {
        final batch = List<PurchaseDetails>.of(purchases);
        _updates = _updates.then((_) => _handleUpdates(batch)).catchError((
          Object _,
        ) {
          _fail(
            'Google Play purchase updates could not be checked. Restore purchases to retry.',
          );
        });
      },
      onError: (Object _) {
        _fail(
          'Google Play purchase updates are unavailable. Restore purchases to retry.',
        );
      },
    );
  }

  factory FirebaseGooglePlayPurchaseApi.forApp(FirebaseApp app) =>
      FirebaseGooglePlayPurchaseApi(auth: FirebaseAuth.instanceFor(app: app));

  final FirebaseAuth _auth;
  final String? _ownerUid;
  final FirebaseFunctions? _functions;
  final InAppPurchase _store;
  final GooglePlayCallable? _callableOverride;
  final Duration deadline;
  final _states = StreamController<GooglePlayPurchaseState>.broadcast();
  final Map<String, GooglePlayProductDetails> _products = {};
  final Set<String> _completed = {};
  late final StreamSubscription<List<PurchaseDetails>> _subscription;
  Future<void> _updates = Future<void>.value();
  GooglePlayPurchaseState _state = const GooglePlayPurchaseState();
  String? _obfuscatedAccountId;
  bool _disposed = false;
  bool _operationInProgress = false;
  bool _ownedPurchasesChecked = false;
  final Set<String> _ownedProductIds = {};
  Timer? _purchaseStatusTimer;
  final Map<String, GooglePlayPurchaseDetails> _verifiedNativePurchases = {};
  bool get _hasExistingSubscription => _ownedProductIds.isNotEmpty;
  GooglePlayPurchaseDetails? get _replacementPurchase =>
      _ownedProductIds.length == 1
      ? _verifiedNativePurchases[_ownedProductIds.single]
      : null;

  @override
  Stream<GooglePlayPurchaseState> get states => _states.stream;
  @override
  GooglePlayPurchaseState get currentState => _state;

  void _requireOwner() {
    if (_disposed || _ownerUid == null || _auth.currentUser?.uid != _ownerUid) {
      throw const _GooglePlayAccountChanged();
    }
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> payload,
  ) async {
    _requireOwner();
    final override = _callableOverride;
    final Map<String, dynamic> data;
    if (override != null) {
      data = await override(name, payload).timeout(deadline);
    } else {
      final response = await _functions!
          .httpsCallable(name)
          .call(payload)
          .timeout(deadline);
      if (response.data is! Map) throw const FormatException();
      data = Map<String, dynamic>.from(response.data as Map);
    }
    _requireOwner();
    return data;
  }

  Future<void> _prepareAccount() async {
    _requireOwner();
    if (_obfuscatedAccountId != null) return;
    final data = await _call('prepareGooglePlayPurchase', const {});
    final account = data['obfuscatedAccountId'];
    if (account is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(account)) {
      throw const FormatException();
    }
    _obfuscatedAccountId = account;
  }

  @override
  Future<void> initialize() async {
    if (_disposed || _operationInProgress || _state.busy) return;
    _operationInProgress = true;
    _emit(
      GooglePlayPurchasePhase.loading,
      message: 'Loading Google Play subscriptions…',
    );
    try {
      _requireOwner();
      if (!await _store.isAvailable().timeout(deadline)) {
        _fail(
          'Google Play is unavailable on this device. You can keep using your current plan.',
        );
        return;
      }
      await _prepareAccount();
      final response = await _store
          .queryProductDetails(googlePlaySubscriptionProductIds)
          .timeout(deadline);
      _requireOwner();
      if (response.error != null) throw const FormatException();
      final products = <String, GooglePlayProductDetails>{};
      for (final product in response.productDetails) {
        if (product is! GooglePlayProductDetails ||
            !_isSupportedBasePlan(product)) {
          continue;
        }
        products.putIfAbsent(product.id, () => product);
      }
      _products
        ..clear()
        ..addAll(products);
      if (_products.isEmpty) {
        _fail(
          'Google Play subscriptions are not available yet. You can keep using your current plan.',
        );
        return;
      }
      await _checkOwnedPurchases();
      final visible = _products.values.map(_visibleProduct).toList()
        ..sort((a, b) {
          final tier = ['basic', 'pro', 'ultra']
              .indexOf(a.tier)
              .compareTo(['basic', 'pro', 'ultra'].indexOf(b.tier));
          return tier != 0 ? tier : a.interval.compareTo(b.interval);
        });
      // A purchase callback can arrive while the catalog request is pending.
      final loading = _state.phase == GooglePlayPurchasePhase.loading;
      _emit(
        loading ? GooglePlayPurchasePhase.ready : _state.phase,
        message: loading ? null : _state.message,
        products: visible,
      );
    } catch (error) {
      _handleFailure(
        error,
        'Google Play subscriptions could not be loaded. Check your connection and try again.',
      );
    } finally {
      _operationInProgress = false;
    }
  }

  bool _isSupportedBasePlan(GooglePlayProductDetails product) {
    if (!googlePlaySubscriptionProductIds.contains(product.id)) return false;
    final index = product.subscriptionIndex;
    final offers = product.productDetails.subscriptionOfferDetails;
    if (index == null ||
        offers == null ||
        index < 0 ||
        index >= offers.length) {
      return false;
    }
    final offer = offers[index];
    final interval = product.id.split('.').last;
    // This first release sells the ordinary recurring base plan. Introductory
    // offers need separate price/disclosure UI and are deliberately excluded.
    return offer.basePlanId == googlePlaySubscriptionBasePlanIds[product.id] &&
        offer.offerId == null &&
        offer.installmentPlanDetails == null &&
        product.offerToken?.isNotEmpty == true &&
        offer.pricingPhases.length == 1 &&
        offer.pricingPhases.single.recurrenceMode ==
            RecurrenceMode.infiniteRecurring &&
        offer.pricingPhases.single.billingPeriod ==
            (interval == 'yearly' ? 'P1Y' : 'P1M');
  }

  GooglePlaySubscriptionProduct _visibleProduct(
    GooglePlayProductDetails product,
  ) {
    final parts = product.id.split('.');
    final tier = parts[1];
    return GooglePlaySubscriptionProduct(
      id: product.id,
      tier: tier,
      interval: parts[2],
      title: switch (tier) {
        'basic' => 'Basic',
        'pro' => 'Pro',
        _ => 'Ultra',
      },
      capacity: switch (tier) {
        'basic' => '500 GB',
        'pro' => '1 TB',
        _ => '2 TB',
      },
      localizedPrice: product.price,
    );
  }

  @override
  Future<void> purchase(String productId) async {
    if (_disposed || _operationInProgress || _state.busy) return;
    final product = _products[productId];
    if (product == null || _obfuscatedAccountId == null) {
      _fail('Reload Google Play subscriptions before choosing a plan.');
      return;
    }
    _operationInProgress = true;
    _emit(GooglePlayPurchasePhase.purchasing, message: 'Opening Google Play…');
    try {
      _requireOwner();
      await _checkOwnedPurchases();
      final previous = _replacementPurchase;
      if (!_ownedPurchasesChecked ||
          (_hasExistingSubscription && previous == null)) {
        _fail(
          'An existing Google Play subscription was found. Manage it in Google Play before selecting another plan.',
        );
        return;
      }
      if (previous?.productID == productId) {
        _fail(
          'This is your current Google Play plan. Choose a different plan or manage renewal in Google Play.',
        );
        return;
      }
      _requireOwner();
      _emit(
        GooglePlayPurchasePhase.purchasing,
        message: 'Opening Google Play…',
      );
      final started = await _store
          .buyNonConsumable(
            purchaseParam: GooglePlayPurchaseParam(
              productDetails: product,
              applicationUserName: _obfuscatedAccountId,
              offerToken: product.offerToken,
              changeSubscriptionParam: previous == null
                  ? null
                  : ChangeSubscriptionParam(
                      oldPurchaseDetails: previous,
                      replacementMode: ReplacementMode.withTimeProration,
                    ),
            ),
          )
          .timeout(deadline);
      _requireOwner();
      if (!started) {
        _fail('Google Play could not open the purchase. Try again.');
      } else if (_state.phase == GooglePlayPurchasePhase.purchasing) {
        _purchaseStatusTimer?.cancel();
        _purchaseStatusTimer = Timer(deadline, () {
          if (_state.phase == GooglePlayPurchasePhase.purchasing) {
            _fail(
              'Google Play has not returned a purchase update. Restore purchases to check its status safely.',
            );
          }
        });
      }
    } catch (error) {
      _handleFailure(
        error,
        'Google Play could not start the purchase. Try again.',
      );
    } finally {
      _operationInProgress = false;
    }
  }

  @override
  Future<void> restorePurchases() async {
    if (_disposed ||
        _operationInProgress ||
        (_state.busy && _state.phase != GooglePlayPurchasePhase.pending)) {
      return;
    }
    _operationInProgress = true;
    _emit(
      GooglePlayPurchasePhase.restoring,
      message: 'Checking Google Play purchases…',
    );
    try {
      await _prepareAccount();
      await _checkOwnedPurchases();
      if (_state.phase == GooglePlayPurchasePhase.restoring) {
        _emit(
          GooglePlayPurchasePhase.ready,
          message:
              'No active Google Play purchases were found. Your current plan is unchanged.',
        );
      }
    } catch (error) {
      _handleFailure(
        error,
        'Google Play purchases could not be restored. Check your connection and try again.',
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> _checkOwnedPurchases() async {
    _requireOwner();
    // A fresh owned query must revalidate renewals and restored entitlements;
    // only duplicate delivery within that query shares a completed receipt.
    _completed.clear();
    // Never reuse an older verified replacement token after a failed refresh.
    _verifiedNativePurchases.clear();
    final snapshot = <String>{};
    var snapshotFailed = false;
    final collector = _store.purchaseStream.listen((purchases) {
      for (final purchase in purchases) {
        if (!googlePlaySubscriptionProductIds.contains(purchase.productID)) {
          continue;
        }
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored ||
            purchase.status == PurchaseStatus.pending) {
          snapshot.add(purchase.productID);
        } else if (purchase.status == PurchaseStatus.canceled) {
          snapshot.remove(purchase.productID);
        }
      }
    }, onError: (Object _) => snapshotFailed = true);
    try {
      await _store
          .restorePurchases(applicationUserName: _obfuscatedAccountId)
          .timeout(deadline);
      // The Android implementation publishes the complete owned-purchase batch
      // before returning. Drain it before allowing another payment. Keep
      // ownership even when backend verification rejects an existing receipt.
      await Future<void>.delayed(Duration.zero);
      await _updates.timeout(deadline);
      _requireOwner();
      if (snapshotFailed) throw const FormatException();
      _ownedProductIds
        ..clear()
        ..addAll(snapshot);
      _ownedPurchasesChecked = true;
      _emit(_state.phase, message: _state.message);
    } finally {
      await collector.cancel();
    }
  }

  Future<void> _handleUpdates(List<PurchaseDetails> purchases) async {
    if (_disposed) return;
    for (final purchase in purchases) {
      if (!googlePlaySubscriptionProductIds.contains(purchase.productID)) {
        continue;
      }
      if (_auth.currentUser?.uid != _ownerUid) {
        _handleFailure(const _GooglePlayAccountChanged(), '');
        return;
      }
      _purchaseStatusTimer?.cancel();
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _verifiedNativePurchases.remove(purchase.productID);
          _ownedProductIds.add(purchase.productID);
          _emit(
            GooglePlayPurchasePhase.pending,
            message:
                'Your Google Play payment is pending. Storage changes after payment is confirmed.',
          );
        case PurchaseStatus.canceled:
          _verifiedNativePurchases.remove(purchase.productID);
          _ownedProductIds.remove(purchase.productID);
          _emit(
            GooglePlayPurchasePhase.canceled,
            message:
                'The Google Play purchase was canceled. Your current plan is unchanged.',
          );
        case PurchaseStatus.error:
          _verifiedNativePurchases.remove(purchase.productID);
          _fail(
            'Google Play could not complete the purchase. Restore purchases to check its status.',
          );
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _ownedProductIds.add(purchase.productID);
          await _verifyAndComplete(purchase);
      }
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    final token = purchase.verificationData.serverVerificationData.trim();
    if (token.isEmpty ||
        token.length > 4096 ||
        purchase.verificationData.source != 'google_play') {
      _fail(
        'Google Play did not provide a valid purchase receipt. Restore purchases to retry.',
      );
      return;
    }
    final fingerprint = sha256
        .convert(utf8.encode('${purchase.productID}\u0000$token'))
        .toString();
    if (_completed.contains(fingerprint)) return;
    _verifiedNativePurchases.remove(purchase.productID);
    _emit(
      GooglePlayPurchasePhase.verifying,
      message: 'Confirming your Google Play subscription…',
    );
    try {
      final result = await _call('verifyGooglePlayPurchase', {
        'productId': purchase.productID,
        'purchaseToken': token,
      });
      if (result['accepted'] != true) throw const FormatException();
      _requireOwner();
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase).timeout(deadline);
      }
      _requireOwner();
      _completed.add(fingerprint);
      if (purchase is GooglePlayPurchaseDetails &&
          purchase.billingClientPurchase.purchaseState ==
              PurchaseStateWrapper.purchased &&
          purchase.billingClientPurchase.products.length == 1 &&
          purchase.billingClientPurchase.products.single ==
              purchase.productID &&
          purchase.billingClientPurchase.purchaseToken == token) {
        _verifiedNativePurchases[purchase.productID] = purchase;
      }
      final restored = purchase.status == PurchaseStatus.restored;
      _emit(
        restored
            ? GooglePlayPurchasePhase.restored
            : GooglePlayPurchasePhase.complete,
        message: restored
            ? 'Your Google Play subscription was restored.'
            : 'Subscription confirmed. Your workspace is updating…',
      );
    } catch (error) {
      _handleFailure(
        error,
        'Your Google Play purchase could not be verified yet. Restore purchases to retry safely.',
      );
    }
  }

  void _handleFailure(Object error, String fallback) {
    final message = error is _GooglePlayAccountChanged
        ? 'Your sign-in changed. Open subscriptions again for the current account.'
        : error is FirebaseFunctionsException
        ? switch (error.code.toLowerCase().replaceAll('_', '-')) {
            'unauthenticated' =>
              'Sign in again before checking Google Play purchases.',
            'permission-denied' || 'already-exists' =>
              'This Google Play purchase cannot be applied to this account. Sign in to the account that made the purchase.',
            'failed-precondition' =>
              'Google Play has not confirmed an active subscription. Check payment status in Google Play, then restore purchases.',
            'resource-exhausted' =>
              'Purchase checks are temporarily busy. Wait briefly and restore purchases.',
            _ => fallback,
          }
        : fallback;
    _fail(message);
  }

  void _fail(String message) =>
      _emit(GooglePlayPurchasePhase.error, message: message);
  void _emit(
    GooglePlayPurchasePhase phase, {
    String? message,
    List<GooglePlaySubscriptionProduct>? products,
  }) {
    if (_disposed) return;
    _state = GooglePlayPurchaseState(
      phase: phase,
      message: message,
      products: products ?? _state.products,
      hasExistingSubscription: _hasExistingSubscription,
      currentProductId: _replacementPurchase?.productID,
    );
    _states.add(_state);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _purchaseStatusTimer?.cancel();
    await _subscription.cancel();
    await _states.close();
  }
}

class _GooglePlayAccountChanged implements Exception {
  const _GooglePlayAccountChanged();
}
