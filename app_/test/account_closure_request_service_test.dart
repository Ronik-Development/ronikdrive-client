import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_storage/src/authentication/account_closure_request_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private receipt accepts only the exact first-party capability URL', () {
    final valid =
        'https://ronikcloud.com/deletion-status#request=${'a' * 64}&token=${'b' * 43}';
    expect(parseClosureReceiptUrl(valid)?.toString(), valid);
    final staging = valid.replaceFirst(
      'ronikcloud.com',
      'ronikcloud-test-7dcc2.web.app',
    );
    expect(parseClosureReceiptUrl(staging)?.toString(), staging);
    for (final invalid in [
      null,
      valid.replaceFirst('https:', 'http:'),
      valid.replaceFirst('ronikcloud.com', 'evil.example'),
      '$valid&extra=value',
      valid.replaceFirst('/deletion-status', ':443/deletion-status'),
      valid.replaceFirst('#', '?'),
    ]) {
      expect(parseClosureReceiptUrl(invalid), isNull);
    }
  });

  test(
    'authenticated closure request returns the server queue status',
    () async {
      final service = AccountClosureRequestService(
        auth: MockFirebaseAuth(
          mockUser: MockUser(uid: 'user', email: 'user@example.test'),
          signedIn: true,
        ),
        callable: () async => <String, Object?>{
          'success': true,
          'status': 'requested',
          'alreadyRequested': true,
        },
      );

      final receipt = await service.submit();

      expect(receipt.status, 'requested');
      expect(receipt.alreadyRequested, isTrue);
    },
  );

  test('signed-out closure request fails before calling the backend', () async {
    var called = false;
    final service = AccountClosureRequestService(
      auth: MockFirebaseAuth(signedIn: false),
      callable: () async {
        called = true;
        return <String, Object?>{};
      },
    );

    await expectLater(
      service.submit(),
      throwsA(
        isA<AccountClosureRequestException>().having(
          (error) => error.message,
          'message',
          contains('Sign in again'),
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('closure request failures do not expose backend details', () async {
    final service = AccountClosureRequestService(
      auth: MockFirebaseAuth(
        mockUser: MockUser(uid: 'user', email: 'user@example.test'),
        signedIn: true,
      ),
      callable: () async {
        throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'uid=private email=secret@example.test token=hidden',
        );
      },
    );

    await expectLater(
      service.submit(),
      throwsA(
        isA<AccountClosureRequestException>()
            .having(
              (error) => error.message,
              'fallback',
              contains('contact support'),
            )
            .having(
              (error) => error.message,
              'private detail',
              isNot(contains('secret@example.test')),
            ),
      ),
    );
  });
}
