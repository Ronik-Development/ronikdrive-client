import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_storage/src/billing/apple_store_purchase_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

const _accountToken = '00000000-0000-4000-8000-000000000001';

PurchaseDetails _receipt({
  PurchaseStatus status = PurchaseStatus.restored,
  String signed = 'synthetic-signed-transaction',
}) => PurchaseDetails(
  productID: appleBasicMonthlyProductId,
  verificationData: PurchaseVerificationData(
    localVerificationData: 'private-local-receipt',
    serverVerificationData: signed,
    source: 'app_store',
  ),
  transactionDate: '1000',
  status: status,
)..pendingCompletePurchase = true;

class _Auth extends Fake implements FirebaseAuth {
  User? user = MockUser(uid: 'buyer');
  final changes = StreamController<User?>.broadcast(sync: true);
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() => changes.stream;
  void change(User? next) {
    user = next;
    changes.add(next);
  }
}

class _Store extends Fake implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  List<PurchaseDetails> owned = [];
  int queried = 0;
  int bought = 0;
  int restored = 0;
  int completed = 0;
  Future<ProductDetailsResponse> Function()? query;
  Future<void> Function()? restore;
  Future<void> Function()? complete;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queried++;
    return query?.call() ??
        Future.value(
          ProductDetailsResponse(
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
            notFoundIDs: const [],
          ),
        );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    bought++;
    expect(purchaseParam.applicationUserName, _accountToken);
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restored++;
    expect(applicationUserName, _accountToken);
    if (restore case final callback?) return callback();
    // This includes the empty batch emitted by some StoreKit versions.
    updates.add(owned);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed++;
    await complete?.call();
    purchase.pendingCompletePurchase = false;
  }
}

