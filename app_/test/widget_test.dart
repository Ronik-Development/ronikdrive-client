import 'helpers/firebase_test_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_storage/main.dart';
import 'package:cloud_storage/src/authentication/login_password_vault.dart';
import 'package:cloud_storage/src/authentication/login_page.dart';
import 'package:cloud_storage/src/authentication/two_factor_service.dart';
import 'package:cloud_storage/src/billing/billing_channel.dart';
import 'package:cloud_storage/src/billing/checkout_plan_intent.dart';
import 'package:cloud_storage/src/billing/subscription_gate.dart';
import 'package:cloud_storage/src/billing/subscription_coordinator.dart';
import 'package:cloud_storage/src/business/business_workspace_page.dart';
import 'package:cloud_storage/src/home/selection_action_bar.dart';
import 'package:cloud_storage/src/home/workspace_home_page.dart';
import 'package:cloud_storage/src/legal/legal_documents_page.dart';
import 'package:cloud_storage/src/storage/wasabi_storage_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Desktop registration fits without scrolling at 1440 by 900', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          auth: TestFirebaseAuth(),
          firestore: FakeFirebaseFirestore(),
          initialRegisterMode: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.maxScrollExtent, 0);
    expect(
      find.widgetWithText(ElevatedButton, 'Create account'),
      findsOneWidget,
    );
  });
  Map<String, Object?> currentLegalFields() {
    const now = '2026-06-12T00:00:00.000Z';
    return <String, Object?>{
      'legalVersion': LegalDocuments.legalVersion,
      'termsAcceptedAt': now,
      'privacyAcknowledgedAt': now,
      'acceptableUseAcceptedAt': now,
      'cancellationRefundAcknowledgedAt': now,
      'dataRetentionAcknowledgedAt': now,
      'subprocessorsAcknowledgedAt': now,
      'legalAcceptanceSource': 'signup',
      'productUpdatesOptIn': false,
      'productUpdatesSource': 'signup',
    };
  }

  testWidgets('Shows login marketing content', (WidgetTester tester) async {
    final mockAuth = TestFirebaseAuth();
    final fakeFirestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('RonikCloud home'), findsOneWidget);
    expect(find.text('Your files.\nYour private space.'), findsOneWidget);
    expect(find.text('Create free workspace'), findsOneWidget);
    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Documentation'), findsOneWidget);
    expect(find.text('Room to grow'), findsOneWidget);
    expect(find.text('FOUNDING BETA'), findsNothing);
    expect(find.text('Simple Comparisons'), findsNothing);
    expect(find.text('Get the app'), findsOneWidget);
    expect(find.text('See current downloads'), findsOneWidget);
    expect(find.text('Join release testing'), findsOneWidget);
    expect(find.text('Help shape a privacy-first alternative'), findsNothing);
    expect(find.text('Open tester program'), findsNothing);
    expect(find.text('All downloads and install details'), findsNothing);
    expect(find.text('Receive weekly product news'), findsNothing);
    expect(find.text('Participate in product testing'), findsNothing);
    expect(find.byIcon(Icons.dark_mode), findsNothing);
    expect(find.byIcon(Icons.light_mode), findsNothing);
    expect(find.text('Full name'), findsNothing);

    final primaryActions = find.byKey(
      const ValueKey('landing-primary-actions'),
    );
    final pricing = find.byKey(const ValueKey('landing-pricing-section'));
    final downloads = find.byKey(const ValueKey('landing-download-section'));
    expect(
      tester.getTopLeft(primaryActions).dy,
      lessThan(tester.getTopLeft(pricing).dy),
    );
    expect(
      tester.getTopLeft(pricing).dy,
      lessThan(tester.getTopLeft(downloads).dy),
    );
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets('Landing cards align and fit at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        CloudStorageApp(
          auth: TestFirebaseAuth(),
          firestore: FakeFirebaseFirestore(),
          twoFactorApi: const _TestTwoFactorApi(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width >= 900) {
        final prices = [
          'Basic',
          'Pro',
          'Ultra',
        ].map((title) => tester.getTopLeft(find.text(title)).dy).toList();
        expect(prices[0], prices[1]);
        expect(prices[1], prices[2]);
        final buttons = find.text('Choose Plan');
        expect(buttons, findsNWidgets(3));
        expect(
          tester.getTopLeft(buttons.at(0)).dy,
          tester.getTopLeft(buttons.at(1)).dy,
        );
        expect(
          tester.getTopLeft(buttons.at(1)).dy,
          tester.getTopLeft(buttons.at(2)).dy,
        );
      }
    });
  }

  testWidgets('Landing page opens user documentation', (
    WidgetTester tester,
  ) async {
    final mockAuth = TestFirebaseAuth();
    final fakeFirestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Documentation'));
    await tester.pumpAndSettle();

    expect(find.text('RonikCloud Documentation'), findsOneWidget);
    expect(find.text('Start using RonikCloud'), findsOneWidget);
  });

  testWidgets('Download help opens the platform download page', (
    WidgetTester tester,
  ) async {
    final mockAuth = TestFirebaseAuth();
    final fakeFirestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
      ),
    );
    await tester.pumpAndSettle();

    final help = find.text('See current downloads');
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();

    expect(find.text('Get RonikCloud'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
  });

  testWidgets('Tester program opens on its dedicated page', (
    WidgetTester tester,
  ) async {
    final mockAuth = TestFirebaseAuth();
    final fakeFirestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
      ),
    );
    await tester.pumpAndSettle();

    final testerLink = find.text('Join release testing');
    await tester.ensureVisible(testerLink);
    await tester.tap(testerLink);
    await tester.pumpAndSettle();

    expect(find.text('RonikCloud founding beta'), findsOneWidget);
    expect(find.text('Test one real file workflow'), findsOneWidget);
    expect(find.text('Receive weekly product news'), findsOneWidget);
    expect(find.text('Participate in product testing'), findsOneWidget);
  });

  testWidgets('App Store companion mode exposes sign-in only', (
    WidgetTester tester,
  ) async {
    final mockAuth = TestFirebaseAuth();
    final fakeFirestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
        externalCheckoutEnabled: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);
    expect(find.text('Try for free'), findsNothing);
    expect(find.text('Pricing Plans'), findsNothing);
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Download app for your device'), findsNothing);
  });

  testWidgets('App Store billing channel keeps Personal registration enabled', (
    WidgetTester tester,
  ) async {
    final mockAuth = TestFirebaseAuth();
    final fakeFirestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
        billingChannel: BillingChannel.appStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create free workspace'), findsOneWidget);
    expect(find.text('Sign In'), findsWidgets);
  });

  testWidgets('Register mode requires a username and keeps email optional', (
    WidgetTester tester,
  ) async {
    final mockAuth = TestFirebaseAuth();
    final fakeFirestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, 'Create free workspace'),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextFormField, 'Unique username'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextFormField, 'Display name (optional)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextFormField, 'Recovery email (optional)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
  });

  testWidgets('Register mode requires legal consent before submit', (
    WidgetTester tester,
  ) async {
    final mockAuth = TestFirebaseAuth();
    final fakeFirestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, 'Create free workspace'),
    );
    await tester.pumpAndSettle();

    final submitButton = find.widgetWithText(ElevatedButton, 'Create account');
    expect(submitButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(submitButton).onPressed, isNull);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Acceptable Use'), findsOneWidget);

    final termsConsent = find.text(
      'I agree to the Terms of Service and Acceptable Use Policy.',
    );
    await tester.ensureVisible(termsConsent);
    await tester.pump();
    await tester.tap(termsConsent);
    await tester.pump();
    expect(tester.widget<ElevatedButton>(submitButton).onPressed, isNull);

    final privacyConsent = find.text(
      'I acknowledge the Privacy Policy, Cancellation and Refund Policy, Data Retention Policy, and Subprocessors list.',
    );
    await tester.ensureVisible(privacyConsent);
    await tester.pump();
    await tester.tap(privacyConsent);
    await tester.pump();
    expect(tester.widget<ElevatedButton>(submitButton).onPressed, isNotNull);
    expect(
      find.text('Send me product updates, release notes, and service news.'),
      findsOneWidget,
    );
  });

  testWidgets('Shows workspace when user is authenticated', (
    WidgetTester tester,
  ) async {
    final mockUser = MockUser(
      uid: 'uid-123',
      email: 'natalfern@ronikdrive.com',
    );
    final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
    final fakeFirestore = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues({
      'workspace_walkthrough_completed_v1_uid-123': true,
    });

    await fakeFirestore.collection('users').doc('uid-123').set({
      'name': 'Natal Fern',
      'email': 'natalfern@ronikdrive.com',
      'createdAt': '2024-01-01T00:00:00Z',
      'currentPeriodEnd': DateTime.now().add(const Duration(days: 365)).toIso8601String(),
      'subscriptionProvider': 'stripe',
      'subscriptionTier': 'pro',
      'capacity': '20 TB',
      'subscriptionStatus': 'active',
      ...currentLegalFields(),
    });

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.byType(WorkspaceHomePage), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final supportTile = find.text('App and support', skipOffstage: false);
    await tester.scrollUntilVisible(
      supportTile,
      320,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(supportTile);
    await tester.pump();
    await tester.tap(supportTile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final bugReportTile = find.text('Report an issue', skipOffstage: false);
    await tester.ensureVisible(bugReportTile);
    await tester.pump();

    expect(find.text('Report an issue'), findsOneWidget);
    expect(
      find.text('Send a problem report directly from this workspace.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Report an issue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('What happened?'), findsOneWidget);
    expect(find.text('Steps to reproduce'), findsOneWidget);
    expect(
      find.textContaining('common emails, paths, filenames, tokens'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No file, key, log, or automatic diagnostic'),
      findsOneWidget,
    );
  });

  testWidgets(
    'locked encrypted workspace hides ciphertext and keeps unlock recovery visible',
    (WidgetTester tester) async {
      const userId = 'uid-locked-workspace';
      const encryptedLabel = 'enc--abcdefghijklmnopqrstuv';
      final mockUser = MockUser(
        uid: userId,
        email: 'locked-workspace@example.com',
      );
      final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
      final fakeFirestore = FakeFirebaseFirestore();
      LoginPasswordVault.instance.clear();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'workspace_walkthrough_completed_v1_$userId': true,
      });

      await fakeFirestore.collection('users').doc(userId).set({
        'createdAt': '2026-01-01T00:00:00Z',
        'currentPeriodEnd': '2027-12-31T00:00:00Z',
        'capacity': '2 TB',
        'subscriptionStatus': 'active',
        'encryptionSalt': 'AQEBAQEBAQEBAQEBAQEBAQ==',
        ...currentLegalFields(),
      });
      await fakeFirestore.collection('files').doc('encrypted-file').set({
        'uid': userId,
        'objectKey': 'user_opaque/objects/aa/opaque.e.$encryptedLabel',
        'sizeBytes': 4096,
        'uploadedAt': '2026-08-02T12:00:00Z',
        'encryptionMode': 'standard',
        'contentEncryption': 'standard',
        'encryptedName': encryptedLabel,
        'hasThumbnail': true,
        'storageScope': 'personal',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceHomePage(
            auth: mockAuth,
            user: mockUser,
            firestore: fakeFirestore,
            storageService: WasabiStorageService(
              accessKey: 'test-access-key',
              secretKey: 'test-secret-key',
              bucket: 'test-bucket',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(find.textContaining('enc--'), findsNothing);
      expect(
        find.text('Unlock encrypted workspace', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Encrypted file', skipOffstage: false), findsOneWidget);
      expect(
        find.textContaining('derived key stays protected on this device'),
        findsOneWidget,
      );

      await tester.tap(
        find.byTooltip('Unlock encrypted workspace', skipOffstage: false),
      );
      await tester.pump();
      expect(find.text('Unlock encrypted files'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Business navigation ignores legacy company mirrors and internal group IDs',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const userId = 'uid-private-business-labels';
      const legacyCompanyLabel = 'Provider Readable Legacy Company';
      const internalGroupId = 'group_private_internal_identifier';
      final mockUser = MockUser(
        uid: userId,
        email: 'business-labels@example.test',
      );
      final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
      final fakeFirestore = FakeFirebaseFirestore();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'workspace_walkthrough_completed_v1_$userId': true,
      });

      await fakeFirestore.collection('users').doc(userId).set({
        'createdAt': '2026-01-01T00:00:00Z',
        'currentPeriodEnd': '2027-12-31T00:00:00Z',
        'capacity': '2 TB',
        'subscriptionStatus': 'active',
        'companyId': 'company-private',
        'companyDisplayName': legacyCompanyLabel,
        'companyMembershipStatus': 'active',
        'companyPermissions': <String, bool>{
          'uploadFiles': true,
          'downloadFiles': true,
          'shareFiles': true,
        },
        'companyAccessScopes': <String>['company_workspace'],
        'companyGroupIds': <String>[internalGroupId],
        'companyGroupStorageEnabledIds': <String>[internalGroupId],
        'companyStoragePolicy': <String, Object?>{
          'privateStorageEnabledByDefault': false,
          'sharedStorageEnabled': true,
        },
        ...currentLegalFields(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceHomePage(
            auth: mockAuth,
            user: mockUser,
            firestore: fakeFirestore,
            storageService: WasabiStorageService(
              accessKey: 'test-access-key',
              secretKey: 'test-secret-key',
              bucket: 'test-bucket',
            ),
            businessMode: true,
            businessCompanyLabel: 'Protected company',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.text(legacyCompanyLabel, skipOffstage: false), findsNothing);
      expect(find.textContaining(internalGroupId), findsNothing);
      expect(
        find.text('Protected company files', skipOffstage: false),
        findsWidgets,
      );
      expect(
        find.text('Protected group 1 files', skipOffstage: false),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Business workspace explains upload-only access', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const userId = 'uid-business-upload-only';
    final mockUser = MockUser(uid: userId, email: 'upload-only@example.test');
    final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
    final fakeFirestore = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'workspace_walkthrough_completed_v1_$userId': true,
    });
    await fakeFirestore.collection('users').doc(userId).set({
      'createdAt': '2026-01-01T00:00:00Z',
      'currentPeriodEnd': '2027-12-31T00:00:00Z',
      'capacity': '2 TB',
      'subscriptionStatus': 'active',
      'companyId': 'company-private',
      'companyMembershipStatus': 'active',
      'companyPermissions': <String, bool>{
        'uploadFiles': true,
        'downloadFiles': false,
        'shareFiles': false,
      },
      'companyAccessScopes': <String>['company_workspace'],
      'companyStoragePolicy': <String, Object?>{
        'privateStorageEnabledByDefault': false,
        'sharedStorageEnabled': true,
      },
      ...currentLegalFields(),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceHomePage(
          auth: mockAuth,
          user: mockUser,
          firestore: fakeFirestore,
          storageService: WasabiStorageService(
            accessKey: 'test-access-key',
            secretKey: 'test-secret-key',
            bucket: 'test-bucket',
          ),
          businessMode: true,
          businessCompanyLabel: 'Protected company',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Upload-only Business access'), findsOneWidget);
    expect(
      find.textContaining('names, previews, and decrypted keys'),
      findsOneWidget,
    );
    expect(find.byTooltip('Upload files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Business workspace explains read-only access', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const userId = 'uid-business-read-only';
    final mockUser = MockUser(uid: userId, email: 'read-only@example.test');
    final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
    final fakeFirestore = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'workspace_walkthrough_completed_v1_$userId': true,
    });
    await fakeFirestore.collection('users').doc(userId).set({
      'createdAt': '2026-01-01T00:00:00Z',
      'currentPeriodEnd': '2027-12-31T00:00:00Z',
      'capacity': '2 TB',
      'subscriptionStatus': 'active',
      'companyId': 'company-private',
      'companyMembershipStatus': 'active',
      'companyPermissions': <String, bool>{
        'uploadFiles': false,
        'downloadFiles': true,
        'shareFiles': false,
      },
      'companyAccessScopes': <String>['company_workspace'],
      'companyStoragePolicy': <String, Object?>{
        'privateStorageEnabledByDefault': false,
        'sharedStorageEnabled': true,
      },
      ...currentLegalFields(),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceHomePage(
          auth: mockAuth,
          user: mockUser,
          firestore: fakeFirestore,
          storageService: WasabiStorageService(
            accessKey: 'test-access-key',
            secretKey: 'test-secret-key',
            bucket: 'test-bucket',
          ),
          businessMode: true,
          businessCompanyLabel: 'Protected company',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Read-only Business access'), findsOneWidget);
    expect(
      find.textContaining('uploads and metadata changes are unavailable'),
      findsOneWidget,
    );
    expect(find.byTooltip('Upload files'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Suspended storage shows guidance and disables uploads', (
    WidgetTester tester,
  ) async {
    const userId = 'uid-storage-suspended';
    final mockUser = MockUser(uid: userId, email: 'paused@example.com');
    final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
    final fakeFirestore = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'workspace_walkthrough_completed_v1_$userId': true,
    });

    await fakeFirestore.collection('users').doc(userId).set({
      'name': 'Paused User',
      'email': 'paused@example.com',
      'createdAt': '2026-01-01T00:00:00Z',
      'currentPeriodEnd': '2027-12-31T00:00:00Z',
      'capacity': '2 TB',
      'subscriptionStatus': 'active',
      'storageWriteSuspended': true,
      'storageInventory': <String, dynamic>{
        'status': 'over_capacity',
        'complete': true,
        'observedBytes': 2200000000000,
        'metadataUsageBytes': 2100000000000,
      },
      ...currentLegalFields(),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceHomePage(
          auth: mockAuth,
          user: mockUser,
          firestore: fakeFirestore,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(
      find.text('Uploads temporarily paused', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('never file contents or names', skipOffstage: false),
      findsOneWidget,
    );
    final uploadButton = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(uploadButton.onPressed, isNull);
  });

  testWidgets(
    'Upload bandwidth presets preserve legacy limits and support custom values',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const userId = 'uid-bandwidth';
      final mockUser = MockUser(uid: userId, email: 'bandwidth@example.com');
      final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
      final fakeFirestore = FakeFirebaseFirestore();
      SharedPreferences.setMockInitialValues({
        'workspace_walkthrough_completed_v1_$userId': true,
        'workspace_upload_bandwidth_limit_bps_v1': 5 * 1024 * 1024,
      });

      await fakeFirestore.collection('users').doc(userId).set({
        'name': 'Bandwidth User',
        'email': 'bandwidth@example.com',
        'createdAt': '2026-01-01T00:00:00Z',
        'currentPeriodEnd': '2026-12-31T00:00:00Z',
        'capacity': '20 TB',
        'subscriptionStatus': 'active',
        ...currentLegalFields(),
      });

      await tester.pumpWidget(
        CloudStorageApp(
          auth: mockAuth,
          firestore: fakeFirestore,
          twoFactorApi: const _TestTwoFactorApi(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      await tester.tap(find.text('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final bandwidthTile = find.text('Upload bandwidth', skipOffstage: false);
      await tester.scrollUntilVisible(
        bandwidthTile,
        320,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(bandwidthTile);
      await tester.tap(bandwidthTile);
      await tester.pump(const Duration(milliseconds: 300));
      final settingsScrollable = find.ancestor(
        of: bandwidthTile,
        matching: find.byType(Scrollable),
      );
      expect(settingsScrollable, findsOneWidget);

      expect(find.text('Unlimited (maximum speed)'), findsOneWidget);
      expect(find.text('Slow - 512 KB/s'), findsOneWidget);
      expect(find.text('Medium - 2 MB/s'), findsOneWidget);
      expect(find.text('Fast - 10 MB/s'), findsOneWidget);
      expect(find.text('1 MB/s'), findsNothing);
      expect(find.text('5 MB/s'), findsNothing);
      expect(
        find.text('Current custom limit: 5 MB/s.', skipOffstage: false),
        findsOneWidget,
      );

      final customOption = find.text('Custom', skipOffstage: false);
      await tester.dragUntilVisible(
        customOption,
        settingsScrollable,
        const Offset(0, -180),
      );
      final customListTile = find.ancestor(
        of: customOption,
        matching: find.byType(ListTile),
      );
      expect(customListTile, findsOneWidget);
      tester.widget<ListTile>(customListTile).onTap!();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Custom upload bandwidth'), findsOneWidget);
      expect(find.text('Allowed range: 1 KB/s to 10 GB/s.'), findsOneWidget);
      final customValue = find.byKey(
        const ValueKey<String>('custom-upload-bandwidth-value'),
      );
      await tester.enterText(customValue, '0');
      await tester.tap(find.widgetWithText(FilledButton, 'Save limit'));
      await tester.pump();
      expect(find.text('Enter a value greater than zero.'), findsOneWidget);

      await tester.enterText(customValue, '1.5');
      await tester.tap(find.widgetWithText(FilledButton, 'Save limit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getInt('workspace_upload_bandwidth_limit_bps_v1'),
        1572864,
      );
      expect(find.text('Currently limited to 1.5 MB/s.'), findsOneWidget);

      final unlimitedOption = find.text(
        'Unlimited (maximum speed)',
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        unlimitedOption,
        -240,
        scrollable: settingsScrollable,
      );
      await tester.tap(unlimitedOption);
      await tester.pump(const Duration(milliseconds: 300));
      expect(preferences.getInt('workspace_upload_bandwidth_limit_bps_v1'), 0);
      expect(
        find.text('Uploads use the maximum speed available.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Workspace tour opens automatically and setup guide can minimize',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockUser = MockUser(uid: 'uid-tour', email: 'tour@example.com');
      final mockAuth = _TourAuth(mockUser);
      final fakeFirestore = FakeFirebaseFirestore();
      SharedPreferences.setMockInitialValues({
        'workspace_walkthrough_completed_v1_uid-tour': false,
      });

      await fakeFirestore.collection('users').doc('uid-tour').set({
        'name': 'Tour User',
        'email': 'tour@example.com',
        'createdAt': '2026-01-01T00:00:00Z',
        'currentPeriodEnd': '2026-12-31T00:00:00Z',
        'capacity': '20 TB',
        'subscriptionStatus': 'active',
        ...currentLegalFields(),
      });

      await tester.pumpWidget(
        CloudStorageApp(
          auth: mockAuth,
          firestore: fakeFirestore,
          twoFactorApi: const _TestTwoFactorApi(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      for (var tick = 0; tick < 12; tick++) {
        await tester.pump(const Duration(seconds: 1));
      }
      tester.view.physicalSize = const Size(480, 560);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Workspace tour'),
        ),
        findsOneWidget,
      );
      expect(find.text('Your files, in one place'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('0 of 2 tips checked'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final firstPracticeTip = find.byKey(
        const ValueKey('workspace-tour-point-0-0'),
      );
      await tester.ensureVisible(firstPracticeTip);
      await tester.pump();
      await tester.tap(firstPracticeTip);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('1 of 2 tips checked'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final firstNavigationTile = find.ancestor(
        of: find.text('1. Your files, in one place'),
        matching: find.byType(AnimatedContainer),
      );
      expect(firstNavigationTile, findsOneWidget);
      expect(tester.getSize(firstNavigationTile), const Size(92, 92));

      for (var step = 2; step <= 3; step += 1) {
        await tester.tap(find.widgetWithText(FilledButton, 'Next'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('$step/3'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      expect(find.text('Keep files available offline'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Finish'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(Dialog), findsNothing);
      final guide = find.text('Setup guide');
      await tester.ensureVisible(guide);
      expect(find.text('Replay the short tutorial'), findsNothing);
      await tester.tap(guide);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Replay the short tutorial'), findsOneWidget);
      await tester.tap(guide);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Replay the short tutorial'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'workspace_walkthrough_completed_v1_uid-tour',
        ),
        isTrue,
      );

      expect(tester.takeException(), isNull);
    },
    skip: !kIsWeb,
  ); // This full-workspace fixture requires browser storage.

  testWidgets('Workspace requires legal reacceptance for stale profiles', (
    WidgetTester tester,
  ) async {
    final mockUser = MockUser(uid: 'uid-legal', email: 'legal@example.com');
    final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
    final fakeFirestore = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues({
      'workspace_walkthrough_completed_v1_uid-legal': true,
    });

    await fakeFirestore.collection('users').doc('uid-legal').set({
      'name': 'Legal User',
      'email': 'legal@example.com',
      'createdAt': '2024-01-01T00:00:00Z',
      'currentPeriodEnd': DateTime.now().add(const Duration(days: 365)).toIso8601String(),
      'subscriptionProvider': 'stripe',
      'subscriptionTier': 'pro',
      'capacity': '20 TB',
      'subscriptionStatus': 'active',
    });

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Review updated terms').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('Review updated terms'), findsOneWidget);
    final acceptButton = find.text('Accept and continue');
    expect(acceptButton, findsOneWidget);
    await tester.tap(acceptButton);
    await tester.pump();
    expect(find.text('Review updated terms'), findsOneWidget);

    await tester.tap(
      find.text('I agree to the Terms of Service and Acceptable Use Policy.'),
    );
    await tester.pump();
    await tester.tap(
      find.text(
        'I acknowledge the Privacy Policy, Cancellation and Refund Policy, Data Retention Policy, and Subprocessors list.',
      ),
    );
    await tester.pump();
    await tester.tap(
      find.text('Send me product updates, release notes, and service news.'),
    );
    await tester.pump();

    await tester.tap(acceptButton);
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find.text('Review updated terms').evaluate().isEmpty) {
        break;
      }
    }

    final profile = await fakeFirestore
        .collection('users')
        .doc('uid-legal')
        .get();
    final data = profile.data()!;
    expect(data['legalVersion'], LegalDocuments.legalVersion);
    expect(data['legalAcceptanceSource'], 'reacceptance');
    expect(data['productUpdatesOptIn'], isTrue);
    expect(data['productUpdatesSource'], 'legal_prompt');
  });

  testWidgets('Selection action bar shows bundle download action', (
    WidgetTester tester,
  ) async {
    var cleared = false;
    var downloaded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: SelectionActionBar(
            selectedCount: 2,
            onClear: () => cleared = true,
            actions: [
              SelectionActionBarItem(
                icon: Icons.download_rounded,
                tooltip: 'Download selected as ZIP',
                onPressed: () => downloaded = true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byTooltip('Download selected as ZIP'), findsOneWidget);

    await tester.tap(find.byTooltip('Download selected as ZIP'));
    await tester.pump();
    expect(downloaded, isTrue);

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pump();
    expect(cleared, isTrue);
  });

  testWidgets('Selection action bar uses a menu instead of clipping actions', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var invokedAction = '';
    final actions = List<SelectionActionBarItem>.generate(
      8,
      (index) => SelectionActionBarItem(
        icon: Icons.star_outline_rounded,
        tooltip: 'Action ${index + 1}',
        onPressed: () => invokedAction = 'Action ${index + 1}',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: SelectionActionBar(
            selectedCount: 1,
            onClear: () {},
            actions: actions,
          ),
        ),
      ),
    );

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action 1'));
    await tester.pumpAndSettle();
    expect(invokedAction, 'Action 1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Selection action bar tolerates an empty action set', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(240, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: SelectionActionBar(
            selectedCount: 1,
            onClear: () {},
            actions: const [],
          ),
        ),
      ),
    );

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Free signup preserves direct purchase and shows all personal plans',
    (tester) async {
      final user = MockUser(
        uid: 'direct-purchase',
        email: 'purchase@example.com',
      );
      final auth = TestFirebaseAuth(mockUser: user, signedIn: true);
      final firestore = FakeFirebaseFirestore();
      SharedPreferences.setMockInitialValues({});
      await firestore.collection('users').doc(user.uid).set({
        'subscriptionStatus': 'free',
        'capacity': '1 GB',
        ...currentLegalFields(),
      });
      CheckoutPlanIntentStore.instance.remember(
        tier: 'ultra',
        interval: 'yearly',
      );
      addTearDown(CheckoutPlanIntentStore.instance.clear);
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionGate(
            auth: auth,
            user: user,
            firestore: firestore,
            billingChannel: BillingChannel.stripe,
            subscriptionCoordinator: SubscriptionCoordinator(
              firestore: firestore,
              checkoutApi: HttpStripeCheckoutApi(
                apiBaseUrl: Uri.parse('https://unused.example.test'),
              ),
            ),
            paidWorkspaceBuilder: (_) => const Text('Free workspace'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Choose your RonikCloud plan'), findsOneWidget);
      expect(find.text('Basic'), findsOneWidget);
      expect(find.text('Pro'), findsOneWidget);
      expect(find.text('Ultra'), findsOneWidget);
      expect(find.text('Continue with Ultra'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('Resumes setup for an unfinished personal account', (
    WidgetTester tester,
  ) async {
    final mockUser = MockUser(uid: 'uid-456', email: 'pending@example.com');
    final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
    final fakeFirestore = FakeFirebaseFirestore();

    await fakeFirestore.collection('users').doc('uid-456').set({
      'name': 'Pending User',
      'email': 'pending@example.com',
      'createdAt': '2024-01-01T00:00:00Z',
      'currentPeriodEnd': 'pending',
      'capacity': 'pending',
      'subscriptionStatus': 'pending',
      ...currentLegalFields(),
    });

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Finish account setup'), findsOneWidget);
    expect(find.text('Continue with Pro'), findsNothing);
  });

  testWidgets('Disabled purchase channel removes purchase controls', (
    WidgetTester tester,
  ) async {
    final mockUser = MockUser(
      uid: 'uid-app-store',
      email: 'subscriber@example.com',
    );
    final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
    final fakeFirestore = FakeFirebaseFirestore();

    await fakeFirestore.collection('users').doc('uid-app-store').set({
      'name': 'App Store Subscriber',
      'email': 'subscriber@example.com',
      'createdAt': '2026-01-01T00:00:00Z',
      'currentPeriodEnd': 'pending',
      'capacity': 'pending',
      'subscriptionStatus': 'pending',
      ...currentLegalFields(),
    });

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
        externalCheckoutEnabled: false,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('An active subscription is required'), findsOneWidget);
    expect(find.textContaining('In-app purchases are unavailable'), findsOneWidget);
    expect(find.text('Choose your RonikCloud plan'), findsNothing);
    expect(find.text('Continue with Pro'), findsNothing);
    expect(find.textContaining('Stripe'), findsNothing);
  });

  testWidgets('Business workspace cannot bypass the subscription gate', (
    WidgetTester tester,
  ) async {
    const uid = 'uid-business-unpaid';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'account_environment_uid_v1': uid,
      'account_environment_v1': 'business',
    });
    final mockUser = MockUser(uid: uid, email: 'business@example.com');
    final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
    final fakeFirestore = FakeFirebaseFirestore();
    await fakeFirestore.collection('users').doc(uid).set({
      'name': 'Business User',
      'email': 'business@example.com',
      'createdAt': '2026-01-01T00:00:00Z',
      'currentPeriodEnd': 'pending',
      'capacity': 'pending',
      'subscriptionStatus': 'pending',
      'twoFactorEnabled': false,
      ...currentLegalFields(),
    });

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _TestTwoFactorApi(),
        externalCheckoutEnabled: false,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(BusinessWorkspacePage), findsNothing);
    expect(find.text('An active subscription is required'), findsOneWidget);
  });

  testWidgets('Skips 2FA API for users without two-factor enabled', (
    WidgetTester tester,
  ) async {
    final mockUser = MockUser(uid: 'uid-789', email: 'plain@example.com');
    final mockAuth = TestFirebaseAuth(mockUser: mockUser, signedIn: true);
    final fakeFirestore = FakeFirebaseFirestore();

    await fakeFirestore.collection('users').doc('uid-789').set({
      'name': 'Plain User',
      'email': 'plain@example.com',
      'createdAt': '2024-01-01T00:00:00Z',
      'currentPeriodEnd': DateTime.now().add(const Duration(days: 365)).toIso8601String(),
      'subscriptionProvider': 'stripe',
      'subscriptionTier': 'pro',
      'capacity': '20 TB',
      'subscriptionStatus': 'active',
      'twoFactorEnabled': false,
      ...currentLegalFields(),
    });

    await tester.pumpWidget(
      CloudStorageApp(
        auth: mockAuth,
        firestore: fakeFirestore,
        twoFactorApi: const _FailingTwoFactorApi(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.byType(WorkspaceHomePage), findsOneWidget);
    expect(find.textContaining('Security check failed'), findsNothing);
  });
}

class _TestTwoFactorApi implements TwoFactorApi {
  const _TestTwoFactorApi();

  @override
  Future<void> disable() async {}

  @override
  Future<void> enable({required String secret, required String code}) async {}

  @override
  Future<TwoFactorStatus> fetchStatus() async {
    return const TwoFactorStatus(enabled: false, verified: true);
  }

  @override
  Future<TwoFactorStatus> verifyCode(String code) async {
    return const TwoFactorStatus(enabled: true, verified: true);
  }
}

class _FailingTwoFactorApi implements TwoFactorApi {
  const _FailingTwoFactorApi();

  @override
  Future<void> disable() async {}

  @override
  Future<void> enable({required String secret, required String code}) async {}

  @override
  Future<TwoFactorStatus> fetchStatus() async {
    throw const TwoFactorException('2FA API should not be called.');
  }

  @override
  Future<TwoFactorStatus> verifyCode(String code) async {
    throw const TwoFactorException('2FA API should not be called.');
  }
}

class _TourAuth extends MockFirebaseAuth {
  _TourAuth(MockUser user) : super(mockUser: user, signedIn: true);
  @override
  FirebaseApp get app => _TourFirebaseApp();
}

class _TourFirebaseApp implements FirebaseApp {
  @override
  String get name => '[DEFAULT]';
  @override
  FirebaseOptions get options => const FirebaseOptions(
    apiKey: 'test',
    appId: 'test',
    messagingSenderId: 'test',
    projectId: 'test',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
