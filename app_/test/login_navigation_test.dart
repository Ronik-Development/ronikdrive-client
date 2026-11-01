import 'dart:async';

import 'package:cloud_storage/src/authentication/login_page.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [360.0, 1440.0]) {
    for (final scale in [2.0, 3.0]) {
      testWidgets(
        'account form reflows at width $width and text scale $scale',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: LoginPage(
                auth: MockFirebaseAuth(),
                firestore: FakeFirebaseFirestore(),
                initialRegisterMode: true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final submit = find.widgetWithText(ElevatedButton, 'Create account');
          await tester.ensureVisible(submit);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getRect(submit).bottom, lessThanOrEqualTo(900));
        },
      );
    }
  }
  testWidgets('successful login is not trapped by unavailable encryption setup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = _ExistingAccountAuth();
    final encryption = Completer<bool>();
    var encryptionStarted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LoginPage(
                    auth: auth,
                    firestore: FakeFirebaseFirestore(),
                    standardEncryptionPreparer:
                        ({required uid, required email, required password}) {
                          encryptionStarted = true;
                          return encryption.future;
                        },
                  ),
                ),
              ),
              child: const Text('Open sign in'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'tester@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'existing-password',
    );
    final submit = find.widgetWithText(ElevatedButton, 'Login');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    // Authentication and token refresh complete; the setup endpoint never does.
    for (var i = 0; i < 35 && !encryptionStarted; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(auth.currentUser, isNotNull);
    expect(
      encryptionStarted,
      isTrue,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join(' | '),
    );
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(
      find.byType(LoginPage),
      findsNothing,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join(' | '),
    );
    expect(find.text('Open sign in'), findsOneWidget);
    encryption.complete(false);
    await tester.pumpAndSettle();
  });
}

class _ExistingAccountAuth extends MockFirebaseAuth {
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final result = await super.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _ExistingAccountCredential(result.user!);
  }
}

class _ExistingAccountCredential implements UserCredential {
  _ExistingAccountCredential(this.user);
  @override
  final User user;
  @override
  AdditionalUserInfo? get additionalUserInfo => null;
  @override
  AuthCredential? get credential => null;
}
