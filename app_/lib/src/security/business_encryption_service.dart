import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'encryption_service.dart';

class BusinessEncryptionException implements Exception {
  const BusinessEncryptionException(this.message);

  final String message;

  @override
  String toString() => 'BusinessEncryptionException: $message';
}

class BusinessEncryptionIdentity {
  const BusinessEncryptionIdentity({
    required this.version,
    required this.keyId,
    required this.publicKeyBase64,
    required this.wrappedPrivateKeyBase64,
  });

  factory BusinessEncryptionIdentity.fromMap(Map<String, Object?> value) {
    final version = _positiveInt(value['version']);
    final keyId = _nonEmptyString(value['keyId']);
    final publicKeyBase64 = _nonEmptyString(value['publicKeyBase64']);
    final wrappedPrivateKeyBase64 = _nonEmptyString(
      value['wrappedPrivateKeyBase64'],
    );
    if (version == null ||
        keyId == null ||
        publicKeyBase64 == null ||
        wrappedPrivateKeyBase64 == null) {
      throw const BusinessEncryptionException(
        'The Business encryption identity is incomplete.',
      );
    }
    return BusinessEncryptionIdentity(
      version: version,
      keyId: keyId,
      publicKeyBase64: publicKeyBase64,
      wrappedPrivateKeyBase64: wrappedPrivateKeyBase64,
    );
  }

  final int version;
  final String keyId;
  final String publicKeyBase64;
  final String wrappedPrivateKeyBase64;

  Map<String, Object?> toMap() => <String, Object?>{
    'version': version,
    'algorithm': BusinessEncryptionService.identityAlgorithm,
    'keyId': keyId,
    'publicKeyBase64': publicKeyBase64,
    'wrappedPrivateKeyBase64': wrappedPrivateKeyBase64,
    'privateKeyWrapAlgorithm':
        BusinessEncryptionService.privateKeyWrapAlgorithm,
  };
}

class BusinessEncryptionRecipient {
  const BusinessEncryptionRecipient({
    required this.uid,
    required this.keyId,
    required this.publicKeyBase64,
    this.approvalRevision,
  });

  factory BusinessEncryptionRecipient.fromMap(Map<String, Object?> value) {
    final uid = _nonEmptyString(value['uid']);
    final keyId = _nonEmptyString(value['keyId']);
    final publicKeyBase64 = _nonEmptyString(value['publicKeyBase64']);
    if (uid == null || keyId == null || publicKeyBase64 == null) {
      throw const BusinessEncryptionException(
        'A Business encryption recipient is incomplete.',
      );
    }
    return BusinessEncryptionRecipient(
      uid: uid,
      keyId: keyId,
      publicKeyBase64: publicKeyBase64,
    );
  }

  final String uid;
  final String keyId;
  final String publicKeyBase64;
  final int? approvalRevision;
}

class BusinessFileKeyEnvelope {
  const BusinessFileKeyEnvelope({
    required this.version,
    required this.recipientUid,
    required this.recipientKeyId,
    required this.ephemeralPublicKeyBase64,
    required this.encryptedFileKeyBase64,
    this.approvalRevision,
  });

  factory BusinessFileKeyEnvelope.fromMap(Map<String, Object?> value) {
    final version = _positiveInt(value['version']);
    final recipientUid = _nonEmptyString(value['recipientUid']);
    final recipientKeyId = _nonEmptyString(value['recipientKeyId']);
    final ephemeralPublicKeyBase64 = _nonEmptyString(
      value['ephemeralPublicKeyBase64'],
    );
    final encryptedFileKeyBase64 = _nonEmptyString(
      value['encryptedFileKeyBase64'],
    );
    if (version == null ||
        recipientUid == null ||
        recipientKeyId == null ||
        ephemeralPublicKeyBase64 == null ||
        encryptedFileKeyBase64 == null) {
      throw const BusinessEncryptionException(
        'The Business file-key envelope is incomplete.',
      );
    }
    return BusinessFileKeyEnvelope(
      version: version,
      recipientUid: recipientUid,
      recipientKeyId: recipientKeyId,
      ephemeralPublicKeyBase64: ephemeralPublicKeyBase64,
      encryptedFileKeyBase64: encryptedFileKeyBase64,
    );
  }

  final int version;
  final String recipientUid;
  final String recipientKeyId;
  final String ephemeralPublicKeyBase64;
  final String encryptedFileKeyBase64;
  final int? approvalRevision;

