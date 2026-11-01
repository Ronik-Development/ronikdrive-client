import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import '../shared/user_facing_cloud_error.dart';
import '../shared/user_facing_client_failure.dart';

const String appleBasicMonthlyProductId =
    'com.ronikcloud.ronikdrive.subscription.basic.monthly';
const String appleBasicYearlyProductId =
    'com.ronikcloud.ronikdrive.subscription.basic.yearly';
const String appleProMonthlyProductId =
    'com.ronikcloud.ronikdrive.subscription.pro.monthly';
const String appleProYearlyProductId =
    'com.ronikcloud.ronikdrive.subscription.pro.yearly';
const String appleUltraMonthlyProductId =
    'com.ronikcloud.ronikdrive.subscription.ultra.monthly';
const String appleUltraYearlyProductId =
    'com.ronikcloud.ronikdrive.subscription.ultra.yearly';

const Set<String> appleSubscriptionProductIds = <String>{
  appleBasicMonthlyProductId,
  appleBasicYearlyProductId,
  appleProMonthlyProductId,
  appleProYearlyProductId,
  appleUltraMonthlyProductId,
  appleUltraYearlyProductId,
};

class AppleSubscriptionProduct {
  const AppleSubscriptionProduct({
    required this.id,
    required this.tier,
    required this.interval,
    required this.title,
    required this.description,
    required this.localizedPrice,
    required this.rawPrice,
  });

  final String id;
  final String tier;
  final String interval;
  final String title;
  final String description;
  final String localizedPrice;
  final double rawPrice;

  bool get isYearly => interval == 'yearly';
}

enum ApplePurchasePhase {
  idle,
  loading,
  ready,
  purchasing,
  pending,
  verifying,
  restoring,
  restored,
  complete,
  canceled,
  error,
}

class ApplePurchaseState {
  const ApplePurchaseState({
    required this.phase,
    this.message,
    this.products = const <AppleSubscriptionProduct>[],
  });

  const ApplePurchaseState.idle()
    : phase = ApplePurchasePhase.idle,
      message = null,
      products = const <AppleSubscriptionProduct>[];

  final ApplePurchasePhase phase;
  final String? message;
  final List<AppleSubscriptionProduct> products;

  bool get busy => switch (phase) {
    ApplePurchasePhase.loading ||
    ApplePurchasePhase.purchasing ||
    ApplePurchasePhase.pending ||
    ApplePurchasePhase.restoring ||
    ApplePurchasePhase.verifying => true,
    _ => false,
  };
}

abstract class ApplePurchaseApi {
  Stream<ApplePurchaseState> get states;

  ApplePurchaseState get currentState;

  Future<void> initialize();

  Future<void> purchase(String productId);

  Future<void> restorePurchases();

  Future<void> dispose();
}

typedef ApplePurchaseCallable =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, Object?> payload,
    );

