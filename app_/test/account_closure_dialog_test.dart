import 'dart:io';

import 'package:cloud_storage/src/authentication/account_closure_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Stripe closure distinguishes cancellation deletion refunds and records',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      AccountClosureAction? decision;
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  decision = await showAccountClosureDialog(
                    context: context,
                    profileData: const <String, dynamic>{
                      'billingPrimaryProvider': 'stripe',
                      'subscriptionCustomerId': 'cus_test',
                      'currentPeriodEnd': '2026-09-18T12:00:00Z',
                    },
                    selfServiceDeletionEnabled: true,
                    launchLink: (uri) async {
                      opened.add(uri);
                      return true;
                    },
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel renewal'), findsOneWidget);
      expect(
        find.textContaining('Canceling renewal is different from deleting'),
        findsOneWidget,
      );
      expect(find.textContaining('2026-09-18'), findsOneWidget);
      expect(find.text('Stripe billing'), findsOneWidget);
      expect(find.byKey(accountClosureStripeRefundKey), findsOneWidget);
      expect(find.text('Stripe refund or billing help'), findsOneWidget);
      expect(
        find.textContaining('immediately ends the linked Stripe subscription'),
        findsOneWidget,
      );
      expect(
        find.textContaining('requests removal of the Stripe customer'),
        findsOneWidget,
      );
      expect(find.textContaining('transaction, invoice'), findsOneWidget);
      expect(
        find.textContaining('unused paid time is not automatically refunded'),
        findsOneWidget,
      );
      expect(find.text('Refunds'), findsOneWidget);
      expect(
        find.textContaining('does not automatically request or issue a refund'),
        findsOneWidget,
      );
      expect(find.text('Permanent deletion'), findsOneWidget);
      expect(
        find.textContaining('Organization-owned workspace data may remain'),
        findsOneWidget,
      );
      expect(
        find.textContaining('ownership must be transferred'),
        findsOneWidget,
      );
      expect(find.byKey(accountClosureManageAppleKey), findsNothing);

      await tester.tap(find.byKey(accountClosureStripeRefundKey));
      await tester.pump();
      expect(opened, <Uri>[accountClosureStripeRefundUri]);

      await tester.tap(find.byKey(accountClosureDeleteNowKey));
      await tester.pumpAndSettle();
      expect(decision, AccountClosureAction.deleteNow);
    },
  );

  testWidgets(
    'Apple closure offers management and refund without blocking delete',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final opened = <Uri>[];
      AccountClosureAction? decision;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  decision = await showAccountClosureDialog(
                    context: context,
                    profileData: <String, dynamic>{
                      'billingPrimaryProvider': 'appStore',
                      'billingProvidersActive': const <String>['appStore'],
                      'subscriptionEndDate': DateTime.utc(2026, 10, 2, 12),
                    },
                    selfServiceDeletionEnabled: true,
                    launchLink: (uri) async {
                      opened.add(uri);
                      return true;
                    },
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Apple subscription'), findsOneWidget);
      expect(
        find.textContaining('does not cancel an App Store subscription'),
        findsOneWidget,
      );
      expect(find.textContaining('continue and renew'), findsOneWidget);
      expect(find.byKey(accountClosureManageAppleKey), findsOneWidget);
      expect(find.byKey(accountClosureAppleRefundKey), findsOneWidget);
      expect(find.byKey(accountClosureDeleteNowKey), findsOneWidget);

      await tester.tap(find.byKey(accountClosureManageAppleKey));
      await tester.pump();
      await tester.tap(find.byKey(accountClosureAppleRefundKey));
      await tester.pump();
      expect(opened, <Uri>[
        accountClosureAppleSubscriptionsUri,
        accountClosureAppleRefundUri,
      ]);

      await tester.tap(find.byKey(accountClosureDeleteNowKey));
      await tester.pumpAndSettle();
      expect(decision, AccountClosureAction.deleteNow);
    },
  );

  for (final deleteImmediately in [false, true]) {
    testWidgets(
      'Google Play closure keeps renewal and refunds separate (delete now: $deleteImmediately)',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final opened = <Uri>[];
        AccountClosureAction? decision;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () async {
                    decision = await showAccountClosureDialog(
                      context: context,
                      profileData: const <String, dynamic>{
                        'billingPrimaryProvider': 'googlePlay',
                        'billingSources': <String, dynamic>{
                          'googlePlay': <String, dynamic>{
                            'currentPeriodEnd': '2026-11-16T12:00:00Z',
                          },
                        },
                      },
                      selfServiceDeletionEnabled: deleteImmediately,
                      launchLink: (uri) async {
                        opened.add(uri);
                        return true;
                      },
                    );
                  },
                  child: const Text('Open Play closure'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Play closure'));
        await tester.pumpAndSettle();

        expect(find.text('Google Play subscription'), findsOneWidget);
        expect(find.text('Original billing provider'), findsNothing);
        expect(find.text('Stripe billing'), findsNothing);
        expect(find.text('Apple subscription'), findsNothing);
        expect(find.textContaining('does not cancel'), findsOneWidget);
        expect(
          find.textContaining('does not request or issue a refund'),
          findsOneWidget,
        );
        expect(find.textContaining('2026-11-16'), findsOneWidget);
        if (!deleteImmediately) {
          expect(
            find.textContaining('closure request is pending'),
            findsOneWidget,
          );
          expect(find.byKey(accountClosureDeleteNowKey), findsNothing);
        }

        await tester.ensureVisible(
          find.byKey(accountClosureManageGooglePlayKey),
        );
        await tester.tap(find.byKey(accountClosureManageGooglePlayKey));
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(accountClosureGooglePlayRefundKey),
        );
        await tester.tap(find.byKey(accountClosureGooglePlayRefundKey));
        await tester.pump();
        expect(opened, <Uri>[
          accountClosureGooglePlaySubscriptionsUri,
          accountClosureGooglePlayRefundUri,
        ]);
        expect(decision, isNull);

        final action = find.byKey(
          deleteImmediately
              ? accountClosureDeleteNowKey
              : accountClosureRequestKey,
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(
          decision,
          deleteImmediately
              ? AccountClosureAction.deleteNow
              : AccountClosureAction.requestClosure,
        );
      },
    );
  }

  test('profile recognizes Google Play aliases and source-only billing', () {
    for (final provider in [
      'googlePlay',
      'google_play',
      'googleplay',
      'play',
    ]) {
      for (final data in <Map<String, dynamic>>[
        {'billingPrimaryProvider': provider},
        {'subscriptionProvider': provider},
        {
          'billingProvidersActive': [provider],
        },
        {
          'billingSources': {provider: <String, dynamic>{}},
        },
      ]) {
        final profile = AccountClosureProfile.fromProfile(data);
        expect(profile.hasGooglePlayBilling, isTrue, reason: '$data');
        expect(profile.hasUnknownBillingProvider, isFalse, reason: '$data');
      }
    }
  });

  test('profile parser supports mixed billing providers and epoch dates', () {
    final profile = AccountClosureProfile.fromProfile(<String, dynamic>{
      'billingPrimaryProvider': 'stripe',
      'billingProvidersActive': const <String>[
        'app_store',
        'stripe',
        'google_play',
      ],
      'billingSources': <String, dynamic>{
        'stripe': <String, dynamic>{'current_period_end': 1788213600},
      },
    });

    expect(profile.hasStripeBilling, isTrue);
    expect(profile.hasAppleBilling, isTrue);
    expect(profile.hasGooglePlayBilling, isTrue);
    expect(profile.hasUnknownBillingProvider, isFalse);
    expect(profile.billingStateKnown, isTrue);
    expect(
      profile.paidThrough,
      DateTime.fromMillisecondsSinceEpoch(1788213600000, isUtc: true),
    );
  });

  testWidgets(
    'unknown billing state shows every provider warning on a small large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showAccountClosureDialog(
                  context: context,
                  profileData: null,
                  launchLink: (_) async => true,
                ),
                child: const Text('Open unknown'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open unknown'));
      await tester.pumpAndSettle();
      expect(find.text('Stripe billing'), findsOneWidget);
      expect(find.text('Apple subscription'), findsOneWidget);
      expect(find.text('Google Play subscription'), findsOneWidget);
      expect(
        find.textContaining('Billing status could not be refreshed'),
        findsNWidgets(3),
      );
      expect(find.byKey(accountClosureStripeRefundKey), findsOneWidget);
      expect(find.byKey(accountClosureManageAppleKey), findsOneWidget);
      expect(find.byKey(accountClosureManageGooglePlayKey), findsOneWidget);
      expect(find.byKey(accountClosureRequestKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'default release records an authenticated request for staged deletion',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      AccountClosureAction? decision;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  decision = await showAccountClosureDialog(
                    context: context,
                    profileData: const <String, dynamic>{
                      'billingPrimaryProvider': 'stripe',
                    },
                  );
                },
                child: const Text('Open request'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open request'));
      await tester.pumpAndSettle();

      expect(selfServiceAccountDeletionEnabled, isFalse);
      expect(find.text('Permanent account closure'), findsOneWidget);
      expect(
        find.textContaining('authorizes permanent deletion'),
        findsOneWidget,
      );
      expect(find.textContaining('Cancel renewal separately'), findsOneWidget);
      expect(find.byKey(accountClosureRequestKey), findsOneWidget);
      expect(find.byKey(accountClosureDeleteNowKey), findsNothing);

      await tester.tap(find.byKey(accountClosureRequestKey));
      await tester.pumpAndSettle();
      expect(decision, AccountClosureAction.requestClosure);
    },
  );

  testWidgets(
    'unrecognized billing provider gets explicit cancellation and refund guidance',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showAccountClosureDialog(
                  context: context,
                  profileData: const <String, dynamic>{
                    'billingPrimaryProvider': 'futureStore',
                    'billingProvidersActive': <String>['futureStore'],
                  },
                  launchLink: (uri) async {
                    opened.add(uri);
                    return true;
                  },
                ),
                child: const Text('Open provider warning'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open provider warning'));
      await tester.pumpAndSettle();

      expect(find.text('Original billing provider'), findsOneWidget);
      expect(
        find.textContaining('not recognized by this app version'),
        findsOneWidget,
      );
      expect(find.textContaining('may not cancel its renewal'), findsOneWidget);
      expect(
        find.textContaining('through the original purchase channel'),
        findsOneWidget,
      );
      expect(find.text('Stripe billing'), findsNothing);
      expect(find.text('Apple subscription'), findsNothing);

      await tester.ensureVisible(
        find.byKey(accountClosureUnknownProviderHelpKey),
      );
      await tester.tap(find.byKey(accountClosureUnknownProviderHelpKey));
      await tester.pump();
      expect(opened, <Uri>[accountClosureUnknownProviderHelpUri]);
    },
  );

  testWidgets('recorded request shows status and explains queued processing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showAccountClosureRequestRecordedDialog(
                context: context,
                alreadyRequested: false,
                status: 'requested',
              ),
              child: const Text('Show receipt'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show receipt'));
    await tester.pumpAndSettle();

    expect(find.text('Closure request recorded'), findsOneWidget);
    expect(find.textContaining('Queue status: requested'), findsOneWidget);
    expect(find.textContaining('billing may remain active'), findsOneWidget);
    expect(find.textContaining('Cancel renewal separately'), findsOneWidget);
    expect(find.textContaining('two Czech business days'), findsOneWidget);
  });

  testWidgets('failed in-app request offers only the safe support fallback', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showAccountClosureRequestFallbackDialog(
                context: context,
                message: 'The closure request could not be recorded.',
                launchLink: (uri) async {
                  opened.add(uri);
                  return true;
                },
              ),
              child: const Text('Show fallback'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show fallback'));
    await tester.pumpAndSettle();
    expect(find.text('Closure request not recorded'), findsOneWidget);
    expect(
      find.textContaining('No account, access, data, or billing change'),
      findsOneWidget,
    );

    await tester.tap(find.text('Email support'));
    await tester.pumpAndSettle();
    expect(opened, <Uri>[accountClosureRequestSupportUri]);
  });

  test('both deletion entry points use the shared provider-aware dialog', () {
    final sources = <String>[
      File('lib/src/home/workspace_home_page.dart').readAsStringSync(),
      File('lib/src/settings/security_settings_page.dart').readAsStringSync(),
    ];

    for (final source in sources) {
      expect(source, contains('showAccountClosureDialog('));
      expect(source, contains('profileData: profileData'));
    }

    expect(
      sources.first,
      contains('Sign-in, access, data, and billing remain active'),
    );
    expect(
      sources.first,
      isNot(contains('Permanently delete your account and all data.')),
    );
    for (final source in sources) {
      expect(source, contains('AccountClosureAction.requestClosure'));
      expect(source, contains('AccountClosureRequestService'));
      expect(source, contains('showAccountClosureRequestRecordedDialog'));
    }
  });

  test('self-service deletion is compile-time gated and defaults off', () {
    final source = File(
      'lib/src/authentication/account_closure_dialog.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      source,
      contains(
        "bool.fromEnvironment(\n  'SELF_SERVICE_ACCOUNT_DELETION_ENABLED'",
      ),
    );
    expect(source, contains('defaultValue: false'));
  });

  test('subscription management exposes Stripe and Apple refund routes', () {
    final source = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();
    expect(source, contains('Stripe refund or billing help'));
    expect(source, contains('RonikCloud refund request'));
    expect(source, contains('Request Apple refund'));
    expect(source, contains('https://reportaproblem.apple.com/'));
    expect(source, contains('if (hasAppleProvider)'));
    expect(source, contains('if (managedByStripe)'));
  });
}
