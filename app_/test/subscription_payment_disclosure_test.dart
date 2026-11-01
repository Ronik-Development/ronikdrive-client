import 'package:cloud_storage/src/billing/checkout_plan_intent.dart';
import 'package:cloud_storage/src/billing/subscription_coordinator.dart';
import 'package:cloud_storage/src/billing/subscription_gate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(CheckoutPlanIntentStore.instance.clear);

  testWidgets('Stripe paywall explains payment retention before checkout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final user = MockUser(uid: 'stripe-disclosure', email: 'user@example.test');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final coordinator = SubscriptionCoordinator(
      firestore: FakeFirebaseFirestore(),
      checkoutApi: const DisabledStripeCheckoutApi(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionPaywallPage(
          auth: auth,
          user: user,
          subscription: SubscriptionState(exists: true, status: 'pending'),
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Payment details and renewal'), findsOneWidget);
    expect(
      find.textContaining(
        'RonikCloud never receives or stores your full card number or CVC',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Auto-renewing subscriptions require Stripe to retain a reusable '
        'payment credential',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'If checkout is abandoned before confirmation, no RonikCloud '
        'subscription or charge is created',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Stripe may still process the checkout session and any payment input '
        'under its privacy policy',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Cancellation stops future renewal; deleting your RonikCloud account '
        'does not create a refund',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Continue with Pro'));
    await tester.tap(find.text('Continue with Pro'));
    await tester.pumpAndSettle();

    expect(find.text('Payment and renewal'), findsOneWidget);
    expect(find.text('Do not start recurring plan'), findsOneWidget);
    expect(find.text('Accept renewal and continue'), findsOneWidget);
    expect(
      find.textContaining(
        'RonikCloud never receives or stores your full card number or CVC',
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('paywall honors the plan and interval selected before signup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    CheckoutPlanIntentStore.instance.remember(
      tier: 'basic',
      interval: 'yearly',
    );
    final user = MockUser(uid: 'selected-plan', email: 'user@example.test');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionPaywallPage(
          auth: auth,
          user: user,
          subscription: SubscriptionState(exists: true, status: 'pending'),
          coordinator: SubscriptionCoordinator(
            firestore: FakeFirebaseFirestore(),
            checkoutApi: const DisabledStripeCheckoutApi(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Continue with Basic'), findsOneWidget);
    expect(find.text('Two months free with annual billing'), findsOneWidget);
    expect(find.text(r'$25 per year', findRichText: true), findsOneWidget);
  });

  testWidgets('Business signup exposes a purchasable company plan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final user = MockUser(
      uid: 'business-signup',
      email: 'company_owner@users.ronikcloud.invalid',
    );
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(
        home: SubscriptionPaywallPage(
          auth: auth,
          user: user,
          subscription: SubscriptionState(exists: true, status: 'pending'),
          coordinator: SubscriptionCoordinator(
            firestore: FakeFirebaseFirestore(),
            checkoutApi: const DisabledStripeCheckoutApi(),
          ),
          businessMode: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Unlock RonikCloud Business'), findsOneWidget);
    expect(find.text('Continue with Business'), findsOneWidget);
    expect(find.text('Continue with Basic'), findsNothing);
    expect(find.textContaining('collects a billing email'), findsOneWidget);
    expect(
      find.textContaining('company_owner@users.ronikcloud.invalid'),
      findsNothing,
    );
  });
}
