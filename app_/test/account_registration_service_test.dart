import 'dart:convert';
import 'package:cloud_storage/src/authentication/account_registration_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<void> register(AccountRegistrationService service) => service.register(
    username: '333',
    legalVersion: '2026-09-10',
    legalAcceptedAt: '2026-09-11T12:00:00Z',
    productUpdatesOptIn: false,
    recoveryEmailProvided: false,
    createdAt: '2026-09-11T12:00:00Z',
  );
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    test(
      '$platform registers a username through authenticated callable HTTPS',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        var called = false;
        final auth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'test-user'),
          signedIn: true,
        );
        final service = AccountRegistrationService(
          auth: auth,
          restUri: Uri.https('example.test', '/registerAccountProfile'),
          httpClient: MockClient((request) async {
            called = true;
            expect(request.headers['Authorization'], startsWith('Bearer '));
            expect(jsonDecode(request.body)['data']['username'], '333');
            expect(
              jsonDecode(request.body)['data'].containsKey('uid'),
              isFalse,
            );
            return http.Response('{"result":{"ok":true}}', 200);
          }),
        );
        await register(service);
        expect(called, isTrue);
      },
    );
  }
  test(
    'preserves callable error code without reflecting provider details',
    () async {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'test-user'),
        signedIn: true,
      );
      final service = AccountRegistrationService(
        auth: auth,
        preferRest: true,
        restUri: Uri.https('example.test', '/registerAccountProfile'),
        httpClient: MockClient(
          (_) async => http.Response(
            '{"error":{"status":"ALREADY_EXISTS","message":"secret-provider-detail"}}',
            409,
          ),
        ),
      );
      await expectLater(
        register(service),
        throwsA(
          isA<AccountRegistrationException>()
              .having((e) => e.code, 'code', 'already-exists')
              .having(
                (e) => e.message,
                'safe message',
                isNot(contains('secret-provider-detail')),
              ),
        ),
      );
    },
  );
  test(
    'rejects signed-out registration before making a network request',
    () async {
      final service = AccountRegistrationService(
        auth: MockFirebaseAuth(),
        preferRest: true,
        httpClient: MockClient((_) async => throw StateError('Must not send')),
      );
      await expectLater(
        register(service),
        throwsA(
          isA<AccountRegistrationException>().having(
            (e) => e.code,
            'code',
            'unauthenticated',
          ),
        ),
      );
    },
  );
  test(
    'rejects malformed success instead of silently accepting unprovisioned profile',
    () async {
      final service = AccountRegistrationService(
        auth: MockFirebaseAuth(
          mockUser: MockUser(uid: 'test-user'),
          signedIn: true,
        ),
        preferRest: true,
        restUri: Uri.https('example.test', '/registerAccountProfile'),
        httpClient: MockClient(
          (_) async => http.Response('<html>gateway</html>', 200),
        ),
      );
      await expectLater(
        register(service),
        throwsA(
          isA<AccountRegistrationException>().having(
            (e) => e.code,
            'code',
            'internal',
          ),
        ),
      );
    },
  );
}
