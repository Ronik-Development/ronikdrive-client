import 'package:cryptography/cryptography.dart';

import 'business_encryption_service.dart';
import 'business_recipient_trust.dart';

/// Rewraps the existing upload key; never reads or rewrites its ciphertext.
Future<Map<String, dynamic>> refreshPendingBusinessEnvelopes({
  required Map<String, dynamic> payload,
  required String uid,
  required BusinessEncryptionIdentity identity,
  required SecretKey accountProtectionKey,
  required BusinessEncryptionService encryption,
  required List<BusinessEncryptionRecipient> verifiedRecipients,
  required void Function() checkContext,
}) async {
  checkContext();
  final raw = payload['sharedKeyEnvelopes'];
  final own = raw is Map ? raw[uid] : null;
  final objectKey = payload['objectKey'];
  if (own is! Map ||
      objectKey is! String ||
      verifiedRecipients.isEmpty ||
      !verifiedRecipients.any(
        (r) => r.uid == uid && r.keyId == identity.keyId,
      )) {
    throw const RecipientTrustException(
      'Unlock the original Business identity and verify current recipients before retrying this upload.',
    );
  }
  final key = await encryption.openFileKey(
    objectKey: objectKey,
    currentUid: uid,
    identity: identity,
    envelope: BusinessFileKeyEnvelope.fromMap(Map<String, Object?>.from(own)),
    accountProtectionKey: accountProtectionKey,
  );
  checkContext();
  final envelopes = await encryption.wrapExistingFileKey(
    objectKey: objectKey,
    fileKey: key,
    recipients: verifiedRecipients,
  );
  checkContext();
  return <String, dynamic>{
    ...payload,
    'sharedKeyEnvelopes': <String, Object?>{
      for (final entry in envelopes.entries) entry.key: entry.value.toMap(),
    },
  };
}
