import 'dart:io';

import 'package:cloud_storage/src/billing/apple_store_purchase_service.dart';
import 'package:cloud_storage/src/billing/billing_channel.dart';
import 'package:cloud_storage/src/billing/subscription_coordinator.dart';
import 'package:cloud_storage/src/billing/subscription_gate.dart';
import 'package:cloud_storage/src/shared/subscription_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('billing failure hides details and retries in place', (
    tester,
  ) async {
    const privateDetail =
        'Bearer private-token for private@example.com at /srv/billing/customer';
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'billing-user', email: 'user@example.com');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final coordinator = _ErrorThenSuccessSubscriptionCoordinator(
      firestore: firestore,
      privateDetail: privateDetail,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionGate(
          auth: auth,
          user: user,
          firestore: firestore,
          subscriptionCoordinator: coordinator,
          billingChannel: BillingChannel.stripe,
          paidWorkspaceBuilder: (_) => const Scaffold(
            body: Center(child: Text('Paid workspace restored')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Billing status unavailable'), findsOneWidget);
    expect(
      find.textContaining('could not confirm the subscription'),
      findsOneWidget,
    );
    expect(find.textContaining(privateDetail), findsNothing);
    expect(find.textContaining('private-token'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Paid workspace restored'), findsOneWidget);
    expect(coordinator.watchCount, 2);
  });

  test('subscription exceptions stringify only their closed kind', () {
    const failure = SubscriptionServiceException(
      SubscriptionServiceFailure.invalidResponse,
    );
    const checkout = StripeCheckoutException(
      'https://billing.example/private?token=secret',
    );
    const appStore = ApplePurchaseException(
      'private-account-id at /store/transactions/secret',
    );

    expect(failure.toString(), 'SubscriptionServiceException(invalidResponse)');
    expect(checkout.toString(), 'StripeCheckoutException');
    expect(checkout.toString(), isNot(contains('billing.example')));
    expect(checkout.toString(), isNot(contains('secret')));
    expect(appStore.toString(), 'ApplePurchaseException');
    expect(appStore.toString(), isNot(contains('private-account-id')));
  });

  test(
    'billing and workspace security sources keep details behind boundary',
    () {
      final gate = File(
        'lib/src/billing/subscription_gate.dart',
      ).readAsStringSync();
      final service = File(
        'lib/src/shared/subscription_service.dart',
      ).readAsStringSync();
      final workspace = File(
        'lib/src/home/workspace_home_page.dart',
      ).readAsStringSync();
      final appStore = File(
        'lib/src/billing/apple_store_purchase_service.dart',
      ).readAsStringSync();
      final vault = File(
        'lib/src/authentication/login_password_vault.dart',
      ).readAsStringSync();

      expect(
        gate,
        isNot(contains('We were unable to load your billing status. \$error')),
      );
      expect(gate, isNot(contains('_errorMessage = error.message')));
      expect(service, isNot(contains('REST): \$restError')));
      expect(service, isNot(contains('portal URL: \$urlString')));
      expect(
        workspace,
        isNot(contains('We could not confirm your security session. \$error')),
      );
      expect(
        workspace,
        isNot(contains('Unable to verify the code right now. \$error')),
      );
      expect(
        workspace,
        isNot(contains('Could not load subscription management: \$e')),
      );
      expect(vault, isNot(contains('credentials: \$error')));
      expect(appStore, isNot(contains('message: error.message')));
    },
  );
}

class _ErrorThenSuccessSubscriptionCoordinator extends SubscriptionCoordinator {
  _ErrorThenSuccessSubscriptionCoordinator({
    required super.firestore,
    required this.privateDetail,
  }) : super(checkoutApi: const DisabledStripeCheckoutApi());

  final String privateDetail;
  int watchCount = 0;

  @override
  Stream<SubscriptionState> watchSubscription(String uid) {
    watchCount += 1;
    if (watchCount == 1) {
      return Stream<SubscriptionState>.error(StateError(privateDetail));
    }
    return Stream<SubscriptionState>.value(
      SubscriptionState(exists: true, status: 'active'),
    );
  }
}
