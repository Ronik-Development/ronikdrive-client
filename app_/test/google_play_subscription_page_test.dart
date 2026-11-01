import 'dart:async';

import 'package:cloud_storage/src/billing/billing_channel.dart';
import 'package:cloud_storage/src/billing/google_play_purchase_service.dart';
import 'package:cloud_storage/src/billing/google_play_subscription_page.dart';
import 'package:cloud_storage/src/billing/storage_upgrade_page.dart';
import 'package:cloud_storage/src/billing/subscription_coordinator.dart';
import 'package:cloud_storage/src/billing/subscription_gate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _product = GooglePlaySubscriptionProduct(
  id: 'ronikdrive.basic.monthly',
  tier: 'basic',
  interval: 'monthly',
  title: 'Basic',
  capacity: '500 GB',
  localizedPrice: 'CZK 79.00',
);

class _Api implements GooglePlayPurchaseApi {
  final updates = StreamController<GooglePlayPurchaseState>.broadcast();
  GooglePlayPurchaseState state = const GooglePlayPurchaseState(
    phase: GooglePlayPurchasePhase.ready,
    products: [_product],
  );
  final purchased = <String>[];
  int restored = 0;
  int initialized = 0;
  @override
  Stream<GooglePlayPurchaseState> get states => updates.stream;
  @override
  GooglePlayPurchaseState get currentState => state;
  @override
  Future<void> initialize() async {
    initialized++;
  }

  @override
  Future<void> purchase(String id) async {
    purchased.add(id);
  }

  @override
  Future<void> restorePurchases() async {
    restored++;
  }

  @override
  Future<void> dispose() => updates.close();
}

void main() {
  late _Api api;
  late MockUser user;
  late MockFirebaseAuth auth;
  setUp(() {
    api = _Api();
    user = MockUser(uid: 'play-user');
    auth = MockFirebaseAuth(mockUser: user, signedIn: true);
  });
  tearDown(() => api.dispose());

  testWidgets('Play plans show localized prices and use the purchase API', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GooglePlaySubscriptionPage(auth: auth, purchaseApi: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CZK 79.00'), findsOneWidget);
    expect(find.text('500 GB'), findsOneWidget);
    expect(find.text('Manage Google Play subscriptions'), findsOneWidget);
    expect(find.textContaining('does not cancel'), findsOneWidget);
    expect(find.textContaining('Stripe checkout'), findsNothing);
    await tester.tap(find.text('Subscribe to Basic'));
    expect(api.purchased, ['ronikdrive.basic.monthly']);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('pending payment keeps restore/status and sign-out usable', (
    tester,
  ) async {
    api.state = const GooglePlayPurchaseState(
      phase: GooglePlayPurchasePhase.pending,
      products: [_product],
      hasExistingSubscription: true,
      message: 'Payment is pending.',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GooglePlaySubscriptionPage(auth: auth, purchaseApi: api),
      ),
    );
    await tester.pump();
    final subscribe = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Subscribe to Basic'),
    );
    expect(subscribe.onPressed, isNull);
    await tester.ensureVisible(find.text('Restore Purchases'));
    await tester.pump();
    await tester.tap(find.text('Restore Purchases'));
    expect(api.restored, 1);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Sign out'))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'verified plan changes require a clear replacement confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      api.state = const GooglePlayPurchaseState(
        phase: GooglePlayPurchasePhase.ready,
        products: [_product],
        hasExistingSubscription: true,
        currentProductId: 'ronikdrive.pro.monthly',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GooglePlaySubscriptionPage(auth: auth, purchaseApi: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Change to Basic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change to Basic'));
      await tester.pumpAndSettle();
      expect(find.textContaining('remaining paid time'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(api.purchased, isEmpty);
      await tester.tap(find.text('Keep current plan'));
      await tester.pumpAndSettle();
      expect(api.purchased, isEmpty);
      await tester.tap(find.text('Change to Basic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Google Play'));
      await tester.pumpAndSettle();
      expect(api.purchased, [_product.id]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('the current plan is identified and cannot be purchased again', (
    tester,
  ) async {
    api.state = const GooglePlayPurchaseState(
      phase: GooglePlayPurchasePhase.ready,
      products: [_product],
      hasExistingSubscription: true,
      currentProductId: 'ronikdrive.basic.monthly',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GooglePlaySubscriptionPage(auth: auth, purchaseApi: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Current plan'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'an unavailable interval shows recovery instead of an empty spinner',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GooglePlaySubscriptionPage(auth: auth, purchaseApi: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yearly'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No plans are available'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Play plan selection fits a narrow window at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 680);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: GooglePlaySubscriptionPage(auth: auth, purchaseApi: api),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Subscribe to Basic'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Google Play upgrades remain pending until the backend profile changes',
    (tester) async {
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
            billingChannel: BillingChannel.googlePlay,
            googlePlayPurchaseApi: api,
            initialSubscription: SubscriptionState(
              exists: true,
              status: 'free',
            ),
            coordinator: SubscriptionCoordinator(
              firestore: db,
              checkoutApi: const DisabledStripeCheckoutApi(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GooglePlaySubscriptionPage), findsOneWidget);
      api.updates.add(
        const GooglePlayPurchaseState(
          phase: GooglePlayPurchasePhase.complete,
          products: [_product],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Back to files'), findsNothing);
      await profile.update({'subscriptionStatus': 'active'});
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('Back to files'), findsOneWidget);
      expect(find.byType(GooglePlaySubscriptionPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'unpaid Google Play accounts use Play instead of Stripe checkout',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(user.uid).set({
        'subscriptionStatus': 'expired',
        'username': 'play-user',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionGate(
            auth: auth,
            user: user,
            firestore: db,
            billingChannel: BillingChannel.googlePlay,
            googlePlayPurchaseApi: api,
            subscriptionCoordinator: SubscriptionCoordinator(
              firestore: db,
              checkoutApi: const DisabledStripeCheckoutApi(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GooglePlaySubscriptionPage), findsOneWidget);
      expect(find.byType(SubscriptionPaywallPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
