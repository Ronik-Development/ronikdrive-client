import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'business_encryption_service.dart';

class BusinessMetadataEncryptionException implements Exception {
  const BusinessMetadataEncryptionException(this.message);

  final String message;

  @override
  String toString() => 'BusinessMetadataEncryptionException: $message';
}

class BusinessEncryptedMetadata {
  const BusinessEncryptedMetadata({
    required this.version,
    required this.format,
    required this.entityType,
    required this.contextId,
    required this.ciphertextBase64,
    required this.generation,
    this.keyEnvelope,
    this.readable = false,
  });

  factory BusinessEncryptedMetadata.fromMap(Map<String, Object?> value) {
    const allowedKeys = <String>{
      'version',
      'format',
      'entityType',
      'contextId',
      'ciphertextBase64',
      'generation',
      'keyEnvelope',
      'readable',
    };
    if (value.keys.any((key) => !allowedKeys.contains(key))) {
      throw const BusinessMetadataEncryptionException(
        'Protected Business metadata contains an unsupported field.',
      );
    }
    final version = _positiveInt(value['version']);
    final format = _nonEmptyString(value['format']);
    final entityType = _nonEmptyString(value['entityType']);
    final contextId = _nonEmptyString(value['contextId']);
    final ciphertextBase64 = _nonEmptyString(value['ciphertextBase64']);
    final generation = _positiveInt(value['generation']);
    if (version != BusinessMetadataEncryptionService.metadataVersion ||
        format != BusinessMetadataEncryptionService.metadataFormat ||
        (entityType != 'company' && entityType != 'group') ||
        contextId == null ||
        !RegExp(r'^bmd_[A-Za-z0-9_-]{22,92}$').hasMatch(contextId) ||
        ciphertextBase64 == null ||
        !_isCanonicalBase64Url(ciphertextBase64) ||
        generation == null) {
      throw const BusinessMetadataEncryptionException(
        'Protected Business metadata is malformed.',
      );
    }
    final rawEnvelope = value['keyEnvelope'];
    final keyEnvelope = rawEnvelope == null
        ? null
        : BusinessFileKeyEnvelope.fromMap(_objectMap(rawEnvelope));
    return BusinessEncryptedMetadata(
      version: version!,
      format: format!,
      entityType: entityType!,
      contextId: contextId,
      ciphertextBase64: ciphertextBase64,
      generation: generation,
      keyEnvelope: keyEnvelope,
      readable: value['readable'] == true && keyEnvelope != null,
    );
  }

  final int version;
  final String format;
  final String entityType;
  final String contextId;
  final String ciphertextBase64;
  final int generation;
  final BusinessFileKeyEnvelope? keyEnvelope;
  final bool readable;
}

class BusinessMetadataPlaintext {
  const BusinessMetadataPlaintext({
    required this.name,
    this.domain,
    this.description,
  });

  final String name;
  final String? domain;
  final String? description;
}

class PreparedBusinessMetadata {
  const PreparedBusinessMetadata({
    required this.metadata,
    required this.keyEnvelopes,
  });

  final BusinessEncryptedMetadata metadata;
  final Map<String, BusinessFileKeyEnvelope> keyEnvelopes;

  Map<String, Object?> toMap() => <String, Object?>{
    'version': metadata.version,
    'format': metadata.format,
    'entityType': metadata.entityType,
    'contextId': metadata.contextId,
    'ciphertextBase64': metadata.ciphertextBase64,
    'generation': metadata.generation,
    'keyEnvelopes': <String, Object?>{
      for (final entry in keyEnvelopes.entries) entry.key: entry.value.toMap(),
    },
  };
}

class BusinessMetadataEncryptionService {
  BusinessMetadataEncryptionService({
    BusinessEncryptionService? businessEncryptionService,
    AesGcm? metadataAlgorithm,
    Random? random,
  }) : _businessEncryptionService =
           businessEncryptionService ?? BusinessEncryptionService(),
       _metadataAlgorithm = metadataAlgorithm ?? AesGcm.with256bits(),
       _random = random ?? Random.secure();

  static const int metadataVersion = 1;
  static const String metadataFormat = 'business-metadata-json-aes-gcm-v1';

  final BusinessEncryptionService _businessEncryptionService;
  final AesGcm _metadataAlgorithm;
  final Random _random;

