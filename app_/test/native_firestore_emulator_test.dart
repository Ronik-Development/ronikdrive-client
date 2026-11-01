import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as platform;
import 'package:cloud_storage/src/linux_cloud/native_linux_cloud.dart';
import 'package:cloud_storage/src/storage/folder_document_writer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_cloud_fixture.dart' show MemoryNativeSessionStore;

// Run only under the dedicated demo-project emulator configuration. No Admin
// SDK, production API key, rules bypass, real account or email is used.
const _enabled = bool.fromEnvironment('RONIKDRIVE_NATIVE_EMULATOR_TEST');
const _project = 'demo-ronikdrive-native';
Matcher _code(String code) =>
    isA<FirebaseException>().having((error) => error.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native Auth and Firestore enforce the real application rules for two accounts',
    () async {
      // The widget test binding otherwise replaces every HTTP request with a
      // synthetic 400 response. This opt-in test uses only fixed loopback
      // emulator authorities; production adapters remain unchanged.
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() {
        HttpOverrides.global = previousHttp;
      });
      final previousCore = FirebasePlatform.instance;
      final previousPacking = Firebase.delegatePackingProperty;
      final previousAuth = FirebaseAuthPlatform.instance;
      final previousFactory = platform.FieldValueFactoryPlatform.instance;
      final keyring = MemoryNativeSessionStore();
      final native = NativeLinuxCloud(
        store: keyring,
        authEmulatorPort: 19099,
        firestoreEmulatorPort: 18080,
        automaticallyRefresh: false,
      );
      // Reset a test-only lazy facade; production registration must run before
      // the first Firebase access and never changes this testing property.
      Firebase.delegatePackingProperty = null;
      native.register();
      final app = await Firebase.initializeApp(
        name: 'native-emulator',
        options: const FirebaseOptions(
          apiKey: 'AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          appId: '1:000000000000:web:nativeemulatortest',
          messagingSenderId: '000000000000',
          projectId: _project,
        ),
      );
      addTearDown(() async {
        await app.delete();
        FirebasePlatform.instance = previousCore;
        Firebase.delegatePackingProperty = previousPacking;
        FirebaseAuthPlatform.instance = previousAuth;
        platform.FieldValueFactoryPlatform.instance = previousFactory;
      });
      final auth = FirebaseAuth.instanceFor(app: app);
      final database = FirebaseFirestore.instanceFor(app: app);
      final nonce = DateTime.now().microsecondsSinceEpoch;
      const password = 'local-only-synthetic-password-21';
      final owner = await auth.createUserWithEmailAndPassword(
        email: 'native-owner-$nonce@example.test',
        password: password,
      );
      final uid = owner.user!.uid;
      printOnFailure('Completed emulator owner sign-up.');
      final timestamp = DateTime.now().toUtc().toIso8601String();
      final profile = database.doc('users/$uid');
      await profile.set({
        'profilePrivacyVersion': 1,
        'createdAt': timestamp,
        'currentPeriodEnd': 'pending',
        'capacity': 'pending',
        'subscriptionStatus': 'pending',
        'legalVersion': '2026-06-12',
        'termsAcceptedAt': timestamp,
        'privacyAcknowledgedAt': timestamp,
        'acceptableUseAcceptedAt': timestamp,
        'cancellationRefundAcknowledgedAt': timestamp,
        'dataRetentionAcknowledgedAt': timestamp,
        'subprocessorsAcknowledgedAt': timestamp,
        'legalAcceptanceSource': 'signup',
      });
      expect((await profile.get()).data()!['subscriptionStatus'], 'pending');
      printOnFailure('Completed permitted profile creation/read.');
      await expectLater(
        profile.update({
          'subscriptionStatus': 'active',
          'capacityBytes': 2000000000000,
        }),
        throwsA(_code('permission-denied')),
      );
      await expectLater(
        database.doc('users/$uid/private/security').get(),
        throwsA(_code('permission-denied')),
      );
      printOnFailure('Completed protected billing/security denials.');

      final folder = database.doc('folders/native-$nonce');
      final folderPayload = <String, dynamic>{
        'uid': uid,
        'encryptedName': 'enc--bmF0aXZlLWZvbGRlcg',
        'metadataEncryption': 'standard-aes-gcm-v1',
        'color': '#336699',
        'updatedAt': FieldValue.serverTimestamp(),
        'systemFolder': false,
      };
      // Reproduce the error that used to prevent the workspace from reaching
      // its create fallback for a new folder.
      await expectLater(
        folder.update(folderPayload),
        throwsA(_code('permission-denied')),
      );
      await upsertEncryptedFolderDocument(folder, folderPayload);
      final createdFolder = (await folder.get()).data()!;
      expect(createdFolder['uid'], uid);
      expect(createdFolder['createdAt'], isA<Timestamp>());
      await upsertEncryptedFolderDocument(folder, {
        ...folderPayload,
        'encryptedName': 'enc--cmVuYW1lZC1mb2xkZXI',
      });
      final renamedFolder = (await folder.get()).data()!;
      expect(renamedFolder['createdAt'], createdFolder['createdAt']);
      expect(renamedFolder['encryptedName'], 'enc--cmVuYW1lZC1mb2xkZXI');
      printOnFailure('Completed encrypted folder creation/read.');
      final query = database
          .collection('folders')
          .where('uid', isEqualTo: uid)
          .orderBy(FieldPath.documentId);
      final initial = await query.get();
      expect(initial.docs.map((doc) => doc.id), contains(folder.id));
      printOnFailure('Completed owner query.');

      final live = query
          .snapshots()
          .firstWhere(
            (snapshot) =>
                snapshot.docs.any((doc) => doc.data()['color'] == '#112233'),
          )
          .timeout(const Duration(seconds: 15));
      final batch = database.batch()
        ..update(folder, {
          'color': '#112233',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      await batch.commit();
      final updated = await live;
      expect(updated.docs.single.data()['updatedAt'], isA<Timestamp>());
      printOnFailure('Completed batch transform and live snapshot.');
      await database.runTransaction((transaction) async {
        final current = await transaction.get(folder);
        expect(current.data()!['color'], '#112233');
        transaction.update(folder, {'color': '#445566'});
      });
      expect((await folder.get()).data()!['color'], '#445566');
      printOnFailure('Completed transaction.');

      // Restore the actual emulator-issued refresh credential and retain UID.
      // Force the real emulator's refresh-token path rather than inspecting a
      // JWT locally or bypassing normal sign-in.
      await auth.currentUser!.getIdToken(true);
      expect(auth.currentUser!.uid, uid);
      await auth.signOut();
      await auth.createUserWithEmailAndPassword(
        email: 'native-other-$nonce@example.test',
        password: password,
      );
      await expectLater(profile.get(), throwsA(_code('permission-denied')));
      await expectLater(folder.get(), throwsA(_code('permission-denied')));
      await expectLater(
        folder.update({'color': '#000000'}),
        throwsA(_code('permission-denied')),
      );
      await expectLater(
        upsertEncryptedFolderDocument(folder, {
          ...folderPayload,
          'uid': auth.currentUser!.uid,
        }),
        throwsA(_code('permission-denied')),
      );
      await expectLater(query.get(), throwsA(_code('permission-denied')));
      await auth.signOut();
      await auth.signInWithEmailAndPassword(
        email: 'native-owner-$nonce@example.test',
        password: password,
      );
      expect(auth.currentUser!.uid, uid);
      await folder.delete();
      expect((await query.get()).docs, isEmpty);
    },
    skip: !_enabled
        ? 'Run with the dedicated local Auth/Firestore emulators and RONIKDRIVE_NATIVE_EMULATOR_TEST=true.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
