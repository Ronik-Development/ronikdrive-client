import 'package:cloud_storage/src/security/business_encryption_service.dart';
import 'package:cloud_storage/src/security/pending_business_envelopes.dart';
import 'package:cloud_storage/src/security/business_recipient_trust.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'approval retry retains the original key and all opaque upload metadata',
    () async {
      final service = BusinessEncryptionService();
      final protection = SecretKey(List<int>.filled(32, 7));
      final identity = await service.createIdentity(
        accountProtectionKey: protection,
      );
      BusinessEncryptionRecipient recipient(int revision) =>
          BusinessEncryptionRecipient(
            uid: 'alice',
            keyId: identity.keyId,
            publicKeyBase64: identity.publicKeyBase64,
            approvalRevision: revision,
          );
      const objectKey = 'company/shared/objects/opaque';
      final material = await service.createFileEncryptionMaterial(
        objectKey: objectKey,
        recipients: [recipient(1)],
      );
      final payload = <String, dynamic>{
        'objectKey': objectKey,
        'size': 123,
        'encryptedName': 'enc--opaque',
        'contentIntegrityTag': 'cit--opaque',
        'uploadIntentId': 'opaque-intent',
        'sharedKeyEnvelopes': {'alice': material.envelopes['alice']!.toMap()},
      };
      var checks = 0;
      final refreshed = await refreshPendingBusinessEnvelopes(
        payload: payload,
        uid: 'alice',
        identity: identity,
        accountProtectionKey: protection,
        encryption: service,
        verifiedRecipients: [recipient(2)],
        checkContext: () {
          checks++;
        },
      );
      final raw = (refreshed['sharedKeyEnvelopes'] as Map)['alice'] as Map;
      expect(raw['recipientApprovalRevision'], 2);
      final reopened = await service.openFileKey(
        objectKey: objectKey,
        currentUid: 'alice',
        identity: identity,
        envelope: BusinessFileKeyEnvelope.fromMap(
          Map<String, Object?>.from(raw),
        ),
        accountProtectionKey: protection,
      );
      expect(
        await reopened.extractBytes(),
        await material.fileKey.extractBytes(),
      );
      expect(
        {...refreshed}..remove('sharedKeyEnvelopes'),
        {...payload}..remove('sharedKeyEnvelopes'),
      );
      expect(
        ((payload['sharedKeyEnvelopes'] as Map)['alice']
            as Map)['recipientApprovalRevision'],
        1,
      );
      expect(checks, 3);
      await expectLater(
        refreshPendingBusinessEnvelopes(
          payload: payload,
          uid: 'alice',
          identity: identity,
          accountProtectionKey: protection,
          encryption: service,
          verifiedRecipients: [],
          checkContext: () {},
        ),
        throwsA(isA<RecipientTrustException>()),
      );
      var count = 0;
      await expectLater(
        refreshPendingBusinessEnvelopes(
          payload: payload,
          uid: 'alice',
          identity: identity,
          accountProtectionKey: protection,
          encryption: service,
          verifiedRecipients: [recipient(2)],
          checkContext: () {
            if (++count == 2) {
              throw const RecipientTrustException('Account changed');
            }
          },
        ),
        throwsA(isA<RecipientTrustException>()),
      );
    },
  );
}
