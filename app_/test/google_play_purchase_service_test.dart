import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_storage/src/billing/google_play_purchase_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

List<GooglePlayProductDetails> catalogProduct({
  String id = 'ronikdrive.basic.monthly',
  String? basePlan,
  String? offerId,
  String? period,
}) => GooglePlayProductDetails.fromProductDetails(
  ProductDetailsWrapper(
    description: 'Storage',
    name: 'Basic',
    title: 'Basic',
    productId: id,
    productType: ProductType.subs,
    subscriptionOfferDetails: [
      SubscriptionOfferDetailsWrapper(
        basePlanId:
            basePlan ?? googlePlaySubscriptionBasePlanIds[id] ?? 'unknown',
        offerId: offerId,
        offerTags: const [],
        offerIdToken: 'synthetic-offer-token',
        pricingPhases: [
          PricingPhaseWrapper(
            billingCycleCount: 0,
            billingPeriod: period ?? (id.endsWith('.yearly') ? 'P1Y' : 'P1M'),
            formattedPrice: '€2.49',
            priceAmountMicros: 2490000,
            priceCurrencyCode: 'EUR',
            recurrenceMode: RecurrenceMode.infiniteRecurring,
          ),
        ],
      ),
    ],
  ),
);

PurchaseDetails receipt({
  PurchaseStatus status = PurchaseStatus.purchased,
  String id = 'ronikdrive.basic.monthly',
  String token = 'synthetic-purchase-token',
}) => PurchaseDetails(
  productID: id,
  verificationData: PurchaseVerificationData(
    localVerificationData: 'private local receipt',
    serverVerificationData: token,
    source: 'google_play',
  ),
  transactionDate: '1000',
  status: status,
)..pendingCompletePurchase = true;

GooglePlayPurchaseDetails nativeReceipt({
  String id = 'ronikdrive.basic.monthly',
  String token = 'synthetic-native-token',
  PurchaseStatus status = PurchaseStatus.restored,
  PurchaseStateWrapper nativeState = PurchaseStateWrapper.purchased,
}) => GooglePlayPurchaseDetails(
  productID: id,
  verificationData: PurchaseVerificationData(
    localVerificationData: '{}',
    serverVerificationData: token,
    source: 'google_play',
  ),
  transactionDate: '1000',
  status: status,
  billingClientPurchase: PurchaseWrapper(
    orderId: 'synthetic-order',
    packageName: 'com.ronikcloud.ronikdrive',
    purchaseTime: 1000,
    purchaseToken: token,
    signature: 'synthetic-signature',
    products: [id],
    isAutoRenewing: true,
    originalJson: '{}',
    isAcknowledged: true,
    purchaseState: nativeState,
  ),
);

class _Store extends Fake implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  List<ProductDetails> products = catalogProduct();
  List<PurchaseDetails> owned = [];
  final events = <String>[];
  bool available = true;
  bool purchaseStarted = true;
  PurchaseParam? purchaseParam;
  int completed = 0;
  Object? restoreError;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async =>
      ProductDetailsResponse(productDetails: products, notFoundIDs: const []);
  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    events.add('restore');
    if (restoreError case final error?) throw error;
    updates.add(owned);
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    events.add('buy');
    this.purchaseParam = purchaseParam;
    return purchaseStarted;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    events.add('complete');
    completed++;
    purchase.pendingCompletePurchase = false;
  }
}

