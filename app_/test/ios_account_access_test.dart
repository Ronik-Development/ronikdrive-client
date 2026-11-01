import 'package:cloud_storage/src/billing/billing_channel.dart';
import 'package:cloud_storage/src/billing/subscription_coordinator.dart';
import 'package:cloud_storage/src/billing/subscription_gate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedCheckout extends Fake implements StripeCheckoutApi {}

void main() {
  for (final status in ['active', 'free', 'pending']) {
    testWidgets('iOS $status account does not need the App Store for login', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = FakeFirebaseFirestore();
        final user = MockUser(
          uid: 'account',
          email: 'account@users.ronikcloud.invalid',
        );
        final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
        await db.collection('users').doc(user.uid).set({
          'subscriptionStatus': status,
          'capacity': status == 'pending' ? 'pending' : '1 GB',
          'encryptionSalt': 'existing-salt',
          'usageBytes': 0,
          'storageInventory': {},
          'storageInventoryUpdatedAt': 'server-time',
        });
        await tester.pumpWidget(
          MaterialApp(
            home: SubscriptionGate(
              auth: auth,
              user: user,
              firestore: db,
              subscriptionCoordinator: SubscriptionCoordinator(
                firestore: db,
                checkoutApi: _UnusedCheckout(),
              ),
              billingChannel: BillingChannel.appStore,
              paidWorkspaceBuilder: (_) => const Text('Files are available'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            status == 'pending'
                ? 'Finish account setup'
                : 'Files are available',
          ),
          findsOneWidget,
        );
        expect(find.text('Loading App Store subscriptions…'), findsNothing);
        if (status == 'pending') {
          expect(find.text('Account email'), findsNothing);
          await tester.ensureVisible(find.text('Finish setup'));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
  test(
    'billing-linked pending profiles cannot be re-registered as free',
    () async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('users').doc('billing');
      await ref.set({
        'subscriptionStatus': 'pending',
        'capacity': 'pending',
        'billingSources': {},
      });
      expect(
        SubscriptionState.fromSnapshot(
          await ref.get(),
        ).needsRegistrationCompletion,
        isFalse,
      );
    },
  );
}
