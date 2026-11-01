import 'dart:convert';
import 'dart:io';
import 'package:cloud_storage/src/business/business_key_verification_page.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    await font.load();
  });
  for (final width in [1280.0, 360.0]) {
    testWidgets('verification controls remain readable at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'synthetic-administrator'),
        signedIn: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          // Pin the fixture theme; renderer baselines remain host-specific.
          theme: ThemeData(
            fontFamily: 'Inter',
            platform: TargetPlatform.android,
          ),
          home: Scaffold(
            body: BusinessKeyVerificationPage.forTesting(
              auth: auth,
              companyId: 'synthetic-company',
              state: {
                'canApprove': true,
                'canEnroll': true,
                'candidates': [
                  {
                    'uid': 'synthetic-member-with-a-long-account-identifier',
                    'keyId': 'synthetic-public-key-id',
                    'scopes': [
                      'company_shared',
                      'metadata:company',
                      'metadata:group:sample',
                    ],
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Verify key'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Enroll company protection'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/business_verification_${width.toInt()}${Platform.isLinux ? '_linux' : ''}.png',
        ),
      );
    });
  }
  testWidgets(
    'unverified API record is never offered as a trusted bootstrap record',
    (tester) async {
      final policy =
          jsonDecode(
                File(
                  'test/fixtures/business_recipient_approval_v1.json',
                ).readAsStringSync(),
              )
              as Map;
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'synthetic-administrator'),
        signedIn: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessKeyVerificationPage.forTesting(
              auth: auth,
              companyId: 'synthetic-company',
              state: {
                'recipientTrust': policy,
                'canApprove': true,
                'candidates': [],
              },
            ),
          ),
        ),
      );
      expect(find.text('Public verification record'), findsNothing);
      expect(find.text(policy['publicKey'] as String), findsNothing);
      expect(find.text('Company fingerprint'), findsNothing);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Publish approved keys'),
      );
      expect(button.onPressed, isNull);
    },
  );
}