void main() {
  late _Auth auth;
  late _Store store;
  late FirebaseApplePurchaseApi api;
  late List<({String name, Map<String, Object?> payload})> calls;
  Future<Map<String, dynamic>> Function()? prepare;
  Future<Map<String, dynamic>> Function()? verify;
  var result = <String, dynamic>{'verified': true, 'accepted': true};
  FirebaseApplePurchaseApi createApi({
    Duration deadline = const Duration(seconds: 20),
    Duration verificationDeadline = const Duration(seconds: 90),
  }) => FirebaseApplePurchaseApi(
    auth: auth,
    store: store,
    deadline: deadline,
    verificationDeadline: verificationDeadline,
    callable: (name, payload) async {
      calls.add((name: name, payload: payload));
      if (name == 'prepareApplePurchase') {
        return prepare?.call() ??
            Future.value({'appAccountToken': _accountToken});
      }
      return verify?.call() ?? Future.value(result);
    },
  );
  setUp(() {
    auth = _Auth();
    store = _Store();
    calls = [];
    prepare = null;
    verify = null;
    result = {'verified': true, 'accepted': true};
    api = createApi();
  });
  tearDown(() async {
    await api.dispose();
    await store.updates.close();
    await auth.changes.close();
  });

  test(
    'restore with no callback settles without granting or removing storage',
    () async {
      store.restore = () async {};
      await api.initialize();
      await api.restorePurchases();
      expect(api.currentState.phase, ApplePurchasePhase.ready);
      expect(api.currentState.busy, isFalse);
      expect(
        api.currentState.message,
        contains('No active App Store subscription was returned'),
      );
      expect(store.completed, 0);
      expect(calls.map((call) => call.name), ['prepareApplePurchase']);
      expect(api.currentState.products, hasLength(1));
    },
  );

  test('empty restore batch settles and can be retried', () async {
    await api.initialize();
    await api.restorePurchases();
    await api.restorePurchases();
    expect(store.restored, 2);
    expect(api.currentState.busy, isFalse);
  });

  test(
    'authoritative verification can outlast the native operation deadline',
    () async {
      await api.dispose();
      api = createApi(
        deadline: const Duration(milliseconds: 20),
        verificationDeadline: const Duration(seconds: 1),
      );
      verify = () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return {'verified': true, 'accepted': true};
      };
      store.owned = [_receipt()];
      await api.initialize();
      await api.restorePurchases();
      expect(store.completed, 1);
      expect(api.currentState.phase, ApplePurchasePhase.restored);
    },
  );

  test(
    'restore awaits server verification and completion of native callbacks',
    () async {
      store.owned = [_receipt()];
      await api.initialize();
      await api.restorePurchases();
      expect(api.currentState.phase, ApplePurchasePhase.restored);
      expect(store.completed, 1);
      expect(calls.last.payload, {
        'signedTransaction': 'synthetic-signed-transaction',
      });
    },
  );

  for (final status in ['expired', 'revoked', 'upgraded']) {
    test(
      'owned $status transaction is finished without claiming active storage',
      () async {
        result = {'verified': true, 'accepted': false, 'status': status};
        store.owned = [_receipt()];
        await api.initialize();
        await api.restorePurchases();
        expect(store.completed, 1);
        expect(api.currentState.phase, ApplePurchasePhase.ready);
        expect(
          api.currentState.message,
          contains('no active App Store subscription'),
        );
        expect(api.currentState.message, isNot(contains('unlocking')));
      },
    );
  }

  for (final response in [
    <String, dynamic>{'accepted': false},
    <String, dynamic>{'verified': false, 'accepted': true},
  ]) {
    test(
      'unverified server response $response never finishes StoreKit',
      () async {
        result = response;
        store.owned = [_receipt()];
        await api.initialize();
        await api.restorePurchases();
        expect(store.completed, 0);
        expect(api.currentState.phase, ApplePurchasePhase.error);
      },
    );
  }

  test(
    'legacy accepted response still finishes an owned active purchase',
    () async {
      result = {'accepted': true};
      store.owned = [_receipt(status: PurchaseStatus.purchased)];
      await api.initialize();
      await api.restorePurchases();
      expect(store.completed, 1);
      expect(api.currentState.phase, ApplePurchasePhase.complete);
    },
  );

  test('duplicate batches are serialized and completed once', () async {
    final pending = Completer<Map<String, dynamic>>();
    verify = () => pending.future;
    await api.initialize();
    store.updates.add([_receipt()]);
    store.updates.add([_receipt()]);
    await Future<void>.delayed(Duration.zero);
    expect(
      calls.where((call) => call.name == 'verifyApplePurchase'),
      hasLength(1),
    );
    expect(store.completed, 0);
    pending.complete({'verified': true, 'accepted': true});
    await Future<void>.delayed(Duration.zero);
    expect(store.completed, 1);
    expect(
      calls.where((call) => call.name == 'verifyApplePurchase'),
      hasLength(1),
    );
  });

  test(
    'explicit restore revalidates completed receipts after expiry',
    () async {
      store.owned = [_receipt()];
      await api.initialize();
      await api.restorePurchases();
      result = {'verified': true, 'accepted': false, 'status': 'expired'};
      await api.restorePurchases();
      expect(
        calls.where((call) => call.name == 'verifyApplePurchase'),
        hasLength(2),
      );
      expect(api.currentState.phase, ApplePurchasePhase.ready);
      expect(
        api.currentState.message,
        contains('no active App Store subscription'),
      );
    },
  );

  test(
    'account change during preparation never caches or uses another account token',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      prepare = () => pending.future;
      final initializing = api.initialize();
      await Future<void>.delayed(Duration.zero);
      auth.change(MockUser(uid: 'other'));
      pending.complete({'appAccountToken': _accountToken});
      await initializing;
      await api.purchase(appleBasicMonthlyProductId);
      await api.restorePurchases();
      expect(store.queried, 0);
      expect(store.bought, 0);
      expect(store.restored, 0);
      expect(api.currentState.products, isEmpty);
      expect(api.currentState.message, contains('account changed'));
    },
  );

  test(
    'sign out and back in invalidates the previous purchase session',
    () async {
      await api.initialize();
      final original = auth.user;
      auth.change(null);
      auth.change(original);
      await api.purchase(appleBasicMonthlyProductId);
      expect(store.bought, 0);
      expect(api.currentState.message, contains('account changed'));
    },
  );

  test(
    'account change during product lookup cannot restore stale plans',
    () async {
      final pending = Completer<ProductDetailsResponse>();
      store.query = () => pending.future;
      final initializing = api.initialize();
      await Future<void>.delayed(Duration.zero);
      auth.change(MockUser(uid: 'other'));
      pending.complete(
        ProductDetailsResponse(productDetails: const [], notFoundIDs: const []),
      );
      await initializing;
      expect(api.currentState.products, isEmpty);
      expect(api.currentState.message, contains('account changed'));
    },
  );

  test(
    'account change during verification cannot complete or unlock purchase',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      verify = () => pending.future;
      store.owned = [_receipt()];
      await api.initialize();
      final restoring = api.restorePurchases();
      await Future<void>.delayed(Duration.zero);
      auth.change(MockUser(uid: 'other'));
      pending.complete({'verified': true, 'accepted': true});
      await restoring;
      expect(store.completed, 0);
      expect(api.currentState.phase, ApplePurchasePhase.error);
      expect(api.currentState.message, contains('account changed'));
    },
  );

  test(
    'account change while finishing suppresses the previous success state',
    () async {
      final finishing = Completer<void>();
      store.complete = () => finishing.future;
      store.owned = [_receipt()];
      await api.initialize();
      final restoring = api.restorePurchases();
      await Future<void>.delayed(Duration.zero);
      expect(store.completed, 1);
      auth.change(MockUser(uid: 'other'));
      finishing.complete();
      await restoring;
      expect(api.currentState.phase, ApplePurchasePhase.error);
      expect(api.currentState.message, contains('account changed'));
    },
  );

  test('disposed preparation cannot perform later store operations', () async {
    final pending = Completer<Map<String, dynamic>>();
    prepare = () => pending.future;
    final initializing = api.initialize();
    await Future<void>.delayed(Duration.zero);
    await api.dispose();
    pending.complete({'appAccountToken': _accountToken});
    await initializing;
    expect(store.queried, 0);
  });

  test(
    'pending approval can be refreshed instead of trapping the page',
    () async {
      await api.initialize();
      store.updates.add([_receipt(status: PurchaseStatus.pending)]);
      await Future<void>.delayed(Duration.zero);
      expect(api.currentState.phase, ApplePurchasePhase.pending);
      await api.restorePurchases();
      expect(store.restored, 1);
      expect(api.currentState.busy, isFalse);
    },
  );

  test(
    'verification failure preserves the transaction for a successful restore retry',
    () async {
      verify = () async => throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'private-token private@example.test',
      );
      store.owned = [_receipt()];
      await api.initialize();
      await api.restorePurchases();
      expect(store.completed, 0);
      expect(api.currentState.message, isNot(contains('private')));
      verify = null;
      await api.restorePurchases();
      expect(store.completed, 1);
      expect(api.currentState.phase, ApplePurchasePhase.restored);
    },
  );

  test('unresponsive restore has a deadline and remains retryable', () async {
    await api.dispose();
    api = createApi(deadline: const Duration(milliseconds: 50));
    await api.initialize();
    store.restore = () => Completer<void>().future;
    await api.restorePurchases();
    expect(api.currentState.phase, ApplePurchasePhase.error);
    expect(api.currentState.busy, isFalse);
    store.restore = () async {};
    await api.restorePurchases();
    expect(store.restored, 2);
    expect(api.currentState.phase, ApplePurchasePhase.ready);
  });

  test(
    'missing purchase callback stops the spinner after the deadline',
    () async {
      await api.dispose();
      api = createApi(deadline: const Duration(milliseconds: 50));
      await api.initialize();
      await api.purchase(appleBasicMonthlyProductId);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.currentState.phase, ApplePurchasePhase.error);
      expect(api.currentState.busy, isFalse);
      expect(api.currentState.message, contains('Restore purchases'));
    },
  );

  test(
    'unresponsive receipt verification can be retried after its deadline',
    () async {
      await api.dispose();
      api = createApi(verificationDeadline: const Duration(milliseconds: 50));
      await api.initialize();
      verify = () => Completer<Map<String, dynamic>>().future;
      store.owned = [_receipt()];
      await api.restorePurchases();
      expect(store.completed, 0);
      expect(api.currentState.busy, isFalse);
      verify = null;
      await api.restorePurchases();
      expect(store.completed, 1);
      expect(api.currentState.phase, ApplePurchasePhase.restored);
    },
  );
}
