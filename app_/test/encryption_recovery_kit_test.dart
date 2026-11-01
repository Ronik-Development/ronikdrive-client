import 'dart:convert';
import 'dart:math';

import 'package:cloud_storage/src/security/encryption_recovery_kit.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const passphrase = 'four calm private recovery words';
  final accountSalt = List<int>.generate(16, (index) => index + 11);
  final standardKey = List<int>.generate(32, (index) => 255 - index);
  final material = StandardEncryptionRecoveryMaterial(
    accountUid: 'account-secret-uid',
    environmentId: 'private-production-project',
    encryptionSalt: accountSalt,
    standardKey: standardKey,
    createdAt: DateTime.utc(2026, 7, 24, 13, 30),
  );

  EncryptionRecoveryKitService service({int seed = 7}) {
    return EncryptionRecoveryKitService(
      random: Random(seed),
      keyDeriver: (value, salt) async {
        final digest = crypto.sha256.convert(<int>[
          ...utf8.encode(value),
          0,
          ...salt,
        ]);
        return SecretKey(digest.bytes);
      },
    );
  }

  Future<StandardEncryptionRecoveryMaterial> open(
    EncryptionRecoveryKitService recovery,
    List<int> encoded, {
    String password = passphrase,
    String uid = 'account-secret-uid',
    String environment = 'private-production-project',
    List<int>? salt,
  }) {
    return recovery.open(
      encodedKit: encoded,
      recoveryPassphrase: password,
      expectedAccountUid: uid,
      expectedEnvironmentId: environment,
      expectedEncryptionSalt: salt ?? accountSalt,
    );
  }

  test('round-trips a standard key while hiding account metadata', () async {
    final recovery = service();
    final encoded = await recovery.create(
      material: material,
      recoveryPassphrase: passphrase,
    );
    final visibleJson = utf8.decode(encoded);

    expect(visibleJson, contains(EncryptionRecoveryKitService.format));
    expect(visibleJson, isNot(contains(material.accountUid)));
    expect(visibleJson, isNot(contains(material.environmentId)));
    expect(visibleJson, isNot(contains(base64Encode(material.standardKey))));
    expect(
      visibleJson,
      isNot(contains(base64UrlEncode(material.encryptionSalt))),
    );

    final restored = await open(recovery, encoded);
    expect(restored.accountUid, material.accountUid);
    expect(restored.environmentId, material.environmentId);
    expect(restored.encryptionSalt, material.encryptionSalt);
    expect(restored.standardKey, material.standardKey);
    expect(restored.createdAt, material.createdAt);
  });

  test(
    'wrong passphrase and ciphertext tampering fail authentication',
    () async {
      final recovery = service();
      final encoded = await recovery.create(
        material: material,
        recoveryPassphrase: passphrase,
      );

      await expectLater(
        open(recovery, encoded, password: 'different private recovery words'),
        throwsA(
          isA<EncryptionRecoveryKitException>().having(
            (error) => error.failure,
            'failure',
            EncryptionRecoveryKitFailure.authenticationFailed,
          ),
        ),
      );

      final json = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
      final cipher = json['cipher'] as Map<String, dynamic>;
      final ciphertext = cipher['ciphertext'] as String;
      final tamperIndex = ciphertext.length ~/ 2;
      cipher['ciphertext'] =
          '${ciphertext.substring(0, tamperIndex)}'
          '${ciphertext[tamperIndex] == 'A' ? 'B' : 'A'}'
          '${ciphertext.substring(tamperIndex + 1)}';
      await expectLater(
        open(recovery, utf8.encode(jsonEncode(json))),
        throwsA(
          isA<EncryptionRecoveryKitException>().having(
            (error) => error.failure,
            'failure',
            EncryptionRecoveryKitFailure.authenticationFailed,
          ),
        ),
      );
    },
  );

  test(
    'binds a kit to its account, environment, and encryption salt',
    () async {
      final recovery = service();
      final encoded = await recovery.create(
        material: material,
        recoveryPassphrase: passphrase,
      );

      await expectLater(
        open(recovery, encoded, uid: 'another-account'),
        throwsA(
          isA<EncryptionRecoveryKitException>().having(
            (error) => error.failure,
            'failure',
            EncryptionRecoveryKitFailure.accountMismatch,
          ),
        ),
      );
      await expectLater(
        open(recovery, encoded, environment: 'staging-project'),
        throwsA(
          isA<EncryptionRecoveryKitException>().having(
            (error) => error.failure,
            'failure',
            EncryptionRecoveryKitFailure.environmentMismatch,
          ),
        ),
      );
      await expectLater(
        open(recovery, encoded, salt: List<int>.filled(accountSalt.length, 99)),
        throwsA(
          isA<EncryptionRecoveryKitException>().having(
            (error) => error.failure,
            'failure',
            EncryptionRecoveryKitFailure.encryptionSaltMismatch,
          ),
        ),
      );
    },
  );

  test('rejects ambiguous fields, padded binary, and KDF downgrade', () async {
    final recovery = service();
    final encoded = await recovery.create(
      material: material,
      recoveryPassphrase: passphrase,
    );

    Map<String, dynamic> decoded() =>
        jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;

    final unexpected = decoded()..['accountUid'] = material.accountUid;
    await expectLater(
      open(recovery, utf8.encode(jsonEncode(unexpected))),
      throwsA(
        isA<EncryptionRecoveryKitException>().having(
          (error) => error.failure,
          'failure',
          EncryptionRecoveryKitFailure.invalidFormat,
        ),
      ),
    );

    final padded = decoded();
    final paddedKdf = padded['kdf'] as Map<String, dynamic>;
    paddedKdf['salt'] = '${paddedKdf['salt']}=';
    await expectLater(
      open(recovery, utf8.encode(jsonEncode(padded))),
      throwsA(
        isA<EncryptionRecoveryKitException>().having(
          (error) => error.failure,
          'failure',
          EncryptionRecoveryKitFailure.invalidFormat,
        ),
      ),
    );

    final downgraded = decoded();
    final downgradedKdf = downgraded['kdf'] as Map<String, dynamic>;
    downgradedKdf['iterations'] = 1;
    await expectLater(
      open(recovery, utf8.encode(jsonEncode(downgraded))),
      throwsA(
        isA<EncryptionRecoveryKitException>().having(
          (error) => error.failure,
          'failure',
          EncryptionRecoveryKitFailure.invalidFormat,
        ),
      ),
    );
  });

  test('requires a non-trivial recovery passphrase', () async {
    await expectLater(
      service().create(
        material: material,
        recoveryPassphrase: 'aaaaaaaaaaaaaaaa',
      ),
      throwsA(
        isA<EncryptionRecoveryKitException>().having(
          (error) => error.failure,
          'failure',
          EncryptionRecoveryKitFailure.invalidInput,
        ),
      ),
    );
  });
}