  Map<String, Object?> toMap() => <String, Object?>{
    'version': version,
    'algorithm': BusinessEncryptionService.fileKeyEnvelopeAlgorithm,
    'recipientUid': recipientUid,
    'recipientKeyId': recipientKeyId,
    'ephemeralPublicKeyBase64': ephemeralPublicKeyBase64,
    'encryptedFileKeyBase64': encryptedFileKeyBase64,
    if (approvalRevision != null) 'recipientTrustVersion': 1,
    if (approvalRevision != null) 'recipientApprovalRevision': approvalRevision,
  };
}

class BusinessFileEncryptionMaterial {
  const BusinessFileEncryptionMaterial({
    required this.fileKey,
    required this.envelopes,
  });

  final SecretKey fileKey;
  final Map<String, BusinessFileKeyEnvelope> envelopes;
}

class BusinessEncryptionService {
  BusinessEncryptionService({
    X25519? keyExchange,
    Hkdf? keyDerivation,
    EncryptionService? encryptionService,
    Random? random,
  }) : _keyExchange = keyExchange ?? X25519(),
       _keyDerivation =
           keyDerivation ??
           Hkdf(hmac: Hmac.sha256(), outputLength: _keyLengthBytes),
       _encryptionService = encryptionService ?? EncryptionService.instance,
       _random = random ?? Random.secure();

  static const int identityVersion = 1;
  static const int envelopeVersion = 1;
  static const String identityAlgorithm = 'x25519-v1';
  static const String privateKeyWrapAlgorithm =
      'aes-ctr-hmac-sha256-with-account-key-v1';
  static const String fileKeyEnvelopeAlgorithm =
      'x25519-hkdf-sha256-aes-ctr-hmac-sha256-v1';
  static const int _keyLengthBytes = 32;
  static final List<int> _wrappingKeySalt = utf8.encode(
    'ronikdrive-business-file-key-hkdf-salt-v1',
  );

  final X25519 _keyExchange;
  final Hkdf _keyDerivation;
  final EncryptionService _encryptionService;
  final Random _random;

  Future<BusinessEncryptionIdentity> createIdentity({
    required SecretKey accountProtectionKey,
  }) async {
    final keyPair = await _keyExchange.newKeyPair();
    try {
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
      final publicKey = await keyPair.extractPublicKey();
      _requireKeyLength(privateKeyBytes, label: 'private identity key');
      _requireKeyLength(publicKey.bytes, label: 'public identity key');
      final wrappedPrivateKey = await _encryptionService.encryptData(
        privateKeyBytes,
        accountProtectionKey,
      );
      final publicKeyBase64 = _canonicalBase64Url(publicKey.bytes);
      return BusinessEncryptionIdentity(
        version: identityVersion,
        keyId: keyIdForPublicKey(publicKey.bytes),
        publicKeyBase64: publicKeyBase64,
        wrappedPrivateKeyBase64: _canonicalBase64Url(wrappedPrivateKey),
      );
    } finally {
      keyPair.destroy();
    }
  }

  Future<BusinessFileEncryptionMaterial> createFileEncryptionMaterial({
    required String objectKey,
    required Iterable<BusinessEncryptionRecipient> recipients,
  }) async {
    final normalizedObjectKey = objectKey.trim();
    if (normalizedObjectKey.isEmpty) {
      throw const BusinessEncryptionException(
        'An object identity is required before creating file envelopes.',
      );
    }
    final recipientsByUid = <String, BusinessEncryptionRecipient>{};
    for (final recipient in recipients) {
      final uid = recipient.uid.trim();
      if (uid.isEmpty) {
        continue;
      }
      final previous = recipientsByUid[uid];
      if (previous != null && previous.keyId != recipient.keyId) {
        throw BusinessEncryptionException(
          'Recipient $uid has conflicting encryption identities.',
        );
      }
      recipientsByUid[uid] = recipient;
    }
    if (recipientsByUid.isEmpty) {
      throw const BusinessEncryptionException(
        'At least one encryption-ready Business member is required.',
      );
    }

    final fileKeyBytes = _randomBytes(_keyLengthBytes);
    final fileKey = SecretKey(fileKeyBytes);
    final envelopes = <String, BusinessFileKeyEnvelope>{};
    for (final recipient in recipientsByUid.values) {
      envelopes[recipient.uid] = await _wrapFileKey(
        objectKey: normalizedObjectKey,
        fileKeyBytes: fileKeyBytes,
        recipient: recipient,
      );
    }
    return BusinessFileEncryptionMaterial(
      fileKey: fileKey,
      envelopes: Map<String, BusinessFileKeyEnvelope>.unmodifiable(envelopes),
    );
  }

