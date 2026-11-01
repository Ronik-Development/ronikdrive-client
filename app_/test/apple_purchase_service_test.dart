import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_storage/src/billing/apple_store_purchase_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}

class _Callable extends Fake implements HttpsCallable {
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async =>
      _Result<T>(
        {'appAccountToken': '00000000-0000-4000-8000-000000000001'} as T,
      );
}

class _Functions extends Fake implements FirebaseFunctions {
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _Callable();
}

class _Store extends Fake implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final available = Completer<bool>();
  int purchaseCalls = 0;
  bool startPurchase = true;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() => available.future;
  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async => ProductDetailsResponse(
    productDetails: [
      ProductDetails(
        id: appleBasicMonthlyProductId,
        title: 'Basic',
        description: 'Storage',
        price: '€2.49',
        rawPrice: 2.49,
        currencyCode: 'EUR',
      ),
    ],
    notFoundIDs: [appleUltraYearlyProductId],
  );
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    purchaseCalls++;
    expect(purchaseParam.applicationUserName, isNotEmpty);
    return startPurchase;
  }
}

void main() {
  late _Store store;
  late FirebaseApplePurchaseApi api;
  setUp(() {
    store = _Store();
    api = FirebaseApplePurchaseApi(
      auth: MockFirebaseAuth(mockUser: MockUser(uid: 'buyer'), signedIn: true),
      functions: _Functions(),
      store: store,
    );
  });
  tearDown(() async {
    await api.dispose();
    await store.updates.close();
  });
  test(
    'available plans remain purchasable when another product is missing',
    () async {
      store.available.complete(true);
      await api.initialize();
      expect(api.currentState.phase, ApplePurchasePhase.ready);
      expect(api.currentState.products.single.id, appleBasicMonthlyProductId);
      await api.purchase(appleBasicMonthlyProductId);
      await api.purchase(appleBasicMonthlyProductId);
      expect(store.purchaseCalls, 1);
    },
  );
  test(
    'a purchase sheet that fails to open leaves a retryable error',
    () async {
      store.available.complete(true);
      store.startPurchase = false;
      await api.initialize();
      await api.purchase(appleBasicMonthlyProductId);
      expect(api.currentState.phase, ApplePurchasePhase.error);
      expect(api.currentState.busy, isFalse);
      expect(api.currentState.products, hasLength(1));
    },
  );
  test(
    'store unavailability is not mislabeled as a connection failure',
    () async {
      store.available.complete(false);
      await api.initialize();
      expect(api.currentState.phase, ApplePurchasePhase.error);
      expect(
        api.currentState.message,
        'The App Store is unavailable on this device. Try again later.',
      );
    },
  );
  test(
    'unknown purchase exceptions never expose their diagnostic message',
    () async {
      store.available.completeError(
        const ApplePurchaseException(
          'Bearer private-token for private@example.test',
        ),
      );
      await api.initialize();
      expect(
        api.currentState.message,
        'App Store subscriptions could not be loaded. Try again.',
      );
      expect(api.currentState.phase, ApplePurchasePhase.error);
    },
  );
  testWidgets('an unresponsive store stops loading after the deadline', (
    tester,
  ) async {
    final initializing = api.initialize();
    await tester.pump(const Duration(seconds: 21));
    await initializing;
    expect(api.currentState.phase, ApplePurchasePhase.error);
    expect(api.currentState.busy, isFalse);
  });
}