class FirebaseApplePurchaseApi implements ApplePurchaseApi {
  FirebaseApplePurchaseApi({
    required FirebaseAuth auth,
    FirebaseFunctions? functions,
    InAppPurchase? store,
    ApplePurchaseCallable? callable,
    this.deadline = const Duration(seconds: 20),
    this.verificationDeadline = const Duration(seconds: 90),
  }) : _auth = auth,
       _ownerUid = auth.currentUser?.uid,
       _callableOverride = callable,
       _functions =
           functions ??
           (callable == null
               ? FirebaseFunctions.instanceFor(
                   app: auth.app,
                   region: 'europe-west1',
                 )
               : null),
       _store = store ?? InAppPurchase.instance {
    _purchaseSubscription = _store.purchaseStream.listen(
      (purchases) {
        final batch = List<PurchaseDetails>.of(purchases);
        if (batch.any(
          (purchase) =>
              appleSubscriptionProductIds.contains(purchase.productID),
        )) {
          _purchaseUpdateVersion++;
        }
        _updates = _updates
            .then((_) => _handlePurchaseUpdates(batch))
            .catchError(
              (Object _) => _fail(
                'App Store purchases could not be checked. Restore purchases to retry.',
              ),
            );
      },
      onError: (Object _) {
        _purchaseStatusTimer?.cancel();
        _fail(
          'App Store purchase updates are temporarily unavailable. Restore purchases to retry.',
        );
      },
    );
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user?.uid != _ownerUid) {
        _sessionChanged = true;
        _appAccountToken = null;
        _storeProducts.clear();
        _purchaseStatusTimer?.cancel();
        _fail(_accountChangedMessage);
      }
    });
  }

  factory FirebaseApplePurchaseApi.forApp(FirebaseApp app) {
    return FirebaseApplePurchaseApi(
      auth: FirebaseAuth.instanceFor(app: app),
      functions: FirebaseFunctions.instanceFor(
        app: app,
        region: 'europe-west1',
      ),
    );
  }

  final FirebaseAuth _auth;
  final String? _ownerUid;
  final FirebaseFunctions? _functions;
  final ApplePurchaseCallable? _callableOverride;
  final InAppPurchase _store;
  final Duration deadline;
  final Duration verificationDeadline;
  final StreamController<ApplePurchaseState> _stateController =
      StreamController<ApplePurchaseState>.broadcast();
  final Map<String, ProductDetails> _storeProducts = <String, ProductDetails>{};
  late final StreamSubscription<List<PurchaseDetails>> _purchaseSubscription;
  late final StreamSubscription<User?> _authSubscription;
  Future<void> _updates = Future<void>.value();
  final Set<String> _completedTransactions = {};
  Timer? _purchaseStatusTimer;

  ApplePurchaseState _currentState = const ApplePurchaseState.idle();
  String? _appAccountToken;
  bool _disposed = false;
  bool _sessionChanged = false;
  bool _operationInProgress = false;
  int _purchaseUpdateVersion = 0;

  static const _accountChangedMessage =
      'Your signed-in account changed. Reopen App Store subscriptions to continue.';

  @override
  Stream<ApplePurchaseState> get states => _stateController.stream;

  @override
  ApplePurchaseState get currentState => _currentState;

  void _requireOwner() {
    if (_disposed ||
        _sessionChanged ||
        _ownerUid == null ||
        _auth.currentUser?.uid != _ownerUid) {
      throw const _AppleAccountChanged();
    }
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> payload,
  ) async {
    _requireOwner();
    final verifying = name == 'verifyApplePurchase';
    final operationDeadline = verifying ? verificationDeadline : deadline;
    final override = _callableOverride;
    final Map<String, dynamic> data;
    if (override != null) {
      data = await override(name, payload).timeout(operationDeadline);
    } else {
      final response = await _functions!
          .httpsCallable(
            name,
            options: verifying
                ? HttpsCallableOptions(timeout: const Duration(seconds: 120))
                : null,
          )
          .call(payload)
          .timeout(operationDeadline);
      data = _map(response.data);
    }
    _requireOwner();
    return data;
  }

  void _fail(String message) {
    _emit(
      ApplePurchaseState(
        phase: ApplePurchasePhase.error,
        message: message,
        products: _currentState.products,
      ),
    );
  }

  @override
  Future<void> initialize() async {
    if (_disposed || _operationInProgress || _currentState.busy) {
      return;
    }
    _operationInProgress = true;
    _emit(
      const ApplePurchaseState(
        phase: ApplePurchasePhase.loading,
        message: 'Loading App Store subscriptions…',
      ),
    );

    final user = _auth.currentUser;
    if (user == null) {
      _emit(
        const ApplePurchaseState(
          phase: ApplePurchasePhase.error,
          message: 'Sign in before loading App Store subscriptions.',
        ),
      );
      _operationInProgress = false;
      return;
    }

    try {
      _requireOwner();
      final available = await _store.isAvailable().timeout(deadline);
      _requireOwner();
      if (!available) {
        throw const ApplePurchaseException(
          'The App Store is unavailable on this device. Try again later.',
          initializationFailure: AppleInitializationFailure.storeUnavailable,
        );
      }

      final preparedData = await _call('prepareApplePurchase', const {});
      final token = _string(preparedData['appAccountToken']);
      if (token == null ||
          !RegExp(
            r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
          ).hasMatch(token)) {
        throw const ApplePurchaseException(
          'The purchase service did not return an account token.',
          initializationFailure: AppleInitializationFailure.accountNotReady,
        );
      }
      _appAccountToken = token;

      final response = await _store
          .queryProductDetails(appleSubscriptionProductIds)
          .timeout(deadline);
      _requireOwner();
      if (response.error != null) {
        throw const ApplePurchaseException(
          'Unable to load App Store subscription details. Try again.',
          initializationFailure: AppleInitializationFailure.catalogUnavailable,
        );
      }
      final availableProducts = response.productDetails
          .where((product) => appleSubscriptionProductIds.contains(product.id))
          .toList(growable: false);
      if (availableProducts.isEmpty) {
        throw const ApplePurchaseException(
          'App Store subscriptions are not fully available yet. Try again later.',
          initializationFailure: AppleInitializationFailure.catalogEmpty,
        );
      }

      _storeProducts
        ..clear()
        ..addEntries(
          availableProducts.map(
            (product) => MapEntry<String, ProductDetails>(product.id, product),
          ),
        );
      final products =
          availableProducts.map(_toSubscriptionProduct).toList(growable: false)
            ..sort(_compareProducts);
      _emit(
        ApplePurchaseState(
          phase: _currentState.phase == ApplePurchasePhase.loading
              ? ApplePurchasePhase.ready
              : _currentState.phase,
          message: _currentState.phase == ApplePurchasePhase.loading
              ? null
              : _currentState.message,
          products: products,
        ),
      );
    } on _AppleAccountChanged {
      _fail(_accountChangedMessage);
    } on FirebaseFunctionsException catch (error) {
      _emit(
        ApplePurchaseState(
          phase: ApplePurchasePhase.error,
          message: userFacingCloudErrorMessage(
            operation: UserFacingCloudOperation.applePurchase,
            code: error.code,
          ),
        ),
      );
    } on ApplePurchaseException catch (error) {
      _emit(
        ApplePurchaseState(
          phase: ApplePurchasePhase.error,
          // These are our fixed, public messages, never provider diagnostics.
          message: switch (error.initializationFailure) {
            AppleInitializationFailure.storeUnavailable =>
              'The App Store is unavailable on this device. Try again later.',
            AppleInitializationFailure.accountNotReady =>
              'Your account is not ready for purchases yet. Try again shortly.',
            AppleInitializationFailure.catalogUnavailable =>
              'Unable to load App Store subscription details. Try again.',
            AppleInitializationFailure.catalogEmpty =>
              'App Store subscriptions are not fully available yet. Try again later.',
            null => 'App Store subscriptions could not be loaded. Try again.',
          },
        ),
      );
    } catch (_) {
      _emit(
        const ApplePurchaseState(
          phase: ApplePurchasePhase.error,
          message: 'Unable to load App Store subscriptions. Try again.',
        ),
      );
    } finally {
      _operationInProgress = false;
    }
  }

  @override
  Future<void> purchase(String productId) async {
    if (_disposed || _operationInProgress || _currentState.busy) return;
    try {
      _requireOwner();
    } on _AppleAccountChanged {
      _fail(_accountChangedMessage);
      return;
    }
    final product = _storeProducts[productId];
    final token = _appAccountToken;
    if (product == null || token == null) {
      _emit(
        ApplePurchaseState(
          phase: ApplePurchasePhase.error,
          message: 'Reload the App Store subscriptions before purchasing.',
          products: _currentState.products,
        ),
      );
      return;
    }
    _operationInProgress = true;
    _emit(
      ApplePurchaseState(
        phase: ApplePurchasePhase.purchasing,
        message: 'Opening the App Store purchase sheet…',
        products: _currentState.products,
      ),
    );
    try {
      // A successful sheet launch need not produce a callback (for example,
      // if StoreKit loses the connection). Keep Restore and retry reachable.
      _purchaseStatusTimer?.cancel();
      _purchaseStatusTimer = Timer(deadline, () {
        if (_currentState.phase == ApplePurchasePhase.purchasing) {
          _fail(
            'The App Store has not returned a purchase status. Restore purchases before trying again.',
          );
        }
      });
      final started = await _store
          .buyNonConsumable(
            purchaseParam: Sk2PurchaseParam(
              productDetails: product,
              applicationUserName: token,
            ),
          )
          .timeout(deadline);
      _requireOwner();
      if (!started) {
        throw const ApplePurchaseException(
          'The App Store did not start the purchase.',
        );
      }
    } on _AppleAccountChanged {
      _purchaseStatusTimer?.cancel();
      _fail(_accountChangedMessage);
    } catch (_) {
      _purchaseStatusTimer?.cancel();
      _emit(
        ApplePurchaseState(
          phase: ApplePurchasePhase.error,
          message: userFacingClientFailureMessage(
            UserFacingClientFailure.appStorePurchase,
          ),
          products: _currentState.products,
        ),
      );
    } finally {
      _operationInProgress = false;
    }
  }

  @override
  Future<void> restorePurchases() async {
    if (_disposed ||
        _operationInProgress ||
        (_currentState.busy &&
            _currentState.phase != ApplePurchasePhase.pending)) {
      return;
    }
    final token = _appAccountToken;
    if (token == null) {
      await initialize();
    }
    final resolvedToken = _appAccountToken;
    if (resolvedToken == null) {
      return;
    }
    _operationInProgress = true;
    _purchaseStatusTimer?.cancel();
    _emit(
      ApplePurchaseState(
        phase: ApplePurchasePhase.restoring,
        message: 'Restoring App Store purchases…',
        products: _currentState.products,
      ),
    );
    try {
      _requireOwner();
      await _updates.timeout(verificationDeadline);
      _requireOwner();
      // An explicit restore must revalidate even previously completed receipts:
      // their entitlement may have expired or been revoked since the last check.
      _completedTransactions.clear();
      final updateVersionBeforeRestore = _purchaseUpdateVersion;
      await _store
          .restorePurchases(applicationUserName: resolvedToken)
          .timeout(deadline);
      _requireOwner();
      // Drain callbacks queued before the native restore completed. StoreKit 2
      // also completes normally when currentEntitlements is empty.
      await Future<void>.delayed(Duration.zero);
      await _updates.timeout(verificationDeadline);
      _requireOwner();
      if (_purchaseUpdateVersion == updateVersionBeforeRestore) {
        _emit(
          ApplePurchaseState(
            phase: ApplePurchasePhase.ready,
            message:
                'Restore finished. No active App Store subscription was returned. You can manage your subscriptions with Apple.',
            products: _currentState.products,
          ),
        );
      }
    } on _AppleAccountChanged {
      _fail(_accountChangedMessage);
    } catch (_) {
      _emit(
        ApplePurchaseState(
          phase: ApplePurchasePhase.error,
          message: 'Unable to restore App Store purchases. Try again.',
          products: _currentState.products,
        ),
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    if (_disposed) return;
    for (final purchase in purchases) {
      _requireOwner();
      if (!appleSubscriptionProductIds.contains(purchase.productID)) {
        continue;
      }
      _purchaseStatusTimer?.cancel();
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _emit(
            ApplePurchaseState(
              phase: ApplePurchasePhase.pending,
              message:
                  'The purchase is pending approval or payment confirmation. You can restore purchases to check again or manage it with Apple.',
              products: _currentState.products,
            ),
          );
          continue;
        case PurchaseStatus.canceled:
          _emit(
            ApplePurchaseState(
              phase: ApplePurchasePhase.canceled,
              message: 'The App Store purchase was canceled.',
              products: _currentState.products,
            ),
          );
          continue;
        case PurchaseStatus.error:
          _emit(
            ApplePurchaseState(
              phase: ApplePurchasePhase.error,
              message: 'The App Store could not complete the purchase.',
              products: _currentState.products,
            ),
          );
          continue;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndComplete(purchase);
      }
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    _requireOwner();
    final signedTransaction = purchase.verificationData.serverVerificationData
        .trim();
    if (signedTransaction.isEmpty) {
      _emit(
        ApplePurchaseState(
          phase: ApplePurchasePhase.error,
          message:
              'The App Store did not provide signed transaction information.',
          products: _currentState.products,
        ),
      );
      return;
    }
    final fingerprint = sha256
        .convert(utf8.encode(signedTransaction))
        .toString();
    if (_completedTransactions.contains(fingerprint)) return;
    _emit(
      ApplePurchaseState(
        phase: ApplePurchasePhase.verifying,
        message: 'Verifying the App Store transaction…',
        products: _currentState.products,
      ),
    );
    try {
      final data = await _call('verifyApplePurchase', <String, Object?>{
        'signedTransaction': signedTransaction,
      });
      final verified =
          data['verified'] == true ||
          (!data.containsKey('verified') && data['accepted'] == true);
      if (!verified) {
        throw const ApplePurchaseException(
          'The server did not accept the App Store transaction.',
        );
      }
      _requireOwner();
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase).timeout(deadline);
      }
      _requireOwner();
      _completedTransactions.add(fingerprint);
      if (data['accepted'] != true) {
        _emit(
          ApplePurchaseState(
            phase: ApplePurchasePhase.ready,
            message:
                'This App Store transaction was verified, but there is no active App Store subscription. You can manage your subscriptions with Apple.',
            products: _currentState.products,
          ),
        );
        return;
      }
      final restored = purchase.status == PurchaseStatus.restored;
      _emit(
        ApplePurchaseState(
          phase: restored
              ? ApplePurchasePhase.restored
              : ApplePurchasePhase.complete,
          message: restored
              ? 'Your App Store subscription was restored.'
              : 'Subscription confirmed. Your workspace is unlocking…',
          products: _currentState.products,
        ),
      );
    } on _AppleAccountChanged {
      _fail(_accountChangedMessage);
    } on FirebaseFunctionsException catch (error) {
      _emit(
        ApplePurchaseState(
          phase: ApplePurchasePhase.error,
          message: userFacingCloudErrorMessage(
            operation: UserFacingCloudOperation.applePurchase,
            code: error.code,
          ),
          products: _currentState.products,
        ),
      );
    } on ApplePurchaseException {
      _emit(
        ApplePurchaseState(
          phase: ApplePurchasePhase.error,
          message: userFacingClientFailureMessage(
            UserFacingClientFailure.appStoreVerification,
          ),
          products: _currentState.products,
        ),
      );
    } catch (_) {
      _emit(
        ApplePurchaseState(
          phase: ApplePurchasePhase.error,
          message: 'Unable to verify the App Store transaction. Try again.',
          products: _currentState.products,
        ),
      );
    }
  }

  AppleSubscriptionProduct _toSubscriptionProduct(ProductDetails product) {
    final catalog = appleProductCatalogEntry(product.id);
    return AppleSubscriptionProduct(
      id: product.id,
      tier: catalog.tier,
      interval: catalog.interval,
      title: catalog.title,
      description: product.description.trim().isEmpty
          ? catalog.description
          : product.description.trim(),
      localizedPrice: product.price,
      rawPrice: product.rawPrice,
    );
  }

  void _emit(ApplePurchaseState state) {
    if (_disposed) {
      return;
    }
    final ownsSession =
        !_sessionChanged &&
        _ownerUid != null &&
        _auth.currentUser?.uid == _ownerUid;
    final safeState = ownsSession
        ? state
        : ApplePurchaseState(
            phase: ApplePurchasePhase.error,
            message: _ownerUid == null
                ? 'Sign in before loading App Store subscriptions.'
                : _accountChangedMessage,
          );
    _currentState = safeState;
    _stateController.add(safeState);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _purchaseStatusTimer?.cancel();
    _appAccountToken = null;
    _storeProducts.clear();
    _completedTransactions.clear();
    await _authSubscription.cancel();
    await _purchaseSubscription.cancel();
    await _stateController.close();
  }
}

