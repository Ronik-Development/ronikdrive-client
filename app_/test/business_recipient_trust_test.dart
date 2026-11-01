import 'dart:io';
import 'dart:convert';
import 'package:cloud_storage/src/security/business_recipient_trust.dart';
import 'package:cloud_storage/src/security/business_encryption_service.dart';
import 'package:cloud_storage/src/privacy/local_private_cache.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Keys implements LocalPrivateCacheKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BusinessRecipientTrust trust;
  late SimpleKeyPair signer;
  late BusinessEncryptionIdentity identity;
  late Map<String, Object?> member;
  late BusinessRecipientApproval approval;
  var current = true;
  Future<BusinessRecipientApproval> signed(
    int revision, {
    List<Map<String, Object?>>? members,
  }) => BusinessRecipientApproval.sign(
    companyId: 'synthetic-company',
    revision: revision,
    members: members ?? [member],
    keyPair: signer,
  );
  BusinessEncryptionRecipient recipient(BusinessEncryptionIdentity id) =>
      BusinessEncryptionRecipient(
        uid: 'synthetic-user',
        keyId: id.keyId,
        publicKeyBase64: id.publicKeyBase64,
      );
  Future<List<BusinessEncryptionRecipient>> verify(
    Object? policy, {
    String scope = 'company_shared',
    String company = 'synthetic-company',
    BusinessEncryptionIdentity? id,
  }) => trust.verifyRecipients(
    companyId: company,
    scope: scope,
    policy: policy,
    recipients: [recipient(id ?? identity)],
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    current = true;
    trust = BusinessRecipientTrust(
      LocalPrivateCachePreferences(
        preferences: await SharedPreferences.getInstance(),
        uid: 'synthetic-user',
        scope: 'synthetic-project',
        codec: LocalPrivateCacheCodec(keyStore: _Keys()),
      ),
      accountCurrent: () => current,
    );
    signer = await Ed25519().newKeyPairFromSeed(List.filled(32, 42));
    identity = await BusinessEncryptionService().createIdentity(
      accountProtectionKey: SecretKey(List.filled(32, 9)),
    );
    member = {
      'uid': 'synthetic-user',
      'keyId': identity.keyId,
      'publicKeyBase64': identity.publicKeyBase64,
      'scopes': ['company_shared', 'metadata:company'],
    };
    approval = await signed(1);
  });
  tearDown(() => signer.destroy());
  test(
    'API directory cannot bootstrap trust, independently verified fingerprint can',
    () async {
      await expectLater(
        verify(approval.toMap()),
        throwsA(isA<RecipientTrustException>()),
      );
      await expectLater(
        trust.pinVerified(approval, verifiedFingerprint: 'incorrect'),
        throwsA(isA<RecipientTrustException>()),
      );
      await trust.pinVerified(
        approval,
        verifiedFingerprint: approval.fingerprint,
      );
      expect((await verify(approval.toMap())).single.approvalRevision, 1);
    },
  );
  test(
    'substituted key and key ID are rejected before file wrapping',
    () async {
      await trust.pinVerified(
        approval,
        verifiedFingerprint: approval.fingerprint,
      );
      final attacker = await BusinessEncryptionService().createIdentity(
        accountProtectionKey: SecretKey(List.filled(32, 7)),
      );
      await expectLater(
        verify(approval.toMap(), id: attacker),
        throwsA(isA<RecipientTrustException>()),
      );
    },
  );
  test('signature, UID, company and scope substitution are rejected', () async {
    await trust.pinVerified(
      approval,
      verifiedFingerprint: approval.fingerprint,
    );
    for (final field in ['signature', 'companyId', 'revision']) {
      final bad = Map<String, Object?>.from(approval.toMap());
      bad[field] = field == 'revision'
          ? 2
          : field == 'companyId'
          ? 'other-company'
          : BusinessRecipientApproval.encode(List.filled(64, 0));
      await expectLater(verify(bad), throwsA(isA<RecipientTrustException>()));
    }
    await expectLater(
      verify(approval.toMap(), scope: 'group:unauthorized'),
      throwsA(isA<RecipientTrustException>()),
    );
    final bad =
        jsonDecode(jsonEncode(approval.toMap())) as Map<String, dynamic>;
    (bad['members'] as List).single['uid'] = 'another-user';
    await expectLater(verify(bad), throwsA(isA<RecipientTrustException>()));
  });
  test(
    'revocation advances high water mark and rejects replay, fork and downgrade',
    () async {
      await trust.pinVerified(
        approval,
        verifiedFingerprint: approval.fingerprint,
      );
      final next = await signed(2, members: []);
      await trust.verifyRecipients(
        companyId: approval.companyId,
        scope: 'company_shared',
        policy: next.toMap(),
        recipients: [],
      );
      await expectLater(
        verify(next.toMap()),
        throwsA(isA<RecipientTrustException>()),
      );
      await expectLater(
        verify(approval.toMap()),
        throwsA(isA<RecipientTrustException>()),
      );
      await expectLater(
        verify((await signed(2)).toMap()),
        throwsA(isA<RecipientTrustException>()),
      );
      await expectLater(verify(null), throwsA(isA<RecipientTrustException>()));
      await expectLater(
        verify(null, company: 'forged-new-company'),
        throwsA(isA<RecipientTrustException>()),
      );
    },
  );
  test(
    'encrypted approval key requires correct customer material and current account',
    () async {
      final accountKey = SecretKey(List.filled(32, 9));
      await trust.pinVerified(
        approval,
        verifiedFingerprint: approval.fingerprint,
      );
      await trust.saveSigningKey(approval, signer, accountKey);
      final recovered = await trust.signingKey(approval.companyId, accountKey);
      expect(
        (await recovered.extractPublicKey()).bytes,
        (await signer.extractPublicKey()).bytes,
      );
      recovered.destroy();
      await expectLater(
        trust.signingKey(approval.companyId, SecretKey(List.filled(32, 8))),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      current = false;
      await expectLater(
        verify(approval.toMap()),
        throwsA(isA<RecipientTrustException>()),
      );
    },
  );
  test(
    'Node public signature fixture matches Dart canonical encoding exactly',
    () async {
      final fixture = BusinessRecipientApproval.fromMap(
        Map<String, Object?>.from(
          jsonDecode(
                await File(
                  'test/fixtures/business_recipient_approval_v1.json',
                ).readAsString(),
              )
              as Map,
        ),
      );
      await fixture.verify();
      final pair = await Ed25519().newKeyPairFromSeed(
        List.generate(32, (i) => i),
      );
      try {
        final dart = await BusinessRecipientApproval.sign(
          companyId: fixture.companyId,
          revision: fixture.revision,
          members: fixture.members,
          keyPair: pair,
        );
        expect(dart.toMap(), fixture.toMap());
      } finally {
        pair.destroy();
      }
    },
  );
  test(
    'failed initial publication keeps the root but does not pin an unpublished revision',
    () async {
      final key = SecretKey(List.filled(32, 7));
      await trust.savePendingEnrollment(approval, signer, key);
      await expectLater(verify(null), throwsA(isA<RecipientTrustException>()));
      final changed = await signed(1, members: []);
      await trust.savePendingEnrollment(changed, signer, key);
      await trust.pinVerified(
        changed,
        verifiedFingerprint: changed.fingerprint,
      );
      await expectLater(
        trust.savePendingEnrollment(approval, signer, key),
        throwsA(isA<RecipientTrustException>()),
      );
      await expectLater(
        verify(approval.toMap()),
        throwsA(isA<RecipientTrustException>()),
      );
    },
  );
}
