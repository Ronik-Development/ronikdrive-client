import '../shared/transfer_verification_pause.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import '../privacy/local_private_cache.dart';
import 'business_encryption_service.dart';
import 'encryption_service.dart';

class RecipientTrustException implements Exception, TransferVerificationPause {
  const RecipientTrustException(this.message);
  final String message;
  @override
  String toString() => 'RecipientTrustException: $message';
}

/// The signed directory is public metadata, never a source of initial trust.
/// The approval key and the high-water mark come from a verified customer device.
class BusinessRecipientApproval {
  BusinessRecipientApproval({
    required this.companyId,
    required this.revision,
    required this.publicKey,
    required List<Map<String, Object?>> members,
    required this.signature,
  }) : members = List.unmodifiable(
         members.map(
           (m) => Map<String, Object?>.unmodifiable({
             ...m,
             'scopes': List<String>.unmodifiable(
               List<String>.from(m['scopes'] as List),
             ),
           }),
         ),
       );
  final String companyId;
  final int revision;
  final String publicKey;
  final List<Map<String, Object?>> members;
  final String signature;
  static const domain = 'ronikcloud-business-recipient-approval-v1';
  factory BusinessRecipientApproval.fromMap(Map<String, Object?> value) {
    try {
      if (value.keys.any(
            (k) => !const {
              'version',
              'companyId',
              'revision',
              'publicKey',
              'members',
              'signature',
            }.contains(k),
          ) ||
          value['version'] != 1 ||
          value['revision'] is! int ||
          (value['revision'] as int) < 1 ||
          (value['revision'] as int) > 9007199254740991) {
        throw const FormatException();
      }
      final company = value['companyId'] as String;
      if (company.isEmpty || company.length > 160 || company.contains('/')) {
        {
          throw const FormatException();
        }
      }
      final members = (value['members'] as List)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
      if (members.length > 500) throw const FormatException();
      return BusinessRecipientApproval(
        companyId: company,
        revision: value['revision'] as int,
        publicKey: value['publicKey'] as String,
        members: members,
        signature: value['signature'] as String,
      );
    } catch (_) {
      throw const RecipientTrustException(
        'The company key approval is invalid.',
      );
    }
  }
  List<int> get signedBytes {
    final sorted = members.toList()
      ..sort((a, b) => (a['uid'] as String).compareTo(b['uid'] as String));
    final seen = <String>{};
    final rows = <Object?>[];
    for (final member in sorted) {
      final uid = member['uid'] as String;
      final key = member['publicKeyBase64'] as String;
      final id = member['keyId'] as String;
      final scopes = List<String>.from(member['scopes'] as List)..sort();
      if (member.keys.any(
            (k) => !const {
              'uid',
              'keyId',
              'publicKeyBase64',
              'scopes',
            }.contains(k),
          ) ||
          uid.isEmpty ||
          uid.length > 160 ||
          !seen.add(uid) ||
          scopes.isEmpty ||
          scopes.length > 204 ||
          scopes.toSet().length != scopes.length ||
          scopes.any((s) => s.isEmpty || s.length > 180) ||
          BusinessEncryptionService.keyIdForPublicKey(decode(key, 32)) != id) {
        throw const RecipientTrustException(
          'The company key approval is invalid.',
        );
      }
      rows.add([uid, id, key, scopes]);
    }
    decode(publicKey, 32);
    return utf8.encode(jsonEncode([domain, 1, companyId, revision, rows]));
  }

  String get digest => crypto.sha256.convert(signedBytes).toString();
  String get fingerprint =>
      crypto.sha256.convert(decode(publicKey, 32)).toString();
  Map<String, Object?> toMap() => {
    'version': 1,
    'companyId': companyId,
    'revision': revision,
    'publicKey': publicKey,
    'members': members,
    'signature': signature,
  };
  Future<void> verify() async {
    try {
      if (!await Ed25519().verify(
        signedBytes,
        signature: Signature(
          decode(signature, 64),
          publicKey: SimplePublicKey(
            decode(publicKey, 32),
            type: KeyPairType.ed25519,
          ),
        ),
      )) {
        throw const FormatException();
      }
    } catch (_) {
      throw const RecipientTrustException(
        'The company key approval could not be authenticated.',
      );
    }
  }

  static List<int> decode(String value, int length) {
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (bytes.length != length || encode(bytes) != value) {
      throw const FormatException();
    }
    return bytes;
  }

