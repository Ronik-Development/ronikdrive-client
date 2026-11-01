import 'dart:convert';
import 'dart:math';

import 'package:cloud_storage/src/security/business_encryption_service.dart';
import 'package:cloud_storage/src/security/business_metadata_encryption.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'company labels round-trip only through the intended member envelope',
    () async {
      final business = BusinessEncryptionService(random: Random(41));
      final metadata = BusinessMetadataEncryptionService(
        businessEncryptionService: business,
        random: Random(42),
      );
      final ownerProtection = SecretKey(List<int>.filled(32, 1));
      final memberProtection = SecretKey(List<int>.filled(32, 2));
      final ownerIdentity = await business.createIdentity(
        accountProtectionKey: ownerProtection,
      );
      final memberIdentity = await business.createIdentity(
        accountProtectionKey: memberProtection,
      );
      final prepared = await metadata.prepare(
        entityType: 'company',
        plaintext: const BusinessMetadataPlaintext(
          name: 'Private Company',
          domain: 'private.example',
        ),
        recipients: <BusinessEncryptionRecipient>[
          _recipient('owner', ownerIdentity),
          _recipient('member', memberIdentity),
        ],
      );
      final publicPayload = <String, Object?>{
        ...prepared.toMap()..remove('keyEnvelopes'),
        'keyEnvelope': prepared.keyEnvelopes['owner']!.toMap(),
        'readable': true,
      };
      final parsed = BusinessEncryptedMetadata.fromMap(publicPayload);
      final opened = await metadata.open(
        metadata: parsed,
        currentUid: 'owner',
        identity: ownerIdentity,
        accountProtectionKey: ownerProtection,
      );

      expect(opened.name, 'Private Company');
      expect(opened.domain, 'private.example');
      expect(jsonEncode(prepared.toMap()), isNot(contains('Private Company')));
      expect(jsonEncode(prepared.toMap()), isNot(contains('private.example')));
      expect(prepared.metadata.ciphertextBase64, isNot(contains('=')));

      await expectLater(
        metadata.open(
          metadata: parsed,
          currentUid: 'member',
          identity: memberIdentity,
          accountProtectionKey: memberProtection,
        ),
        throwsA(isA<BusinessEncryptionException>()),
      );
    },
  );

  test('group metadata is context-bound and rotates to a fresh key', () async {
    final business = BusinessEncryptionService(random: Random(51));
    final metadata = BusinessMetadataEncryptionService(
      businessEncryptionService: business,
      random: Random(52),
    );
    final protection = SecretKey(List<int>.filled(32, 3));
    final identity = await business.createIdentity(
      accountProtectionKey: protection,
    );
    final recipient = _recipient('admin', identity);
    final first = await metadata.prepare(
      entityType: 'group',
      plaintext: const BusinessMetadataPlaintext(
        name: 'Engineering',
        description: 'Private roadmap',
      ),
      recipients: <BusinessEncryptionRecipient>[recipient],
    );
    final second = await metadata.prepare(
      entityType: 'group',
      plaintext: const BusinessMetadataPlaintext(
        name: 'Engineering',
        description: 'Private roadmap',
      ),
      recipients: <BusinessEncryptionRecipient>[recipient],
      contextId: first.metadata.contextId,
      generation: 2,
    );

    expect(second.metadata.contextId, first.metadata.contextId);
    expect(second.metadata.generation, 2);
    expect(
      second.metadata.ciphertextBase64,
      isNot(first.metadata.ciphertextBase64),
    );
    expect(
      second.keyEnvelopes['admin']!.encryptedFileKeyBase64,
      isNot(first.keyEnvelopes['admin']!.encryptedFileKeyBase64),
    );
  });

  test('metadata parser rejects plaintext fields and padded ciphertext', () {
    final base = <String, Object?>{
      'version': BusinessMetadataEncryptionService.metadataVersion,
      'format': BusinessMetadataEncryptionService.metadataFormat,
      'entityType': 'company',
      'contextId': 'bmd_AAAAAAAAAAAAAAAAAAAAAA',
      'ciphertextBase64': base64UrlEncode(List<int>.filled(32, 1)),
      'generation': 1,
      'readable': false,
    };

    expect(
      () => BusinessEncryptedMetadata.fromMap(base),
      throwsA(isA<BusinessMetadataEncryptionException>()),
    );
    final unpadded = <String, Object?>{
      ...base,
      'ciphertextBase64': base64UrlEncode(
        List<int>.filled(32, 1),
      ).replaceAll('=', ''),
      'name': 'must not pass through',
    };
    expect(
      () => BusinessEncryptedMetadata.fromMap(unpadded),
      throwsA(isA<BusinessMetadataEncryptionException>()),
    );
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