void main() {
  late _Store store;
  late MockFirebaseAuth auth;
  late FirebaseGooglePlayPurchaseApi api;
  late List<({String name, Map<String, Object?> payload})> calls;
  Completer<Map<String, dynamic>>? verification;
  Object? verificationError;
  var accepted = true;
  setUp(() {
    store = _Store();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'synthetic-buyer'),
      signedIn: true,
    );
    calls = [];
    verification = null;
    verificationError = null;
    accepted = true;
    api = FirebaseGooglePlayPurchaseApi(
      auth: auth,
      store: store,
      callable: (name, payload) async {
        calls.add((name: name, payload: Map.of(payload)));
        if (name == 'prepareGooglePlayPurchase') {
          return {'obfuscatedAccountId': 'a' * 64};
        }
        store.events.add('verify');
        if (verificationError case final error?) throw error;
        return verification?.future ?? Future.value({'accepted': accepted});
      },
    );
  });
  tearDown(() async {
    await api.dispose();
    await store.updates.close();
  });

  test(
    'six valid Play product IDs use localized ordinary base-plan prices',
    () async {
      expect(googlePlaySubscriptionProductIds, hasLength(6));
      expect(
        googlePlaySubscriptionProductIds.every((id) => id.length <= 40),
        isTrue,
      );
      store.products = [
        ...catalogProduct(offerId: 'intro'),
        ...catalogProduct(basePlan: 'unexpected'),
        ...catalogProduct(period: 'P3M'),
        ...catalogProduct(),
      ];
      await api.initialize();
      expect(api.currentState.phase, GooglePlayPurchasePhase.ready);
      expect(api.currentState.products.single.localizedPrice, '€2.49');
      expect(api.currentState.products.single.capacity, '500 GB');
      expect(calls.single.name, 'prepareGooglePlayPurchase');
      expect(calls.single.payload, isEmpty);
    },
  );
  test(
    'all six saved Console plans are selectable with their actual intervals',
    () async {
      final catalog =
          jsonDecode(
                File(
                  'test/fixtures/google_play_subscription_catalog.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final products = (catalog['products'] as List)
          .cast<Map<String, dynamic>>();
      expect(googlePlaySubscriptionBasePlanIds, {
        for (final product in products)
          product['productId'] as String: product['basePlanId'] as String,
      });
      store.products = [
        for (final product in products)
          ...catalogProduct(
            id: product['productId'] as String,
            basePlan: product['basePlanId'] as String,
            period: product['billingPeriod'] as String,
          ),
      ];
      await api.initialize();
      expect(api.currentState.phase, GooglePlayPurchasePhase.ready);
      expect(
        api.currentState.products.map((product) => product.id),
        unorderedEquals(products.map((product) => product['productId'])),
      );
      expect(
        api.currentState.products.where((product) => product.isYearly),
        hasLength(3),
      );
    },
  );
  test(
    'a product suffix cannot substitute for its saved base-plan ID',
    () async {
      store.products = [
        ...catalogProduct(),
        ...catalogProduct(id: 'ronikdrive.basic.yearly', basePlan: 'yearly'),
        ...catalogProduct(id: 'ronikdrive.pro.monthly', basePlan: 'monthly'),
        ...catalogProduct(id: 'ronikdrive.ultra.yearly', basePlan: 'yearly'),
      ];
      await api.initialize();
      expect(api.currentState.products.map((product) => product.id), [
        'ronikdrive.basic.monthly',
      ]);
    },
  );

  test(
    'purchase uses opaque account and offer tokens and cannot double-submit',
    () async {
      await api.initialize();
      await api.purchase('ronikdrive.basic.monthly');
      await api.purchase('ronikdrive.basic.monthly');
      expect(store.events.where((event) => event == 'buy'), hasLength(1));
      final parameters = store.purchaseParam as GooglePlayPurchaseParam;
      expect(parameters.applicationUserName, 'a' * 64);
      expect(parameters.offerToken, 'synthetic-offer-token');
      expect(
        parameters.applicationUserName,
        isNot(contains('synthetic-buyer')),
      );
    },
  );
  test('a missing purchase callback returns to a recoverable status', () async {
    await api.dispose();
    api = FirebaseGooglePlayPurchaseApi(
      auth: auth,
      store: store,
      deadline: const Duration(milliseconds: 100),
      callable: (name, payload) async => name == 'prepareGooglePlayPurchase'
          ? {'obfuscatedAccountId': 'a' * 64}
          : {'accepted': true},
    );
    await api.initialize();
    await api.purchase('ronikdrive.basic.monthly');
    expect(api.currentState.busy, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(api.currentState.busy, isFalse);
    expect(api.currentState.message, contains('Restore purchases'));
    await api.restorePurchases();
    expect(api.currentState.phase, GooglePlayPurchasePhase.ready);
  });
  test(
    'receipt verification must finish before Play purchase completion',
    () async {
      await api.initialize();
      verification = Completer<Map<String, dynamic>>();
      final verifying = api.states.firstWhere(
        (state) => state.phase == GooglePlayPurchasePhase.verifying,
      );
      store.updates.add([receipt()]);
      await verifying;
      expect(store.completed, 0);
      final complete = api.states.firstWhere(
        (state) => state.phase == GooglePlayPurchasePhase.complete,
      );
      verification!.complete({'accepted': true});
      await complete;
      expect(
        store.events.indexOf('verify'),
        lessThan(store.events.indexOf('complete')),
      );
      expect(calls.last.payload, {
        'productId': 'ronikdrive.basic.monthly',
        'purchaseToken': 'synthetic-purchase-token',
      });
    },
  );
  test('rejected verification never completes or unlocks a purchase', () async {
    await api.initialize();
    accepted = false;
    final failed = api.states.firstWhere(
      (state) => state.phase == GooglePlayPurchasePhase.error,
    );
    store.updates.add([receipt()]);
    await failed;
    expect(store.completed, 0);
    expect(api.currentState.message, contains('could not be verified'));
  });
  test(
    'pending and canceled purchases never reach backend verification',
    () async {
      await api.initialize();
      final pending = api.states.firstWhere(
        (state) => state.phase == GooglePlayPurchasePhase.pending,
      );
      store.updates.add([receipt(status: PurchaseStatus.pending)]);
      await pending;
      final canceled = api.states.firstWhere(
        (state) => state.phase == GooglePlayPurchasePhase.canceled,
      );
      store.updates.add([receipt(status: PurchaseStatus.canceled)]);
      await canceled;
      expect(
        calls.where((call) => call.name == 'verifyGooglePlayPurchase'),
        isEmpty,
      );
      expect(store.completed, 0);
      await api.purchase('ronikdrive.basic.monthly');
      expect(store.purchaseParam, isNotNull);
    },
  );
  test(
    'an empty restore returns to usable state instead of spinning',
    () async {
      await api.initialize();
      await api.restorePurchases();
      expect(api.currentState.busy, isFalse);
      expect(
        api.currentState.message,
        contains('No active Google Play purchases'),
      );
    },
  );
  test(
    'existing subscriptions are restored and never start another charge',
    () async {
      store.owned = [receipt(status: PurchaseStatus.restored)];
      await api.initialize();
      expect(api.currentState.phase, GooglePlayPurchasePhase.restored);
      expect(api.currentState.hasExistingSubscription, isTrue);
      await api.purchase('ronikdrive.basic.monthly');
      expect(store.purchaseParam, isNull);
      expect(api.currentState.message, contains('Manage it in Google Play'));
      expect(store.completed, 1);
    },
  );
  test('duplicate receipt callbacks verify and complete once', () async {
    await api.initialize();
    final complete = api.states.firstWhere(
      (state) => state.phase == GooglePlayPurchasePhase.complete,
    );
    store.updates.add([receipt(), receipt()]);
    await complete;
    await Future<void>.delayed(Duration.zero);
    expect(
      calls.where((call) => call.name == 'verifyGooglePlayPurchase'),
      hasLength(1),
    );
    expect(store.completed, 1);
  });
  test(
    'plan change replaces only the freshly verified native purchase',
    () async {
      final owned = nativeReceipt();
      store.owned = [owned];
      store.products = [
        ...catalogProduct(),
        ...catalogProduct(id: 'ronikdrive.pro.monthly'),
      ];
      await api.initialize();
      expect(api.currentState.currentProductId, owned.productID);
      await api.purchase('ronikdrive.pro.monthly');
      final parameters = store.purchaseParam as GooglePlayPurchaseParam;
      expect(parameters.productDetails.id, 'ronikdrive.pro.monthly');
      expect(
        parameters.changeSubscriptionParam?.oldPurchaseDetails,
        same(owned),
      );
      expect(
        parameters.changeSubscriptionParam?.replacementMode,
        ReplacementMode.withTimeProration,
      );
      expect(
        calls.where((call) => call.name == 'verifyGooglePlayPurchase'),
        hasLength(2),
      );
      expect(store.events.last, 'buy');
    },
  );
  test(
    'the current native plan never launches a duplicate subscription',
    () async {
      store.owned = [nativeReceipt()];
      await api.initialize();
      await api.purchase('ronikdrive.basic.monthly');
      expect(store.purchaseParam, isNull);
      expect(api.currentState.message, contains('current Google Play plan'));
    },
  );
  test(
    'denied account verification never supplies a replacement token',
    () async {
      store.owned = [nativeReceipt()];
      store.products = [
        ...catalogProduct(),
        ...catalogProduct(id: 'ronikdrive.pro.monthly'),
      ];
      verificationError = FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'private binding',
      );
      await api.initialize();
      expect(api.currentState.currentProductId, isNull);
      await api.purchase('ronikdrive.pro.monthly');
      expect(store.purchaseParam, isNull);
      expect(api.currentState.hasExistingSubscription, isTrue);
    },
  );
  test(
    'native pending ownership never qualifies for a plan replacement',
    () async {
      store.owned = [nativeReceipt(nativeState: PurchaseStateWrapper.pending)];
      store.products = [
        ...catalogProduct(),
        ...catalogProduct(id: 'ronikdrive.pro.monthly'),
      ];
      await api.initialize();
      expect(api.currentState.currentProductId, isNull);
      await api.purchase('ronikdrive.pro.monthly');
      expect(store.purchaseParam, isNull);
    },
  );
  test(
    'multiple owned subscriptions fail closed instead of choosing one to replace',
    () async {
      store.owned = [
        nativeReceipt(),
        nativeReceipt(
          id: 'ronikdrive.pro.monthly',
          token: 'another-owned-token',
        ),
      ];
      store.products = [
        ...catalogProduct(),
        ...catalogProduct(id: 'ronikdrive.ultra.monthly'),
      ];
      await api.initialize();
      expect(api.currentState.currentProductId, isNull);
      await api.purchase('ronikdrive.ultra.monthly');
      expect(store.purchaseParam, isNull);
    },
  );
  test(
    'a changed-plan receipt can be safely reverified after a transient failure',
    () async {
      store.owned = [nativeReceipt()];
      store.products = [
        ...catalogProduct(),
        ...catalogProduct(id: 'ronikdrive.pro.monthly'),
      ];
      await api.initialize();
      await api.purchase('ronikdrive.pro.monthly');
      accepted = false;
      final failed = api.states.firstWhere(
        (state) => state.phase == GooglePlayPurchasePhase.error,
      );
      final changed = nativeReceipt(
        id: 'ronikdrive.pro.monthly',
        token: 'replacement-token',
        status: PurchaseStatus.purchased,
      )..pendingCompletePurchase = true;
      store.updates.add([changed]);
      await failed;
      expect(store.completed, 0);
      accepted = true;
      store.owned = [changed];
      await api.restorePurchases();
      expect(store.completed, 1);
      expect(api.currentState.currentProductId, 'ronikdrive.pro.monthly');
      expect(api.currentState.hasExistingSubscription, isTrue);
    },
  );
  test('explicit restore revalidates previously completed receipts', () async {
    store.owned = [receipt(status: PurchaseStatus.restored)];
    await api.initialize();
    await api.restorePurchases();
    expect(
      calls.where((call) => call.name == 'verifyGooglePlayPurchase'),
      hasLength(2),
    );
    expect(api.currentState.phase, GooglePlayPurchasePhase.restored);
    expect(api.currentState.message, isNot(contains('No active')));
  });
  test('failed owned query retains existing subscription protection', () async {
    store.owned = [receipt(status: PurchaseStatus.restored)];
    await api.initialize();
    store.restoreError = StateError('private query failure');
    await api.restorePurchases();
    expect(api.currentState.hasExistingSubscription, isTrue);
    await api.purchase('ronikdrive.basic.monthly');
    expect(store.purchaseParam, isNull);
  });
  test(
    'a receipt that fails account verification still blocks a second charge',
    () async {
      store.owned = [receipt(status: PurchaseStatus.restored)];
      accepted = false;
      await api.initialize();
      expect(api.currentState.hasExistingSubscription, isTrue);
      await api.purchase('ronikdrive.basic.monthly');
      expect(store.purchaseParam, isNull);
      expect(store.completed, 0);
    },
  );
  test(
    'a successful empty owned query releases an expired subscription',
    () async {
      store.owned = [receipt(status: PurchaseStatus.restored)];
      await api.initialize();
      expect(api.currentState.hasExistingSubscription, isTrue);
      store.owned = [];
      await api.restorePurchases();
      expect(api.currentState.hasExistingSubscription, isFalse);
      await api.purchase('ronikdrive.basic.monthly');
      expect(store.purchaseParam, isNotNull);
    },
  );
  test(
    'pending payment can be checked again without restarting the page',
    () async {
      await api.initialize();
      final pending = api.states.firstWhere(
        (state) => state.phase == GooglePlayPurchasePhase.pending,
      );
      store.updates.add([receipt(status: PurchaseStatus.pending)]);
      await pending;
      await api.restorePurchases();
      expect(api.currentState.busy, isFalse);
      expect(api.currentState.hasExistingSubscription, isFalse);
    },
  );
  test('account change during verification suppresses completion', () async {
    await api.initialize();
    verification = Completer<Map<String, dynamic>>();
    final verifying = api.states.firstWhere(
      (state) => state.phase == GooglePlayPurchasePhase.verifying,
    );
    store.updates.add([receipt()]);
    await verifying;
    await auth.signOut();
    final failed = api.states.firstWhere(
      (state) => state.phase == GooglePlayPurchasePhase.error,
    );
    verification!.complete({'accepted': true});
    await failed;
    expect(store.completed, 0);
    expect(api.currentState.message, contains('sign-in changed'));
  });
  test(
    'backend failures use fixed messages without provider or receipt details',
    () async {
      await api.initialize();
      verificationError = FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Bearer secret-token private@example.test',
      );
      final failed = api.states.firstWhere(
        (state) => state.phase == GooglePlayPurchasePhase.error,
      );
      store.updates.add([receipt()]);
      await failed;
      expect(
        api.currentState.message,
        contains('account that made the purchase'),
      );
      expect(api.currentState.message, isNot(contains('secret-token')));
      expect(api.currentState.message, isNot(contains('private@example.test')));
      expect(store.completed, 0);
    },
  );
}
