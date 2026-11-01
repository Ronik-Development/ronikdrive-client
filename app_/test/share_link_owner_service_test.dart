import 'package:cloud_storage/src/share/share_link_owner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'emergency revocation accepts only a bounded complete response',
    () async {
      final service = ShareLinkOwnerService(
        callable: (functionName) async {
          expect(functionName, 'revokeAllShareLinks');
          return <String, dynamic>{
            'ok': true,
            'revokedCount': 4,
            'complete': true,
          };
        },
      );

      final result = await service.revokeAll();
      expect(result.revokedCount, 4);
      expect(result.complete, isTrue);
    },
  );

  test('emergency revocation rejects malformed callable data', () async {
    for (final response in <Map<String, dynamic>>[
      <String, dynamic>{},
      <String, dynamic>{'ok': true, 'revokedCount': -1, 'complete': true},
      <String, dynamic>{'ok': true, 'revokedCount': 1, 'complete': 'yes'},
    ]) {
      final service = ShareLinkOwnerService(callable: (_) async => response);
      await expectLater(
        service.revokeAll(),
        throwsA(
          isA<ShareOwnerException>().having(
            (error) => error.kind,
            'kind',
            ShareOwnerFailureKind.invalidResponse,
          ),
        ),
      );
    }
  });

  test('unexpected callable failures expose no provider message', () async {
    final service = ShareLinkOwnerService(
      callable: (_) async =>
          throw StateError('provider.example token=secret file=board-plan.pdf'),
    );

    await expectLater(
      service.revokeAll(),
      throwsA(
        isA<ShareOwnerException>()
            .having(
              (error) => error.kind,
              'kind',
              ShareOwnerFailureKind.unavailable,
            )
            .having(
              (error) => error.toString(),
              'redacted text',
              isNot(contains('provider.example')),
            ),
      ),
    );
  });
}