  Future<Map<String, BusinessFileKeyEnvelope>> wrapExistingFileKey({
    required String objectKey,
    required SecretKey fileKey,
    required Iterable<BusinessEncryptionRecipient> recipients,
  }) async {
    final normalizedObjectKey = objectKey.trim();
    if (normalizedObjectKey.isEmpty) {
      throw const BusinessEncryptionException(
        'An object identity is required before refreshing file access.',
      );
    }
    final recipientsByUid = <String, BusinessEncryptionRecipient>{};
    for (final recipient in recipients) {
      final uid = recipient.uid.trim();
      if (uid.isEmpty) {
        continue;
      }
      final previous = recipientsByUid[uid];
      if (previous != null && previous.keyId != recipient.keyId) {
        throw BusinessEncryptionException(
          'Recipient $uid has conflicting encryption identities.',
        );
      }
      recipientsByUid[uid] = recipient;
    }
    if (recipientsByUid.isEmpty) {
      throw const BusinessEncryptionException(
        'At least one missing Business recipient is required.',
      );
    }

    final fileKeyBytes = Uint8List.fromList(await fileKey.extractBytes());
    try {
      _requireKeyLength(fileKeyBytes, label: 'Business file key');
      final envelopes = <String, BusinessFileKeyEnvelope>{};
      for (final recipient in recipientsByUid.values) {
        envelopes[recipient.uid] = await _wrapFileKey(
          objectKey: normalizedObjectKey,
          fileKeyBytes: fileKeyBytes,
          recipient: recipient,
        );
      }
      return Map<String, BusinessFileKeyEnvelope>.unmodifiable(envelopes);
    } finally {
      _wipe(fileKeyBytes);
    }
  }

