import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_storage/src/authentication/account_deletion_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('callable deletion errors never expose provider details', () async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'user', email: 'user@example.test'),
      signedIn: true,
    );
    final service = AccountDeletionService(
      auth: auth,
      callable: () async {
        await Future<void>.delayed(Duration.zero);
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message:
              'host=private.example object=customer/private.pdf token=secret',
        );
      },
    );

    await expectLater(
      service.deleteAccount(),
      throwsA(
        isA<AccountDeletionException>()
            .having(
              (error) => error.message,
              'safe recovery',
              contains('required safety step'),
            )
            .having(
              (error) => error.message,
              'provider detail',
              isNot(contains('private.example')),
            )
            .having(
              (error) => error.message,
              'object detail',
              isNot(contains('private.pdf')),
            ),
      ),
    );
  });

  test(
    'REST deletion errors use status only and preserve retry access',
    () async {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'user', email: 'user@example.test'),
        signedIn: true,
      );
      final service = AccountDeletionService(
        auth: auth,
        callable: () async => throw StateError('private callable response'),
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode(<String, dynamic>{
              'error': <String, dynamic>{
                'status': 'UNAVAILABLE',
                'message': 'host=private.example token=secret',
              },
            }),
            503,
          ),
        ),
      );

      await expectLater(
        service.deleteAccount(),
        throwsA(
          isA<AccountDeletionException>()
              .having(
                (error) => error.message,
                'safe recovery',
                contains('remains available'),
              )
              .having(
                (error) => error.message,
                'provider detail',
                isNot(contains('private.example')),
              ),
        ),
      );
    },
  );

  test('signed-out deletion fails closed before any request', () async {
    var called = false;
    final service = AccountDeletionService(
      auth: MockFirebaseAuth(signedIn: false),
      callable: () async {
        called = true;
      },
    );

    await expectLater(
      service.deleteAccount(),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.message,
          'message',
          contains('Sign in again'),
        ),
      ),
    );
    expect(called, isFalse);
  });
}
