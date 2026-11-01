import 'package:cloud_storage/src/analytics/growth_analytics.dart';
import 'package:cloud_storage/src/analytics/signup_completion_reconciliation.dart';
import 'package:cloud_storage/src/authentication/login_page.dart';
import 'package:cloud_storage/src/authentication/account_environment.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('signup start keeps first-touch attribution and fires once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final events = <GrowthEvent>[];
    final sources = <GrowthSource>[];
    final recordedProperties = <GrowthEventProperties>[];

    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          auth: MockFirebaseAuth(),
          firestore: FakeFirebaseFirestore(),
          attribution: const GrowthAttribution(
            source: GrowthSource.organicSocial,
            channel: GrowthChannel.linkedin,
            entryPage: GrowthEntryPage.secureCloudStorage,
          ),
          signupPlacement: GrowthPlacement.hero,
          signupCtaPlacement: GrowthCtaPlacement.hero,
          growthEventRecorder:
              ({required event, required source, required properties}) async {
                events.add(event);
                sources.add(source);
                recordedProperties.add(properties);
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();

    expect(events, <GrowthEvent>[GrowthEvent.signupStarted]);
    expect(sources, <GrowthSource>[GrowthSource.organicSocial]);
    expect(
      recordedProperties.single.authMethod,
      GrowthAuthMethod.emailPassword,
    );
    expect(recordedProperties.single.placement, GrowthPlacement.hero);
    expect(recordedProperties.single.channel, GrowthChannel.linkedin);
    expect(
      recordedProperties.single.entryPage,
      GrowthEntryPage.secureCloudStorage,
    );
    expect(recordedProperties.single.ctaPlacement, GrowthCtaPlacement.hero);
  });

  testWidgets(
    'registration producer persists the injected retry marker immediately',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final pendingStore = _RecordingPendingStore();
      final reconciler = SignupCompletionReconciler(
        store: pendingStore,
        retryDelays: const <Duration>[],
        submitter:
            ({
              required idToken,
              required channel,
              required entryPage,
              required ctaPlacement,
              required authMethod,
            }) async => AuthenticatedSignupCompletionResult.retryable,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            auth: MockFirebaseAuth(),
            firestore: FakeFirebaseFirestore(),
            initialRegisterMode: true,
            attribution: const GrowthAttribution(
              source: GrowthSource.organicSocial,
              channel: GrowthChannel.linkedin,
              entryPage: GrowthEntryPage.secureCloudStorage,
            ),
            signupPlacement: GrowthPlacement.hero,
            signupCtaPlacement: GrowthCtaPlacement.hero,
            signupCompletionReconciler: reconciler,
            standardEncryptionPreparer:
                ({required uid, required email, required password}) async =>
                    true,
            accountRegistrationProvisioner:
                ({
                  required username,
                  required legalVersion,
                  required legalAcceptedAt,
                  required productUpdatesOptIn,
                  required recoveryEmailProvided,
                  required createdAt,
                }) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'privacy_safe_user');
      await tester.enterText(fields.at(1), 'Privacy Safe User');
      await tester.enterText(fields.at(2), 'privacy-safe@example.test');
      await tester.enterText(fields.at(3), 'a-strong-test-password');
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).at(0))
          .onChanged!(true);
      await tester.pump();
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).at(1))
          .onChanged!(true);
      await tester.pump();
      final createAccount = find.widgetWithText(
        ElevatedButton,
        'Create account',
      );
      final submit = tester.widget<ElevatedButton>(createAccount).onPressed;
      expect(submit, isNotNull);
      submit!();
      for (var step = 0; step < 30 && pendingStore.pending == null; step += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final pending = pendingStore.pending;
      expect(pending, isNotNull);
      await tester.pumpAndSettle();
      expect(pending!.channel, GrowthChannel.linkedin);
      expect(pending.entryPage, GrowthEntryPage.secureCloudStorage);
      expect(pending.ctaPlacement, GrowthCtaPlacement.hero);
      expect(pending.authMethod, GrowthAuthMethod.emailPassword);
      expect(pending.normalizedAccountCreatedAt.isUtc, isTrue);
      expect(pending.toJson().keys, <String>{
        'schema_version',
        'channel',
        'entry_page',
        'cta_placement',
        'auth_method',
        'account_created_at',
      });
    },
  );

  testWidgets('username-only signup provisions without a recovery email', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final auth = MockFirebaseAuth();
    String? registeredUsername;
    bool? capturedRecoveryEmailProvided;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          auth: auth,
          firestore: FakeFirebaseFirestore(),
          initialRegisterMode: true,
          standardEncryptionPreparer:
              ({required uid, required email, required password}) async => true,
          accountRegistrationProvisioner:
              ({
                required username,
                required legalVersion,
                required legalAcceptedAt,
                required productUpdatesOptIn,
                required recoveryEmailProvided,
                required createdAt,
              }) async {
                registeredUsername = username;
                capturedRecoveryEmailProvided = recoveryEmailProvided;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'No_Email_User');
    await tester.enterText(fields.at(1), 'No Email User');
    await tester.enterText(fields.at(3), 'a-strong-test-password');
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile).at(0))
        .onChanged!(true);
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile).at(1))
        .onChanged!(true);
    await tester.pump();
    tester
        .widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Create account'),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(registeredUsername, 'no_email_user');
    expect(capturedRecoveryEmailProvided, false);
    expect(auth.currentUser?.email, 'no_email_user@users.ronikcloud.invalid');
  });

  testWidgets('Business mode offers account creation', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          auth: MockFirebaseAuth(),
          firestore: FakeFirebaseFirestore(),
          initialEnvironment: AccountEnvironment.business,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();

    expect(find.text('Create your Business account'), findsOneWidget);
    expect(find.text('Unique username'), findsOneWidget);
  });
}

class _RecordingPendingStore implements PendingSignupCompletionStore {
  PendingSignupCompletion? pending;

  @override
  Future<bool> clearIfMatches(PendingSignupCompletion candidate) async {
    if (pending?.hasSamePayload(candidate) != true) {
      return false;
    }
    pending = null;
    return true;
  }

  @override
  Future<PendingSignupCompletion?> read() async => pending;

  @override
  Future<bool> write(PendingSignupCompletion candidate) async {
    pending = candidate;
    return true;
  }
}