  static String encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
  static Future<BusinessRecipientApproval> sign({
    required String companyId,
    required int revision,
    required List<Map<String, Object?>> members,
    required SimpleKeyPair keyPair,
  }) async {
    final pub = await keyPair.extractPublicKey();
    final unsigned = BusinessRecipientApproval(
      companyId: companyId,
      revision: revision,
      publicKey: encode(pub.bytes),
      members: members,
      signature: '',
    );
    final signature = await Ed25519().sign(
      unsigned.signedBytes,
      keyPair: keyPair,
    );
    return BusinessRecipientApproval(
      companyId: companyId,
      revision: revision,
      publicKey: unsigned.publicKey,
      members: members,
      signature: encode(signature.bytes),
    );
  }
}

class BusinessRecipientTrust {
  BusinessRecipientTrust(
    this.cache, {
    required this.accountCurrent,
    this.readEnrollmentMarker,
    this.writeEnrollmentMarker,
  });
  final LocalPrivateCachePreferences cache;
  final bool Function() accountCurrent;
  final Future<String?> Function()? readEnrollmentMarker;
  final Future<void> Function(String companyHash)? writeEnrollmentMarker;
  String _companyHash(String company) =>
      crypto.sha256.convert(utf8.encode(company)).toString();
  Future<void> _chain = Future.value();
  String _base(String company) =>
      'business_trust_v1_${crypto.sha256.convert(utf8.encode(company))}';
  Future<Map<String, Object?>?> _read(String company) async {
    final value = await cache.read(
      baseKey: _base(company),
      namespace: 'business_recipient_trust_v1',
    );
    if (!accountCurrent()) {
      throw const RecipientTrustException('The account changed.');
    }
    if (value.discardedCorruptValue || value.temporarilyUnavailable) {
      throw const RecipientTrustException(
        'Verify the company on a trusted device again.',
      );
    }
    if (value.value == null) return null;
    return Map<String, Object?>.from(jsonDecode(value.value!) as Map);
  }

