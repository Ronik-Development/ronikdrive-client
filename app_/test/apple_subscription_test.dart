import 'dart:async';

import 'package:cloud_storage/src/billing/apple_store_purchase_service.dart';
import 'package:cloud_storage/src/billing/apple_subscription_page.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog maps all six products to the expected tier and interval', () {
    expect(appleProductCatalog, hasLength(6));
    expect(appleProductCatalog[appleBasicMonthlyProductId]?.tier, 'basic');
    expect(appleProductCatalog[appleProYearlyProductId]?.interval, 'yearly');
    expect(appleProductCatalog[appleUltraMonthlyProductId]?.rank, 1);
    expect(
      appleSubscriptionProductIds,
      containsAll(<String>[
        appleBasicMonthlyProductId,
        appleBasicYearlyProductId,
        appleProMonthlyProductId,
        appleProYearlyProductId,
        appleUltraMonthlyProductId,
        appleUltraYearlyProductId,
      ]),
    );
  });

  testWidgets('shows localized prices and restores purchases', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FakeApplePurchaseApi(_readyState());
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        home: AppleSubscriptionPage(auth: MockFirebaseAuth(), purchaseApi: api),
      ),
    );
    await tester.pump();

    expect(find.text(r'$2.49'), findsOneWidget);
    expect(find.text(r'$3.49'), findsOneWidget);
    expect(find.text(r'$6.00'), findsOneWidget);
    expect(find.text(r'$25.00'), findsNothing);
    expect(find.text('Restore Purchases'), findsOneWidget);
    expect(find.text('Manage Apple subscriptions'), findsOneWidget);
    expect(find.text('Request Apple refund'), findsOneWidget);
    expect(find.byKey(const Key('apple-refund-link')), findsOneWidget);
    expect(
      find.textContaining('Apple handles payment details'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Deleting your RonikCloud account does not cancel your App Store '
        'subscription',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Yearly'));
    await tester.pump();
    expect(find.text(r'$25.00'), findsOneWidget);
    expect(find.text(r'$35.00'), findsOneWidget);
    expect(find.text(r'$60.00'), findsOneWidget);

    await tester.tap(find.text('Restore Purchases'));
    await tester.pump();
    expect(api.restoreCalls, 1);
  });

  testWidgets(
    'renders pending, canceled, restored, and error purchase states',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _FakeApplePurchaseApi(_readyState());
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AppleSubscriptionPage(
            auth: MockFirebaseAuth(),
            purchaseApi: api,
          ),
        ),
      );
      await tester.pump();

      for (final entry in <(ApplePurchasePhase, String)>[
        (ApplePurchasePhase.pending, 'Waiting for approval'),
        (ApplePurchasePhase.canceled, 'Purchase canceled'),
        (ApplePurchasePhase.restored, 'Purchase restored'),
        (ApplePurchasePhase.error, 'Verification failed'),
      ]) {
        api.emit(
          ApplePurchaseState(
            phase: entry.$1,
            message: entry.$2,
            products: _products(),
          ),
        );
        await tester.pump();
        expect(find.text(entry.$2), findsOneWidget);
      }
      expect(find.text('Reload subscriptions'), findsOneWidget);
    },
  );

  testWidgets(
    'empty settled catalog shows recovery instead of an endless spinner',
    (tester) async {
      final api = _FakeApplePurchaseApi(
        const ApplePurchaseState(
          phase: ApplePurchasePhase.ready,
          message:
              'Restore finished. No active App Store subscription was returned.',
        ),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AppleSubscriptionPage(
            auth: MockFirebaseAuth(),
            purchaseApi: api,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining('No subscriptions are available'),
        findsOneWidget,
      );
      expect(find.text('Reload subscriptions'), findsOneWidget);
    },
  );

  testWidgets(
    'pending purchase keeps restore and sign out usable at 390px and 200% text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _FakeApplePurchaseApi(
        ApplePurchaseState(
          phase: ApplePurchasePhase.pending,
          message:
              'The purchase is pending approval or payment confirmation. You can restore purchases to check again or manage it with Apple.',
          products: _products(),
        ),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: AppleSubscriptionPage(
            auth: MockFirebaseAuth(),
            purchaseApi: api,
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Sign out'))
            .onPressed,
        isNotNull,
      );
      final restore = find.text('Restore Purchases');
      await tester.scrollUntilVisible(
        restore,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<TextButton>(
              find.ancestor(
                of: restore,
                matching: find.byWidgetPredicate(
                  (widget) => widget is TextButton,
                ),
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(restore);
      await tester.pump();
      expect(api.restoreCalls, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}

ApplePurchaseState _readyState() =>
    ApplePurchaseState(phase: ApplePurchasePhase.ready, products: _products());

List<AppleSubscriptionProduct> _products() {
  const prices = <String, String>{
    appleBasicMonthlyProductId: r'$2.49',
    appleBasicYearlyProductId: r'$25.00',
    appleProMonthlyProductId: r'$3.49',
    appleProYearlyProductId: r'$35.00',
    appleUltraMonthlyProductId: r'$6.00',
    appleUltraYearlyProductId: r'$60.00',
  };
  return appleProductCatalog.entries
      .map((entry) {
        final catalog = entry.value;
        return AppleSubscriptionProduct(
          id: entry.key,
          tier: catalog.tier,
          interval: catalog.interval,
          title: catalog.title,
          description: catalog.description,
          localizedPrice: prices[entry.key]!,
          rawPrice: 1,
        );
      })
      .toList(growable: false);
}

class _FakeApplePurchaseApi implements ApplePurchaseApi {
  _FakeApplePurchaseApi(this._state);

  final StreamController<ApplePurchaseState> _controller =
      StreamController<ApplePurchaseState>.broadcast(sync: true);
  ApplePurchaseState _state;
  int restoreCalls = 0;

  @override
  ApplePurchaseState get currentState => _state;

  @override
  Stream<ApplePurchaseState> get states => _controller.stream;

  void emit(ApplePurchaseState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> purchase(String productId) async {}

  @override
  Future<void> restorePurchases() async {
    restoreCalls += 1;
  }

  @override
  Future<void> dispose() async {}

  Future<void> close() => _controller.close();
}
