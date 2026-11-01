import 'package:cloud_storage/src/security/encryption_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a second device derives the same standard key from account recovery inputs',
    () async {
      final service = EncryptionService.instance;
      final salt = List<int>.generate(16, (index) => index * 3);
      final firstDevice = await service.deriveKey(
        password: 'correct horse battery staple',
        salt: salt,
      );
      final secondDevice = await service.deriveKey(
        password: 'correct horse battery staple',
        salt: salt,
      );
      expect(
        await secondDevice.extractBytes(),
        await firstDevice.extractBytes(),
      );
    },
  );

  test(
    'password change and corrupted content fail authentication, not silently',
    () async {
      final service = EncryptionService.instance;
      final salt = List<int>.generate(16, (index) => 31 - index);
      final originalKey = await service.deriveKey(
        password: 'original-password-value',
        salt: salt,
      );
      final changedPasswordKey = await service.deriveKey(
        password: 'changed-password-value',
        salt: salt,
      );
      final encrypted = await service.encryptData(<int>[
        1,
        2,
        3,
        4,
      ], originalKey);
      await expectLater(
        service.decryptData(encrypted, changedPasswordKey),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      encrypted[encrypted.length ~/ 2] ^= 0xff;
      await expectLater(
        service.decryptData(encrypted, originalKey),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );

  group('EncryptionService secure shard tokens', () {
    test(
      'are deterministic and opaque for the same key/object/index',
      () async {
        final service = EncryptionService.instance;
        final key = SecretKey(List<int>.generate(32, (index) => index));

        final first = await service.deriveSecureShardToken(
          secretKey: key,
          objectKey: 'owner/objects/aa/bb/file-token',
          shardIndex: 7,
        );
        final second = await service.deriveSecureShardToken(
          secretKey: key,
          objectKey: 'owner/objects/aa/bb/file-token',
          shardIndex: 7,
        );
        final otherIndex = await service.deriveSecureShardToken(
          secretKey: key,
          objectKey: 'owner/objects/aa/bb/file-token',
          shardIndex: 8,
        );
        final otherObject = await service.deriveSecureShardToken(
          secretKey: key,
          objectKey: 'owner/objects/aa/bb/other-token',
          shardIndex: 7,
        );

        expect(second, first);
        expect(otherIndex, isNot(first));
        expect(otherObject, isNot(first));
        expect(first, isNot('000007'));
        expect(first, isNot(contains('/')));
        expect(first.length, greaterThan(24));
      },
    );
  });
}