  Future<void> _write(String company, Map<String, Object?> state) async {
    if (!accountCurrent()) {
      throw const RecipientTrustException('The account changed.');
    }
    await cache.write(
      baseKey: _base(company),
      namespace: 'business_recipient_trust_v1',
      value: jsonEncode(state),
    );
    if (!accountCurrent()) {
      throw const RecipientTrustException('The account changed.');
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final next = _chain.then((_) => action());
    _chain = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  /// Explicit verified-device bootstrap only. Never call this for an API response.
  Future<void> pinVerified(
    BusinessRecipientApproval approval, {
    required String verifiedFingerprint,
  }) => _serialized(() async {
    await approval.verify();
    if (verifiedFingerprint != approval.fingerprint) {
      throw const RecipientTrustException(
        'The independently verified fingerprint does not match.',
      );
    }
    final old = await _read(approval.companyId);
    if (old != null &&
        (old['publicKey'] != approval.publicKey ||
            (old['revision'] as int) > approval.revision ||
            (old['revision'] == approval.revision &&
                old['digest'] != approval.digest))) {
      throw const RecipientTrustException(
        'The company approval conflicts with this trusted device.',
      );
    }
    await _write(approval.companyId, {
      'publicKey': approval.publicKey,
      'revision': approval.revision,
      'digest': approval.digest,
      if (old?['wrappedSeed'] != null) 'wrappedSeed': old!['wrappedSeed'],
    });
    await _write('active-company', {'companyId': approval.companyId});
    await writeEnrollmentMarker?.call(_companyHash(approval.companyId));
  });
  Future<List<BusinessEncryptionRecipient>> verifyRecipients({
    required String companyId,
    required String scope,
    required Object? policy,
    required List<BusinessEncryptionRecipient> recipients,
  }) => _serialized(() async {
    final marker = await readEnrollmentMarker?.call();
    if (marker != null && marker != _companyHash(companyId)) {
      throw const RecipientTrustException(
        'Verify the new company on this device before writing.',
      );
    }
    final active = await _read('active-company');
    if (active != null && active['companyId'] != companyId) {
      throw const RecipientTrustException(
        'Verify the new company on this device before writing.',
      );
    }
    final pinned = await _read(companyId);
    if (marker != null && pinned == null) {
      throw const RecipientTrustException(
        'Company trust was cleared. Verify this device again before writing.',
      );
    }
    if (policy == null) {
      if (pinned != null) {
        throw const RecipientTrustException(
          'Verified company protection cannot be downgraded.',
        );
      }
      return recipients; // Explicitly unenrolled companies retain legacy compatibility.
    }
    final approval = BusinessRecipientApproval.fromMap(
      Map<String, Object?>.from(policy as Map),
    );
    if (pinned == null) {
      throw const RecipientTrustException(
        'Verify this company with an administrator before uploading.',
      );
    }
    await approval.verify();
    if (approval.companyId != companyId ||
        approval.publicKey != pinned['publicKey'] ||
        approval.revision < (pinned['revision'] as int) ||
        (approval.revision == pinned['revision'] &&
            approval.digest != pinned['digest'])) {
      throw const RecipientTrustException(
        'The company key approval changed or rolled back.',
      );
    }
    // Latch a valid newer revocation even when the requested recipient fails.
    if (approval.revision > (pinned['revision'] as int)) {
      await _write(companyId, {
        ...pinned,
        'revision': approval.revision,
        'digest': approval.digest,
      });
    }
    final result = <BusinessEncryptionRecipient>[];
    for (final recipient in recipients) {
      final approved = approval.members.where((m) => m['uid'] == recipient.uid);
      if (approved.length != 1 ||
          approved.single['keyId'] != recipient.keyId ||
          approved.single['publicKeyBase64'] != recipient.publicKeyBase64 ||
          !(approved.single['scopes'] as List).contains(scope)) {
        throw const RecipientTrustException(
          'A recipient key needs verified administrator approval.',
        );
      }
      result.add(
        BusinessEncryptionRecipient(
          uid: recipient.uid,
          keyId: recipient.keyId,
          publicKeyBase64: recipient.publicKeyBase64,
          approvalRevision: approval.revision,
        ),
      );
    }

    return result;
  });
  Future<String> _wrapSigningSeed(SimpleKeyPair pair, SecretKey key) async {
    final seed = List<int>.from(await pair.extractPrivateKeyBytes());
    try {
      return BusinessRecipientApproval.encode(
        await EncryptionService.instance.encryptData(seed, key),
      );
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  /// Keep a customer-generated root recoverable across failed initial publication.
  /// Revision zero is pending; it never authorizes an unsigned or legacy write.
  Future<void> savePendingEnrollment(
    BusinessRecipientApproval approval,
    SimpleKeyPair pair,
    SecretKey accountKey,
  ) async {
    await approval.verify();
    if (approval.revision != 1 ||
        BusinessRecipientApproval.encode(
              (await pair.extractPublicKey()).bytes,
            ) !=
            approval.publicKey) {
      throw const RecipientTrustException(
        'The pending approval key does not match.',
      );
    }
    final wrapped = await _wrapSigningSeed(pair, accountKey);
    await _serialized(() async {
      final old = await _read(approval.companyId);
      if (old != null &&
          (old['revision'] != 0 || old['publicKey'] != approval.publicKey)) {
        throw const RecipientTrustException(
          'Existing company trust cannot be downgraded.',
        );
      }
      await _write(approval.companyId, {
        'publicKey': approval.publicKey,
        'revision': 0,
        'digest': '',
        'wrappedSeed': wrapped,
      });
      await _write('active-company', {'companyId': approval.companyId});
      await writeEnrollmentMarker?.call(_companyHash(approval.companyId));
    });
  }

  Future<void> saveSigningKey(
    BusinessRecipientApproval approval,
    SimpleKeyPair keyPair,
    SecretKey accountKey,
  ) async {
    if (BusinessRecipientApproval.encode(
          (await keyPair.extractPublicKey()).bytes,
        ) !=
        approval.publicKey) {
      throw const RecipientTrustException('The approval key does not match.');
    }
    final wrapped = await _wrapSigningSeed(keyPair, accountKey);
    await _serialized(() async {
      final state = await _read(approval.companyId);
      if (state == null || state['publicKey'] != approval.publicKey) {
        throw const RecipientTrustException(
          'Verify the company before saving its approval key.',
        );
      }
      await _write(approval.companyId, {...state, 'wrappedSeed': wrapped});
    });
  }

  Future<bool> hasSigningKey(String company) async =>
      (await _read(company))?['wrappedSeed'] != null;
  Future<SimpleKeyPair> signingKey(String company, SecretKey accountKey) async {
    final state = await _read(company);
    if (state?['wrappedSeed'] == null) {
      throw const RecipientTrustException(
        'Import the company approval recovery material on this device.',
      );
    }
    final bytes = await EncryptionService.instance.decryptData(
      base64Url.decode(base64Url.normalize(state!['wrappedSeed'] as String)),
      accountKey,
    );
    try {
      final pair = await Ed25519().newKeyPairFromSeed(bytes);
      if (BusinessRecipientApproval.encode(
            (await pair.extractPublicKey()).bytes,
          ) !=
          state['publicKey']) {
        pair.destroy();
        throw const RecipientTrustException(
          'The approval recovery material does not match.',
        );
      }
      return pair;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}