  Future<void> validateIdentity({
    required BusinessEncryptionIdentity identity,
    required SecretKey accountProtectionKey,
  }) async {
    if (identity.version != identityVersion) {
      throw const BusinessEncryptionException(
        'The Business encryption identity version is unsupported.',
      );
    }
    Uint8List? privateKeyBytes;
    SimpleKeyPair? keyPair;
    try {
      privateKeyBytes = await _encryptionService.decryptData(
        _decodeBase64(identity.wrappedPrivateKeyBase64),
        accountProtectionKey,
      );
      _requireKeyLength(privateKeyBytes, label: 'private identity key');
      keyPair = await _keyExchange.newKeyPairFromSeed(privateKeyBytes);
      final restoredPublicKey = await keyPair.extractPublicKey();
      final expectedPublicKey = _decodeBase64(identity.publicKeyBase64);
      if (!_constantTimeEqual(restoredPublicKey.bytes, expectedPublicKey) ||
          keyIdForPublicKey(restoredPublicKey.bytes) != identity.keyId) {
        throw const BusinessEncryptionException(
          'The protected Business encryption identity is inconsistent.',
        );
      }
    } on BusinessEncryptionException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const BusinessEncryptionException(
        'The Business encryption identity could not be authenticated.',
      );
    } on FormatException {
      throw const BusinessEncryptionException(
        'The Business encryption identity is malformed.',
      );
    } finally {
      keyPair?.destroy();
      if (privateKeyBytes != null) {
        _wipe(privateKeyBytes);
      }
    }
  }

  Future<SecretKey> openFileKey({
    required String objectKey,
    required String currentUid,
    required BusinessEncryptionIdentity identity,
    required BusinessFileKeyEnvelope envelope,
    required SecretKey accountProtectionKey,
  }) async {
    final normalizedObjectKey = objectKey.trim();
    final normalizedUid = currentUid.trim();
    if (normalizedObjectKey.isEmpty || normalizedUid.isEmpty) {
      throw const BusinessEncryptionException(
        'The file and member identities are required to open a Business file.',
      );
    }
    if (identity.version != identityVersion ||
        envelope.version != envelopeVersion ||
        envelope.recipientUid != normalizedUid ||
        envelope.recipientKeyId != identity.keyId) {
      throw const BusinessEncryptionException(
        'This Business file-key envelope is not assigned to the current '
        'encryption identity.',
      );
    }

    Uint8List? privateKeyBytes;
    SimpleKeyPair? keyPair;
    try {
      privateKeyBytes = await _encryptionService.decryptData(
        _decodeBase64(identity.wrappedPrivateKeyBase64),
        accountProtectionKey,
      );
      _requireKeyLength(privateKeyBytes, label: 'private identity key');
      keyPair = await _keyExchange.newKeyPairFromSeed(privateKeyBytes);
      final restoredPublicKey = await keyPair.extractPublicKey();
      final expectedPublicKey = _decodeBase64(identity.publicKeyBase64);
      if (!_constantTimeEqual(restoredPublicKey.bytes, expectedPublicKey) ||
          keyIdForPublicKey(restoredPublicKey.bytes) != identity.keyId) {
        throw const BusinessEncryptionException(
          'The protected Business encryption identity is inconsistent.',
        );
      }
      final ephemeralPublicKey = _decodePublicKey(
        envelope.ephemeralPublicKeyBase64,
      );
      final sharedSecret = await _keyExchange.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: ephemeralPublicKey,
      );
      final wrappingKey = await _deriveWrappingKey(
        sharedSecret: sharedSecret,
        objectKey: normalizedObjectKey,
        recipientUid: normalizedUid,
        recipientKeyId: identity.keyId,
      );
      final fileKeyBytes = await _encryptionService.decryptData(
        _decodeBase64(envelope.encryptedFileKeyBase64),
        wrappingKey,
      );
      _requireKeyLength(fileKeyBytes, label: 'Business file key');
      return SecretKey(fileKeyBytes);
    } on BusinessEncryptionException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const BusinessEncryptionException(
        'The Business file key could not be authenticated.',
      );
    } on FormatException {
      throw const BusinessEncryptionException(
        'The Business file-key envelope is malformed.',
      );
    } finally {
      keyPair?.destroy();
      if (privateKeyBytes != null) {
        _wipe(privateKeyBytes);
      }
    }
  }

  Future<BusinessFileKeyEnvelope> _wrapFileKey({
    required String objectKey,
    required List<int> fileKeyBytes,
    required BusinessEncryptionRecipient recipient,
  }) async {
    final publicKey = _decodePublicKey(recipient.publicKeyBase64);
    final derivedKeyId = keyIdForPublicKey(publicKey.bytes);
    if (derivedKeyId != recipient.keyId) {
      throw BusinessEncryptionException(
        'Recipient ${recipient.uid} has an invalid encryption key identity.',
      );
    }
    final ephemeralKeyPair = await _keyExchange.newKeyPair();
    try {
      final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();
      final sharedSecret = await _keyExchange.sharedSecretKey(
        keyPair: ephemeralKeyPair,
        remotePublicKey: publicKey,
      );
      final wrappingKey = await _deriveWrappingKey(
        sharedSecret: sharedSecret,
        objectKey: objectKey,
        recipientUid: recipient.uid,
        recipientKeyId: recipient.keyId,
      );
      final encryptedFileKey = await _encryptionService.encryptData(
        fileKeyBytes,
        wrappingKey,
      );
      return BusinessFileKeyEnvelope(
        version: envelopeVersion,
        approvalRevision: recipient.approvalRevision,
        recipientUid: recipient.uid,
        recipientKeyId: recipient.keyId,
        ephemeralPublicKeyBase64: _canonicalBase64Url(ephemeralPublicKey.bytes),
        encryptedFileKeyBase64: _canonicalBase64Url(encryptedFileKey),
      );
    } finally {
      ephemeralKeyPair.destroy();
    }
  }

  Future<SecretKey> _deriveWrappingKey({
    required SecretKey sharedSecret,
    required String objectKey,
    required String recipientUid,
    required String recipientKeyId,
  }) {
    return _keyDerivation.deriveKey(
      secretKey: sharedSecret,
      nonce: _wrappingKeySalt,
      info: utf8.encode(
        'ronikdrive-business-file-key-v1\n'
        '$objectKey\n$recipientUid\n$recipientKeyId',
      ),
    );
  }

  SimplePublicKey _decodePublicKey(String encoded) {
    final bytes = _decodeBase64(encoded);
    _requireKeyLength(bytes, label: 'public identity key');
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  Uint8List _decodeBase64(String encoded) {
    try {
      return Uint8List.fromList(base64Url.decode(base64Url.normalize(encoded)));
    } on FormatException {
      throw const BusinessEncryptionException(
        'Business encryption data is not valid base64url.',
      );
    }
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  static String keyIdForPublicKey(List<int> publicKeyBytes) {
    _requireKeyLength(publicKeyBytes, label: 'public identity key');
    return _canonicalBase64Url(crypto.sha256.convert(publicKeyBytes).bytes);
  }

  static String _canonicalBase64Url(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static void _requireKeyLength(List<int> bytes, {required String label}) {
    if (bytes.length != _keyLengthBytes) {
      throw BusinessEncryptionException(
        'The $label must be $_keyLengthBytes bytes.',
      );
    }
  }

  static bool _constantTimeEqual(List<int> first, List<int> second) {
    if (first.length != second.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < first.length; index += 1) {
      difference |= first[index] ^ second[index];
    }
    return difference == 0;
  }

  static void _wipe(List<int> bytes) {
    for (var index = 0; index < bytes.length; index += 1) {
      bytes[index] = 0;
    }
  }
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _positiveInt(Object? value) {
  if (value is int && value > 0) {
    return value;
  }
  return null;
}