  String createContextId() {
    final bytes = Uint8List.fromList(
      List<int>.generate(24, (_) => _random.nextInt(256)),
    );
    return 'bmd_${_canonicalBase64Url(bytes)}';
  }

  String encryptionContext({
    required String entityType,
    required String contextId,
  }) {
    final normalizedType = _normalizeEntityType(entityType);
    final normalizedContext = contextId.trim();
    if (!RegExp(r'^bmd_[A-Za-z0-9_-]{22,92}$').hasMatch(normalizedContext)) {
      throw const BusinessMetadataEncryptionException(
        'The protected metadata context is invalid.',
      );
    }
    return 'ronikdrive-business-metadata-v1:'
        '$normalizedType:$normalizedContext';
  }

  Future<PreparedBusinessMetadata> prepare({
    required String entityType,
    required BusinessMetadataPlaintext plaintext,
    required Iterable<BusinessEncryptionRecipient> recipients,
    String? contextId,
    int generation = 1,
  }) async {
    final normalizedType = _normalizeEntityType(entityType);
    final normalizedPlaintext = _normalizePlaintext(normalizedType, plaintext);
    if (generation < 1 || generation > 1000000000) {
      throw const BusinessMetadataEncryptionException(
        'The protected metadata generation is invalid.',
      );
    }
    final resolvedContextId = contextId?.trim().isNotEmpty == true
        ? contextId!.trim()
        : createContextId();
    final context = encryptionContext(
      entityType: normalizedType,
      contextId: resolvedContextId,
    );
    final material = await _businessEncryptionService
        .createFileEncryptionMaterial(
          objectKey: context,
          recipients: recipients,
        );
    final payload = <String, Object?>{
      'version': metadataVersion,
      'entityType': normalizedType,
      'contextId': resolvedContextId,
      'name': normalizedPlaintext.name,
      if (normalizedPlaintext.domain != null)
        'domain': normalizedPlaintext.domain,
      if (normalizedPlaintext.description != null)
        'description': normalizedPlaintext.description,
    };
    final secretBox = await _metadataAlgorithm.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: material.fileKey,
      nonce: _randomBytes(_metadataAlgorithm.nonceLength),
    );
    final ciphertext = <int>[
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ];
    return PreparedBusinessMetadata(
      metadata: BusinessEncryptedMetadata(
        version: metadataVersion,
        format: metadataFormat,
        entityType: normalizedType,
        contextId: resolvedContextId,
        ciphertextBase64: _canonicalBase64Url(ciphertext),
        generation: generation,
        readable: true,
      ),
      keyEnvelopes: material.envelopes,
    );
  }

  Future<BusinessMetadataPlaintext> open({
    required BusinessEncryptedMetadata metadata,
    required String currentUid,
    required BusinessEncryptionIdentity identity,
    required SecretKey accountProtectionKey,
  }) async {
    final fileKey = await openMetadataKey(
      metadata: metadata,
      currentUid: currentUid,
      identity: identity,
      accountProtectionKey: accountProtectionKey,
    );
    try {
      final encrypted = _decodeCanonicalBase64Url(metadata.ciphertextBase64);
      final nonceLength = _metadataAlgorithm.nonceLength;
      final macLength = _metadataAlgorithm.macAlgorithm.macLength;
      if (encrypted.length < nonceLength + macLength + 1) {
        throw const FormatException('Protected metadata is too short.');
      }
      final plaintextBytes = await _metadataAlgorithm.decrypt(
        SecretBox(
          encrypted.sublist(nonceLength, encrypted.length - macLength),
          nonce: encrypted.sublist(0, nonceLength),
          mac: Mac(encrypted.sublist(encrypted.length - macLength)),
        ),
        secretKey: fileKey,
      );
      final decoded = jsonDecode(utf8.decode(plaintextBytes));
      if (decoded is! Map) {
        throw const BusinessMetadataEncryptionException(
          'Protected Business metadata did not contain an object.',
        );
      }
      final payload = <String, Object?>{
        for (final entry in decoded.entries) entry.key.toString(): entry.value,
      };
      final allowedKeys = metadata.entityType == 'company'
          ? const <String>{
              'version',
              'entityType',
              'contextId',
              'name',
              'domain',
            }
          : const <String>{
              'version',
              'entityType',
              'contextId',
              'name',
              'description',
            };
      if (payload.keys.any((key) => !allowedKeys.contains(key)) ||
          payload['version'] != metadataVersion ||
          payload['entityType'] != metadata.entityType ||
          payload['contextId'] != metadata.contextId) {
        throw const BusinessMetadataEncryptionException(
          'Protected Business metadata has the wrong context.',
        );
      }
      return _normalizePlaintext(
        metadata.entityType,
        BusinessMetadataPlaintext(
          name: _nonEmptyString(payload['name']) ?? '',
          domain: _nonEmptyString(payload['domain']),
          description: _nonEmptyString(payload['description']),
        ),
      );
    } on BusinessMetadataEncryptionException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const BusinessMetadataEncryptionException(
        'Protected Business labels could not be authenticated.',
      );
    } on FormatException {
      throw const BusinessMetadataEncryptionException(
        'Protected Business labels are malformed.',
      );
    }
  }

  List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }

  Future<SecretKey> openMetadataKey({
    required BusinessEncryptedMetadata metadata,
    required String currentUid,
    required BusinessEncryptionIdentity identity,
    required SecretKey accountProtectionKey,
  }) {
    final envelope = metadata.keyEnvelope;
    if (!metadata.readable || envelope == null) {
      throw const BusinessMetadataEncryptionException(
        'This member does not yet have access to the protected Business labels.',
      );
    }
    return _businessEncryptionService.openFileKey(
      objectKey: encryptionContext(
        entityType: metadata.entityType,
        contextId: metadata.contextId,
      ),
      currentUid: currentUid,
      identity: identity,
      envelope: envelope,
      accountProtectionKey: accountProtectionKey,
    );
  }

  Future<Map<String, BusinessFileKeyEnvelope>> wrapForRecipients({
    required BusinessEncryptedMetadata metadata,
    required SecretKey metadataKey,
    required Iterable<BusinessEncryptionRecipient> recipients,
  }) {
    return _businessEncryptionService.wrapExistingFileKey(
      objectKey: encryptionContext(
        entityType: metadata.entityType,
        contextId: metadata.contextId,
      ),
      fileKey: metadataKey,
      recipients: recipients,
    );
  }

  String _normalizeEntityType(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized != 'company' && normalized != 'group') {
      throw const BusinessMetadataEncryptionException(
        'Protected metadata requires a company or group entity.',
      );
    }
    return normalized;
  }

  BusinessMetadataPlaintext _normalizePlaintext(
    String entityType,
    BusinessMetadataPlaintext value,
  ) {
    final name = value.name.trim();
    final maxNameLength = entityType == 'company' ? 160 : 120;
    if (name.isEmpty || name.length > maxNameLength) {
      throw BusinessMetadataEncryptionException(
        entityType == 'company'
            ? 'Enter a company name no longer than 160 characters.'
            : 'Enter a group name no longer than 120 characters.',
      );
    }
    if (entityType == 'company') {
      final domain = value.domain?.trim().toLowerCase();
      if (domain != null &&
          domain.isNotEmpty &&
          !RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$').hasMatch(domain)) {
        throw const BusinessMetadataEncryptionException(
          'Enter a valid company domain.',
        );
      }
      return BusinessMetadataPlaintext(
        name: name,
        domain: domain == null || domain.isEmpty ? null : domain,
      );
    }
    final description = value.description?.trim();
    if (description != null && description.length > 500) {
      throw const BusinessMetadataEncryptionException(
        'Group descriptions cannot exceed 500 characters.',
      );
    }
    return BusinessMetadataPlaintext(
      name: name,
      description: description == null || description.isEmpty
          ? null
          : description,
    );
  }
}

Uint8List _decodeCanonicalBase64Url(String value) {
  if (!_isCanonicalBase64Url(value)) {
    throw const FormatException('Invalid canonical base64url.');
  }
  return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
}

bool _isCanonicalBase64Url(String value) {
  if (value.isEmpty ||
      value.contains('=') ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    return false;
  }
  try {
    final bytes = base64Url.decode(base64Url.normalize(value));
    return _canonicalBase64Url(bytes) == value;
  } on FormatException {
    return false;
  }
}

String _canonicalBase64Url(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    throw const BusinessMetadataEncryptionException(
      'Protected Business metadata is malformed.',
    );
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _positiveInt(Object? value) {
  if (value is int && value > 0) {
    return value;
  }
  if (value is num && value.isFinite && value > 0 && value.round() == value) {
    return value.toInt();
  }
  return null;
}
