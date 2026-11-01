import 'package:cloud_storage/src/authentication/two_factor_gate.dart';
import 'package:cloud_storage/src/authentication/two_factor_service.dart';
import 'package:cloud_storage/src/billing/billing_channel.dart';
import 'package:cloud_storage/src/billing/subscription_coordinator.dart';
import 'package:cloud_storage/src/billing/subscription_gate.dart';
import 'package:cloud_storage/src/settings/security_settings_page.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// MockUser exposes mutable Firebase user properties for tests.
// ignore: must_be_immutable
class _User extends MockUser {
  _User() : super(uid: 'user', email: 'user@example.test');
  int refreshes = 0;
  @override
  Future<String> getIdToken([bool forceRefresh = false]) async {
    if (forceRefresh) refreshes++;
    return 'test-token';
  }
}

class _Checkout extends Fake implements StripeCheckoutApi {}

class _Api extends Fake implements TwoFactorApi {
  _Api(this.failFirst);
  final bool failFirst;
  int calls = 0;
  @override
  Future<TwoFactorStatus> fetchStatus() async {
    calls++;
    if (failFirst && calls == 1) {
      throw const TwoFactorException('Authenticated session expired');
    }
    return const TwoFactorStatus(enabled: true, verified: false);
  }
}

class _UnavailableApi extends Fake implements TwoFactorApi {
  @override
  Future<TwoFactorStatus> fetchStatus() async =>
      throw StateError('Unavailable');
}

class _SettingsApi extends Fake implements TwoFactorApi {
  int calls = 0;
  @override
  Future<TwoFactorStatus> fetchStatus() async {
    if (++calls == 1) {
      throw StateError('Unavailable');
    }
    return const TwoFactorStatus(enabled: true, verified: true);
  }
}

void main() {
  testWidgets(
    'security settings keep failed status unknown until retry succeeds',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _SettingsApi();
      await tester.pumpWidget(
        MaterialApp(
          home: SecuritySettingsPage(
            user: _User(),
            firestore: FakeFirebaseFirestore(),
            twoFactorApi: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
      expect(
        find.text('Disabled. Add an extra layer of security to your account.'),
        findsNothing,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is FilledButton && widget.onPressed != null,
        ),
      );
      await tester.pumpAndSettle();
      expect(api.calls, 2);
      expect(
        find.text('Enabled. You will be asked for a code when signing in.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'security error recovery scrolls with large text on a short phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final user = _User();
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(user.uid).set({
        'twoFactorEnabled': true,
      });
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: TwoFactorGate(
            auth: MockFirebaseAuth(mockUser: user, signedIn: true),
            user: user,
            firestore: db,
            subscriptionCoordinator: SubscriptionCoordinator(
              firestore: db,
              checkoutApi: _Checkout(),
            ),
            twoFactorApi: _UnavailableApi(),
            billingChannel: BillingChannel.disabled,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('Sign out')).bottom,
        lessThanOrEqualTo(600),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in ['disabled', 'enabled', 'retry']) {
    testWidgets('Security startup $mode refreshes only on session failure', (
      tester,
    ) async {
      final user = _User();
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(user.uid).set({
        'twoFactorEnabled': mode != 'disabled',
        'subscriptionStatus': 'pending',
        'billingSources': {},
      });
      final api = _Api(mode == 'retry');
      await tester.pumpWidget(
        MaterialApp(
          home: TwoFactorGate(
            auth: auth,
            user: user,
            firestore: db,
            subscriptionCoordinator: SubscriptionCoordinator(
              firestore: db,
              checkoutApi: _Checkout(),
            ),
            twoFactorApi: api,
            billingChannel: BillingChannel.disabled,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(user.refreshes, mode == 'retry' ? 1 : 0);
      expect(
        api.calls,
        mode == 'disabled'
            ? 0
            : mode == 'retry'
            ? 2
            : 1,
      );
      expect(
        find.byType(SubscriptionGate),
        mode == 'disabled' ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
