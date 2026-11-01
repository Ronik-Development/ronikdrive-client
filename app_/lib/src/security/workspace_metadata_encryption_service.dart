import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'encryption_service.dart';

class WorkspaceMetadataEncryptionException implements Exception {
  const WorkspaceMetadataEncryptionException(this.message);

  final String message;

  @override
  String toString() => 'WorkspaceMetadataEncryptionException: $message';
}

/// Protects user-visible workspace metadata before it leaves the device.
///
/// Folder labels use authenticated encryption. Stable identifiers that must be
/// queryable (for example backup path identities) use a keyed HMAC, preventing
/// the provider from confirming guesses with an offline dictionary.
class WorkspaceMetadataEncryptionService {
  WorkspaceMetadataEncryptionService({
    EncryptionService? encryptionService,
    Hmac? tagAlgorithm,
  }) : _encryptionService = encryptionService ?? EncryptionService.instance,
       _tagAlgorithm = tagAlgorithm ?? Hmac.sha256();

  static const String standardMetadataMode = 'standard-aes-gcm-v1';
  static const String businessMetadataMode = 'business-envelope-aes-gcm-v1';
  static const String backupPathTagPrefix = 'bpt--';
  static const String localPathTagPrefix = 'lpt--';
  static const String contentIntegrityTagPrefix = 'cit--';
  static const String contentIntegrityVersion = 'hmac-sha256-v1';
  static const String folderIdPrefix = 'fld--';
  static const String folderContextPrefix = 'ronikdrive-folder-v1:';

  final EncryptionService _encryptionService;
  final Hmac _tagAlgorithm;

  Future<String> encryptLabel({
    required String label,
    required SecretKey key,
  }) async {
    final normalizedLabel = label.trim();
    if (normalizedLabel.isEmpty) {
      throw const WorkspaceMetadataEncryptionException(
        'A non-empty metadata label is required.',
      );
    }
    return _encryptionService.encryptFileName(normalizedLabel, key);
  }

  Future<String?> decryptLabel({
    required String encryptedLabel,
    required SecretKey key,
  }) {
    final normalizedLabel = encryptedLabel.trim();
    if (normalizedLabel.isEmpty) {
      return Future<String?>.value(null);
    }
    return _encryptionService.decryptFileName(normalizedLabel, key);
  }

  Future<String> backupPathTag({
    required String normalizedRelativePath,
    required SecretKey key,
  }) {
    return _opaqueTag(
      domain: 'ronikdrive-backup-path-v1',
      value: normalizedRelativePath,
      prefix: backupPathTagPrefix,
      key: key,
    );
  }

  Future<String> localPathTag({
    required String normalizedLocalPath,
    required SecretKey key,
  }) {
    return _opaqueTag(
      domain: 'ronikdrive-local-path-v1',
      value: normalizedLocalPath,
      prefix: localPathTagPrefix,
      key: key,
    );
  }

  /// Converts a local plaintext SHA-256 digest into a provider-safe tag.
  ///
  /// The raw digest remains on the device. Keying the remote value prevents the
  /// metadata service from comparing a user's files with a public hash corpus
  /// or with another account that uses a different encryption key.
  Future<String> contentIntegrityTag({
    required String sha256Base64,
    required SecretKey key,
  }) {
    final normalizedDigest = sha256Base64.trim();
    try {
      final decoded = base64Decode(normalizedDigest);
      if (decoded.length != 32) {
        throw const FormatException('SHA-256 digests use 32 bytes.');
      }
    } on FormatException {
      throw const WorkspaceMetadataEncryptionException(
        'A valid SHA-256 digest is required for an integrity tag.',
      );
    }
    return _opaqueTag(
      domain: 'ronikdrive-content-integrity-v1',
      value: normalizedDigest,
      prefix: contentIntegrityTagPrefix,
      key: key,
    );
  }

  Future<String> deterministicFolderId({
    required String namespace,
    required String storageSpaceId,
    required String? parentId,
    required String normalizedName,
    required SecretKey key,
  }) async {
    final normalizedNamespace = namespace.trim().toLowerCase();
    final normalizedSpace = storageSpaceId.trim();
    final normalizedParent = parentId?.trim();
    final normalizedLabel = normalizedName.trim().toLowerCase();
    if (normalizedNamespace.isEmpty ||
        normalizedSpace.isEmpty ||
        normalizedLabel.isEmpty) {
      throw const WorkspaceMetadataEncryptionException(
        'Folder identity inputs must be non-empty.',
      );
    }
    final tag = await _opaqueTag(
      domain: 'ronikdrive-folder-id-v1',
      value:
          '$normalizedNamespace\n$normalizedSpace\n'
          '${normalizedParent?.isNotEmpty == true ? normalizedParent : "root"}\n'
          '$normalizedLabel',
      prefix: folderIdPrefix,
      key: key,
    );
    return tag;
  }

  String folderEncryptionContext(String folderId) {
    final normalizedFolderId = folderId.trim();
    if (normalizedFolderId.isEmpty) {
      throw const WorkspaceMetadataEncryptionException(
        'A folder identity is required.',
      );
    }
    return '$folderContextPrefix$normalizedFolderId';
  }

  Future<String> _opaqueTag({
    required String domain,
    required String value,
    required String prefix,
    required SecretKey key,
  }) async {
    final normalizedDomain = domain.trim();
    final normalizedValue = value.trim();
    if (normalizedDomain.isEmpty || normalizedValue.isEmpty) {
      throw const WorkspaceMetadataEncryptionException(
        'Opaque metadata tag inputs must be non-empty.',
      );
    }
    final mac = await _tagAlgorithm.calculateMac(
      utf8.encode('$normalizedDomain\n$normalizedValue'),
      secretKey: key,
    );
    return '$prefix${base64Url.encode(mac.bytes).replaceAll('=', '')}';
  }
}
