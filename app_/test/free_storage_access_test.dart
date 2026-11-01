import 'package:cloud_storage/src/billing/subscription_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:cloud_storage/src/billing/subscription_gate.dart';
import 'package:cloud_storage/src/billing/billing_channel.dart';
import 'package:cloud_storage/src/billing/storage_upgrade_page.dart';

void main() {
  testWidgets(
    'upgrade waits for backend confirmation and then leaves checkout',
    (tester) async {
      final user = MockUser(uid: 'upgrade-user');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final db = FakeFirebaseFirestore();
      final profile = db.collection('users').doc(user.uid);
      await profile.set({
        'subscriptionStatus': 'free',
        'capacityBytes': 1073741824,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: StorageUpgradePage(
            auth: auth,
            user: user,
            billingChannel: BillingChannel.stripe,
            initialSubscription: SubscriptionState(
              exists: true,
              status: 'free',
            ),
            coordinator: SubscriptionCoordinator(
              firestore: db,
              checkoutApi: HttpStripeCheckoutApi(
                apiBaseUrl: Uri.parse('https://unused.example.test'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SubscriptionPaywallPage), findsOneWidget);
      expect(find.text('Back to files'), findsNothing);
      // A client-side success notification alone is not an entitlement.
      paymentProcessingNotifier.value = true;
      await tester.pump();
      expect(find.text('Back to files'), findsNothing);
      await profile.update({'subscriptionStatus': 'active'});
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.byType(SubscriptionPaywallPage), findsNothing);
      expect(find.text('Back to files'), findsOneWidget);
      paymentProcessingNotifier.value = false;
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final channel in [
    BillingChannel.stripe,
    BillingChannel.appStore,
    BillingChannel.googlePlay,
  ]) {
    testWidgets('free personal workspace bypasses checkout on $channel', (
      tester,
    ) async {
      final user = MockUser(uid: 'free-user');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(user.uid).set({
        'subscriptionStatus': 'free',
        'capacityBytes': 1073741824,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionGate(
            auth: auth,
            user: user,
            firestore: db,
            billingChannel: channel,
            subscriptionCoordinator: SubscriptionCoordinator(
              firestore: db,
              checkoutApi: HttpStripeCheckoutApi(
                apiBaseUrl: Uri.parse('https://unused.example.test'),
              ),
            ),
            paidWorkspaceBuilder: (_) => const Text('Free workspace'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Free workspace'), findsOneWidget);
      expect(find.byType(SubscriptionPaywallPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test(
    'free entitlement opens personal workspace without claiming paid access',
    () {
      final state = SubscriptionState(exists: true, status: 'free');
      expect(state.hasWorkspaceAccess, isTrue);
      expect(state.requiresPayment, isFalse);
      expect(state.isPaid, isFalse);
    },
  );

  test('missing and unpaid profiles cannot bypass the gate', () {
    for (final status in ['pending', 'expired', 'past_due', 'unknown']) {
      final state = SubscriptionState(exists: true, status: status);
      expect(state.hasWorkspaceAccess, isFalse);
    }
    expect(
      SubscriptionState(exists: false, status: 'free').hasWorkspaceAccess,
      isFalse,
    );
  });

  test('paid and grace access remain available', () {
    for (final status in ['active', 'billing_grace_period']) {
      final state = SubscriptionState(exists: true, status: status);
      expect(state.hasWorkspaceAccess, isTrue);
      expect(state.isPaid, isTrue);
    }
  });
}
