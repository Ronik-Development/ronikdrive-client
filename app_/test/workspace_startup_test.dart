import 'helpers/firebase_test_auth.dart';
import 'dart:async';
import 'package:cloud_storage/src/authentication/login_password_vault.dart';
import 'package:cloud_storage/src/home/workspace_home_page.dart';
import 'package:cloud_storage/src/storage/wasabi_storage_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'workspace metadata loads while credential restoration is delayed',
    (tester) async {
      final keychain = Completer<String?>();
      var credentialReadStarted = false;
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'read' &&
            call.arguments['key'] == 'ronikdrive_login_email_v1') {
          credentialReadStarted = true;
          return keychain.future;
        }
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        LoginPasswordVault.instance.clear();
      });
      LoginPasswordVault.instance.clear(forgetPersisted: false);
      final user = MockUser(uid: 'slow-keychain', email: 'test@example.test');
      final auth = TestFirebaseAuth(mockUser: user, signedIn: true);
      final db = FakeFirebaseFirestore();
      SharedPreferences.setMockInitialValues({
        'workspace_walkthrough_completed_v1_slow-keychain': true,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceHomePage(
            auth: auth,
            user: user,
            firestore: db,
            storageService: WasabiStorageService(
              region: '',
              accessKey: '',
              secretKey: '',
              bucket: '',
            ),
          ),
        ),
      );
      try {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        expect(credentialReadStarted, isTrue);
        expect(keychain.isCompleted, isFalse);
        expect(find.text('Loading your workspace...'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        keychain.complete(null);
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