class _AppleAccountChanged implements Exception {
  const _AppleAccountChanged();
}

class AppleProductCatalogEntry {
  const AppleProductCatalogEntry({
    required this.productId,
    required this.tier,
    required this.interval,
    required this.title,
    required this.description,
    required this.rank,
  });

  final String productId;
  final String tier;
  final String interval;
  final String title;
  final String description;
  final int rank;
}

const Map<String, AppleProductCatalogEntry> appleProductCatalog =
    <String, AppleProductCatalogEntry>{
      appleBasicMonthlyProductId: AppleProductCatalogEntry(
        productId: appleBasicMonthlyProductId,
        tier: 'basic',
        interval: 'monthly',
        title: 'Basic',
        description: '500 GB of encrypted cloud storage.',
        rank: 3,
      ),
      appleBasicYearlyProductId: AppleProductCatalogEntry(
        productId: appleBasicYearlyProductId,
        tier: 'basic',
        interval: 'yearly',
        title: 'Basic',
        description: '500 GB of encrypted cloud storage.',
        rank: 3,
      ),
      appleProMonthlyProductId: AppleProductCatalogEntry(
        productId: appleProMonthlyProductId,
        tier: 'pro',
        interval: 'monthly',
        title: 'Pro',
        description: '1 TB of storage with collaboration features.',
        rank: 2,
      ),
      appleProYearlyProductId: AppleProductCatalogEntry(
        productId: appleProYearlyProductId,
        tier: 'pro',
        interval: 'yearly',
        title: 'Pro',
        description: '1 TB of storage with collaboration features.',
        rank: 2,
      ),
      appleUltraMonthlyProductId: AppleProductCatalogEntry(
        productId: appleUltraMonthlyProductId,
        tier: 'ultra',
        interval: 'monthly',
        title: 'Ultra',
        description: '2 TB with advanced retention and priority support.',
        rank: 1,
      ),
      appleUltraYearlyProductId: AppleProductCatalogEntry(
        productId: appleUltraYearlyProductId,
        tier: 'ultra',
        interval: 'yearly',
        title: 'Ultra',
        description: '2 TB with advanced retention and priority support.',
        rank: 1,
      ),
    };

AppleProductCatalogEntry appleProductCatalogEntry(String productId) {
  final entry = appleProductCatalog[productId];
  if (entry == null) {
    throw ApplePurchaseException('Unknown App Store product: $productId');
  }
  return entry;
}

int _compareProducts(
  AppleSubscriptionProduct left,
  AppleSubscriptionProduct right,
) {
  final leftCatalog = appleProductCatalogEntry(left.id);
  final rightCatalog = appleProductCatalogEntry(right.id);
  final rankComparison = rightCatalog.rank.compareTo(leftCatalog.rank);
  if (rankComparison != 0) {
    return rankComparison;
  }
  return left.interval.compareTo(right.interval);
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry<String, dynamic>(key.toString(), item),
    );
  }
  return const <String, dynamic>{};
}

String? _string(dynamic value) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

enum AppleInitializationFailure {
  storeUnavailable,
  accountNotReady,
  catalogUnavailable,
  catalogEmpty,
}

class ApplePurchaseException implements Exception {
  const ApplePurchaseException(this.message, {this.initializationFailure});

  final AppleInitializationFailure? initializationFailure;

  final String message;

  @override
  String toString() => 'ApplePurchaseException';
}
