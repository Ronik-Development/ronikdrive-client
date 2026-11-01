import 'dart:convert';
import 'dart:math';

import 'package:cloud_storage/src/security/business_encryption_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BusinessEncryptionService', () {
    test('wraps one random file key independently for two members', () async {
      final service = BusinessEncryptionService(random: Random(11));
      final aliceProtection = SecretKey(List<int>.filled(32, 1));
      final bobProtection = SecretKey(List<int>.filled(32, 2));
      final aliceIdentity = await service.createIdentity(
        accountProtectionKey: aliceProtection,
      );
      final bobIdentity = await service.createIdentity(
        accountProtectionKey: bobProtection,
      );
      final material = await service.createFileEncryptionMaterial(
        objectKey: 'company_opaque/shared/objects/aa/bb/file-token',
        recipients: <BusinessEncryptionRecipient>[
          _recipient('alice', aliceIdentity),
          _recipient('bob', bobIdentity),
        ],
      );

      final aliceFileKey = await service.openFileKey(
        objectKey: 'company_opaque/shared/objects/aa/bb/file-token',
        currentUid: 'alice',
        identity: aliceIdentity,
        envelope: material.envelopes['alice']!,
        accountProtectionKey: aliceProtection,
      );
      final bobFileKey = await service.openFileKey(
        objectKey: 'company_opaque/shared/objects/aa/bb/file-token',
        currentUid: 'bob',
        identity: bobIdentity,
        envelope: material.envelopes['bob']!,
        accountProtectionKey: bobProtection,
      );

      expect(
        await aliceFileKey.extractBytes(),
        await material.fileKey.extractBytes(),
      );
      expect(
        await bobFileKey.extractBytes(),
        await material.fileKey.extractBytes(),
      );
      expect(
        material.envelopes['alice']!.encryptedFileKeyBase64,
        isNot(material.envelopes['bob']!.encryptedFileKeyBase64),
      );
      expect(aliceIdentity.publicKeyBase64, isNot(contains('=')));
      expect(aliceIdentity.wrappedPrivateKeyBase64, isNot(contains('=')));
      expect(
        material.envelopes.values.every(
          (envelope) =>
              !envelope.ephemeralPublicKeyBase64.contains('=') &&
              !envelope.encryptedFileKeyBase64.contains('='),
        ),
        isTrue,
      );
    });

    test('binds a file-key envelope to its object and recipient', () async {
      final service = BusinessEncryptionService(random: Random(21));
      final protection = SecretKey(List<int>.filled(32, 3));
      final identity = await service.createIdentity(
        accountProtectionKey: protection,
      );
      final material = await service.createFileEncryptionMaterial(
        objectKey: 'company_opaque/shared/objects/aa/bb/original',
        recipients: <BusinessEncryptionRecipient>[
          _recipient('member-1', identity),
        ],
      );

      await expectLater(
        service.openFileKey(
          objectKey: 'company_opaque/shared/objects/aa/bb/different',
          currentUid: 'member-1',
          identity: identity,
          envelope: material.envelopes['member-1']!,
          accountProtectionKey: protection,
        ),
        throwsA(isA<BusinessEncryptionException>()),
      );
      await expectLater(
        service.openFileKey(
          objectKey: 'company_opaque/shared/objects/aa/bb/original',
          currentUid: 'member-2',
          identity: identity,
          envelope: material.envelopes['member-1']!,
          accountProtectionKey: protection,
        ),
        throwsA(isA<BusinessEncryptionException>()),
      );
    });

    test(
      'does not expose raw private or file-key bytes in stored maps',
      () async {
        final service = BusinessEncryptionService(random: Random(31));
        final protectionBytes = List<int>.generate(32, (index) => index + 1);
        final protection = SecretKey(protectionBytes);
        final identity = await service.createIdentity(
          accountProtectionKey: protection,
        );
        final material = await service.createFileEncryptionMaterial(
          objectKey: 'company_opaque/shared/objects/aa/bb/private',
          recipients: <BusinessEncryptionRecipient>[
            _recipient('member-1', identity),
          ],
        );
        final rawFileKey = await material.fileKey.extractBytes();
        final serialized = jsonEncode(<String, Object?>{
          'identity': identity.toMap(),
          'envelope': material.envelopes['member-1']!.toMap(),
        });

        expect(serialized, isNot(contains(base64UrlEncode(protectionBytes))));
        expect(serialized, isNot(contains(base64UrlEncode(rawFileKey))));
        expect(serialized, isNot(contains('privateKeyBase64')));
        expect(serialized, contains('wrappedPrivateKeyBase64'));
      },
    );

    test('rejects a mismatched account protection key', () async {
      final service = BusinessEncryptionService(random: Random(41));
      final identity = await service.createIdentity(
        accountProtectionKey: SecretKey(List<int>.filled(32, 4)),
      );
      final material = await service.createFileEncryptionMaterial(
        objectKey: 'company_opaque/shared/objects/aa/bb/protected',
        recipients: <BusinessEncryptionRecipient>[
          _recipient('member-1', identity),
        ],
      );

      await expectLater(
        service.openFileKey(
          objectKey: 'company_opaque/shared/objects/aa/bb/protected',
          currentUid: 'member-1',
          identity: identity,
          envelope: material.envelopes['member-1']!,
          accountProtectionKey: SecretKey(List<int>.filled(32, 5)),
        ),
        throwsA(isA<BusinessEncryptionException>()),
      );
    });

    test(
      'validates that a recovered account key opens the Business identity',
      () async {
        final service = BusinessEncryptionService(random: Random(51));
        final recoveredProtection = SecretKey(
          List<int>.generate(32, (index) => index + 20),
        );
        final identity = await service.createIdentity(
          accountProtectionKey: recoveredProtection,
        );

        await service.validateIdentity(
          identity: identity,
          accountProtectionKey: recoveredProtection,
        );
        await expectLater(
          service.validateIdentity(
            identity: identity,
            accountProtectionKey: SecretKey(List<int>.filled(32, 1)),
          ),
          throwsA(isA<BusinessEncryptionException>()),
        );
      },
    );

    test('rewraps an existing file key only for newly added members', () async {
      final service = BusinessEncryptionService(random: Random(71));
      final aliceProtection = SecretKey(List<int>.filled(32, 8));
      final bobProtection = SecretKey(List<int>.filled(32, 9));
      final aliceIdentity = await service.createIdentity(
        accountProtectionKey: aliceProtection,
      );
      final bobIdentity = await service.createIdentity(
        accountProtectionKey: bobProtection,
      );
      const objectKey = 'company_opaque/shared/objects/aa/bb/existing';
      final original = await service.createFileEncryptionMaterial(
        objectKey: objectKey,
        recipients: <BusinessEncryptionRecipient>[
          _recipient('alice', aliceIdentity),
        ],
      );
      final openedByAlice = await service.openFileKey(
        objectKey: objectKey,
        currentUid: 'alice',
        identity: aliceIdentity,
        envelope: original.envelopes['alice']!,
        accountProtectionKey: aliceProtection,
      );

      final additions = await service.wrapExistingFileKey(
        objectKey: objectKey,
        fileKey: openedByAlice,
        recipients: <BusinessEncryptionRecipient>[
          _recipient('bob', bobIdentity),
        ],
      );
      final openedByBob = await service.openFileKey(
        objectKey: objectKey,
        currentUid: 'bob',
        identity: bobIdentity,
        envelope: additions['bob']!,
        accountProtectionKey: bobProtection,
      );

      expect(additions.keys, <String>['bob']);
      expect(original.envelopes.keys, <String>['alice']);
      expect(
        await openedByBob.extractBytes(),
        await original.fileKey.extractBytes(),
      );
    });
  });
}

BusinessEncryptionRecipient _recipient(
  String uid,
  BusinessEncryptionIdentity identity,
) {
  return BusinessEncryptionRecipient(
    uid: uid,
    keyId: identity.keyId,
    publicKeyBase64: identity.publicKeyBase64,
  );
}
