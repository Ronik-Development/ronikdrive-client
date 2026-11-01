import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_storage/src/linux_cloud/native_firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/native_cloud_fixture.dart';

Matcher _authCode(String code) =>
    isA<FirebaseAuthException>().having((e) => e.code, 'code', code);
Matcher _functionCode(String code) =>
    isA<FirebaseFunctionsException>().having((e) => e.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativeCloudFixture fixture;
  setUp(() async {
    fixture = NativeCloudFixture();
    await fixture.initialize();
  });
  tearDown(() async {
    await fixture.dispose();
  });

  test(
    'public Firebase Auth preserves existing customer UID, profile and token claims',
    () async {
      final credential = await fixture.auth.signInWithEmailAndPassword(
        email: 'customer@example.test',
        password: 'synthetic-password',
      );
      final user = credential.user!;
      expect(user.uid, 'existing-web-customer');
      expect(fixture.auth.currentUser?.uid, user.uid);
      expect(user.emailVerified, true);
      expect(user.providerData.single.providerId, 'password');
      expect(user.providerData.single.uid, user.uid);
      expect(
        user.metadata.creationTime,
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
      final token = await user.getIdTokenResult();
      expect(token.claims?['sub'], user.uid);
      expect(token.signInProvider, 'password');
      expect(token.expirationTime!.isAfter(DateTime.now()), true);
      expect(user.refreshToken, null);
    },
  );

  test(
    'auth state emits sign-in/sign-out once, without treating refresh as a new login',
    () async {
      final states = <String?>[];
      final subscription = fixture.auth.authStateChanges().listen(
        (user) => states.add(user?.uid),
      );
      await Future<void>.delayed(Duration.zero);
      final user = (await fixture.auth.signInWithEmailAndPassword(
        email: 'user@example.test',
        password: 'synthetic-password',
      )).user!;
      await user.getIdToken(true);
      await fixture.auth.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(states, [null, 'existing-web-customer', null]);
      await subscription.cancel();
    },
  );

  test(
    'updating a profile refreshes both current user and the original user object',
    () async {
      final user = (await fixture.auth.signInWithEmailAndPassword(
        email: 'user@example.test',
        password: 'synthetic-password',
      )).user!;
      await user.updateDisplayName('Test Person');
      expect(user.displayName, 'Test Person');
      expect(fixture.auth.currentUser?.displayName, 'Test Person');
      await user.updateDisplayName(null);
      expect(user.displayName, null);
      final deletion = fixture.requests
          .where((request) => request.url.path.endsWith('accounts:update'))
          .last;
      expect((jsonDecode(deletion.body) as Map)['deleteAttribute'], [
        'DISPLAY_NAME',
      ]);
    },
  );

  test(
    'reauthentication with another account fails without changing the current account',
    () async {
      final user = (await fixture.auth.signInWithEmailAndPassword(
        email: 'user@example.test',
        password: 'synthetic-password',
      )).user!;
      fixture.nextSignInUid = 'another-customer';
      await expectLater(
        user.reauthenticateWithCredential(
          EmailAuthProvider.credential(
            email: 'other@example.test',
            password: 'synthetic-password',
          ),
        ),
        throwsA(_authCode('user-mismatch')),
      );
      expect(fixture.auth.currentUser?.uid, 'existing-web-customer');
      expect(await user.getIdToken(), isNotNull);
    },
  );

  test(
    'password reset uses Firebase locale and documented REST action settings',
    () async {
      await fixture.auth.setLanguageCode('cs');
      await fixture.auth.sendPasswordResetEmail(
        email: 'user@example.test',
        actionCodeSettings: ActionCodeSettings(
          url: 'https://example.test/account',
        ),
      );
      final request = fixture.requests.single;
      expect(request.headers['X-Firebase-Locale'], 'cs');
      expect(jsonDecode(request.body), {
        'requestType': 'PASSWORD_RESET',
        'email': 'user@example.test',
        'continueUrl': 'https://example.test/account',
        'canHandleCodeInApp': false,
      });
    },
  );

  test(
    'production user tokens cannot be redirected to a cleartext emulator',
    () async {
      await expectLater(
        fixture.auth.useAuthEmulator('127.0.0.1', 9099),
        throwsA(_authCode('operation-not-allowed')),
      );
      expect(fixture.requests, isEmpty);
    },
  );

  test(
    'native Core shares initialization and does not expose an unfinished app',
    () async {
      var initializations = 0;
      final ready = Completer<void>();
      final core = NativeFirebaseCore(
        initializeServices: (_) async {
          initializations++;
          await ready.future;
        },
        disposeServices: (_) async {},
      );
      const options = FirebaseOptions(
        apiKey: 'test',
        appId: 'test',
        messagingSenderId: '123',
        projectId: 'demo-native',
      );
      final first = core.initializeApp(name: 'pending', options: options);
      final second = core.initializeApp(name: 'pending', options: options);
      expect(initializations, 1);
      expect(core.apps, isEmpty);
      expect(() => core.app('pending'), throwsA(isA<FirebaseException>()));
      ready.complete();
      final apps = await Future.wait([first, second]);
      expect(identical(apps.first, apps.last), true);
      expect(core.apps, hasLength(1));
      expect(apps.first.isAutomaticDataCollectionEnabled, false);
      await apps.first.delete();
      expect(core.apps, isEmpty);
    },
  );

  test(
    'native callable attaches the signed-in customer token and decodes integers',
    () async {
      await fixture.auth.signInWithEmailAndPassword(
        email: 'user@example.test',
        password: 'synthetic-password',
      );
      fixture.functionHandler = (request) {
        expect(request.followRedirects, false);
        expect(
          request.url,
          Uri.parse(
            'https://europe-west1-${NativeCloudFixture.projectId}.cloudfunctions.net/readPlan',
          ),
        );
        expect(
          NativeCloudFixture.tokenUid(
            request.headers['Authorization']!.substring(7),
          ),
          'existing-web-customer',
        );
        expect(jsonDecode(request.body), {
          'data': {'limit': 10},
        });
        return NativeCloudFixture.json({
          'result': {
            'bytes': {
              '@type': 'type.googleapis.com/google.protobuf.Int64Value',
              'value': '2199023255552',
            },
          },
        });
      };
      final functions = FirebaseFunctions.instanceFor(
        app: fixture.app,
        region: 'europe-west1',
      );
      final result = await functions.httpsCallable('readPlan').call({
        'limit': 10,
      });
      expect(result.data, {'bytes': 2199023255552});
    },
  );

  test('a callable redirect is refused without a second request', () async {
    fixture.functionHandler = (_) => http.Response(
      '',
      302,
      headers: {'location': 'https://untrusted.example.test'},
    );
    final functions = FirebaseFunctions.instanceFor(
      app: fixture.app,
      region: 'europe-west1',
    );
    await expectLater(
      functions.httpsCallable('readPlan').call(),
      throwsA(_functionCode('unavailable')),
    );
    expect(fixture.requests, hasLength(1));
  });

  test(
    'callable results from a signed-out account cannot reach the replacement account',
    () async {
      await fixture.auth.signInWithEmailAndPassword(
        email: 'user@example.test',
        password: 'synthetic-password',
      );
      final response = Completer<http.Response>();
      final started = Completer<void>();
      fixture.functionHandler = (_) {
        started.complete();
        return response.future;
      };
      final functions = FirebaseFunctions.instanceFor(
        app: fixture.app,
        region: 'europe-west1',
      );
      final call = functions.httpsCallable('readPlan').call();
      final rejected = expectLater(call, throwsA(_functionCode('cancelled')));
      await started.future;
      await fixture.auth.signOut();
      response.complete(
        NativeCloudFixture.json({
          'result': {'private': 'original-customer-data'},
        }),
      );
      await rejected;
    },
  );

  test(
    'callable errors retain public categories and details while hiding provider diagnostics',
    () async {
      fixture.functionHandler = (_) => NativeCloudFixture.json({
        'error': {
          'status': 'FAILED_PRECONDITION',
          'message': 'private provider diagnostic and receipt',
          'details': {'reason': 'requires-two-factor'},
        },
      }, 400);
      final functions = FirebaseFunctions.instanceFor(
        app: fixture.app,
        region: 'europe-west1',
      );
      try {
        await functions.httpsCallable('protectedOperation').call();
        fail('Expected rejection');
      } on FirebaseFunctionsException catch (error) {
        expect(error.code, 'failed-precondition');
        expect(error.details, {'reason': 'requires-two-factor'});
        expect(error.message, isNot(contains('private provider diagnostic')));
      }
    },
  );
}
