import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/encryption_service.dart';

const String fileRequestTitleMetadataFormat =
    'file-request-title-json-aes-ctr-hmac-sha256-v1';
const String fileRequestUploadMetadataFormat =
    'file-request-upload-json-aes-ctr-hmac-sha256-v1';
const String legacyFileRequestMetadataFormat = 'file-request-legacy-generic-v0';
const String legacyFileRequestCompatibilityTitle = 'Private file request';
const int fileRequestLifecyclePrivacyVersion = 2;

class FileRequestMetadataException implements Exception {
  const FileRequestMetadataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProtectedFileRequestUploadMetadata {
  const ProtectedFileRequestUploadMetadata({
    required this.fileName,
    required this.contentType,
  });

  final String fileName;
  final String contentType;
}

/// Protects file-request labels with the random key carried only in the URL
/// fragment and in the owner's standard-key envelope. Firestore and the public
/// metadata API receive ciphertext but never the request title, submitted file
/// name, or submitted MIME type.
abstract final class FileRequestMetadataEnvelope {
  static const int _version = 1;
  static const int maximumEncodedLength = 16 * 1024;
  static const int maximumPlaintextLength = 4 * 1024;

  static Future<String> sealTitle({
    required String title,
    required SecretKey key,
  }) async {
    final normalizedTitle = _normalizeTitle(title);
    return _seal(<String, Object>{
      'version': _version,
      'title': normalizedTitle,
    }, key);
  }

  static Future<String> openTitle({
    required String encodedEnvelope,
    required SecretKey key,
  }) async {
    final decoded = await _open(encodedEnvelope, key);
    const allowedKeys = <String>{'version', 'title'};
    if (decoded.length != allowedKeys.length ||
        decoded.keys.any((key) => !allowedKeys.contains(key)) ||
        decoded['version'] != _version) {
      throw const FileRequestMetadataException(
        'The protected request title has an unsupported format.',
      );
    }
    return _normalizeTitle(decoded['title']);
  }

  static Future<String> sealUpload({
    required String fileName,
    required String? contentType,
    required SecretKey key,
  }) async {
    return _seal(<String, Object>{
      'version': _version,
      'fileName': _normalizeFileName(fileName),
      'contentType': _normalizeContentType(contentType),
    }, key);
  }

  static Future<ProtectedFileRequestUploadMetadata> openUpload({
    required String encodedEnvelope,
    required SecretKey key,
  }) async {
    final decoded = await _open(encodedEnvelope, key);
    const allowedKeys = <String>{'version', 'fileName', 'contentType'};
    if (decoded.length != allowedKeys.length ||
        decoded.keys.any((key) => !allowedKeys.contains(key)) ||
        decoded['version'] != _version) {
      throw const FileRequestMetadataException(
        'The protected upload metadata has an unsupported format.',
      );
    }
    return ProtectedFileRequestUploadMetadata(
      fileName: _normalizeFileName(decoded['fileName']),
      contentType: _normalizeContentType(decoded['contentType']),
    );
  }

  static Map<String, Object?> protectedCreatePayload({
    required String encryptedTitleBase64,
    required String encryptedKeyBase64,
    required int expiryDays,
    required int maxFileBytes,
    required int maxUploads,
  }) {
    final envelope = _normalizeEncodedEnvelope(encryptedTitleBase64);
    return <String, Object?>{
      // Older servers require a title. It is deliberately fixed and conveys
      // no user-entered information; current servers discard it.
      'title': legacyFileRequestCompatibilityTitle,
      'metadataFormat': fileRequestTitleMetadataFormat,
      'requestPrivacyVersion': fileRequestLifecyclePrivacyVersion,
      'encryptedTitleBase64': envelope,
      'encryptedKeyBase64': encryptedKeyBase64,
      'expiryDays': expiryDays.clamp(1, 30),
      'maxFileBytes': maxFileBytes.clamp(1024, 100 * 1024 * 1024),
      'maxUploads': maxUploads.clamp(1, 100),
    };
  }

  static Map<String, Object?> protectedCompletionPayload({
    required String uploadId,
    required String encryptedMetadataBase64,
  }) {
    final normalizedUploadId = uploadId.trim();
    if (normalizedUploadId.isEmpty ||
        normalizedUploadId.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalizedUploadId)) {
      throw const FileRequestMetadataException(
        'The upload authorization is invalid.',
      );
    }
    return <String, Object?>{
      'uploadId': normalizedUploadId,
      'metadataFormat': fileRequestUploadMetadataFormat,
      'requestMetadataPrivacyVersion': fileRequestLifecyclePrivacyVersion,
      'encryptedMetadataBase64': _normalizeEncodedEnvelope(
        encryptedMetadataBase64,
      ),
    };
  }

  static Future<String> _seal(
    Map<String, Object> payload,
    SecretKey key,
  ) async {
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    if (plaintext.isEmpty || plaintext.length > maximumPlaintextLength) {
      throw const FileRequestMetadataException(
        'The protected request metadata is too large.',
      );
    }
    final encrypted = await EncryptionService.instance.encryptData(
      plaintext,
      key,
    );
    return _normalizeEncodedEnvelope(base64Encode(encrypted));
  }

  static Future<Map<String, dynamic>> _open(
    String encodedEnvelope,
    SecretKey key,
  ) async {
    final normalizedEnvelope = _normalizeEncodedEnvelope(encodedEnvelope);
    late final Uint8List encrypted;
    try {
      encrypted = base64Decode(normalizedEnvelope);
    } on FormatException {
      throw const FileRequestMetadataException(
        'The protected request metadata envelope is invalid.',
      );
    }
    final plaintext = await EncryptionService.instance.decryptData(
      encrypted,
      key,
    );
    if (plaintext.isEmpty || plaintext.length > maximumPlaintextLength) {
      throw const FileRequestMetadataException(
        'The protected request metadata payload is invalid.',
      );
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(plaintext));
    } on FormatException {
      throw const FileRequestMetadataException(
        'The protected request metadata payload is invalid.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FileRequestMetadataException(
        'The protected request metadata payload is invalid.',
      );
    }
    return decoded;
  }

  static String _normalizeEncodedEnvelope(Object? value) {
    final normalized = value is String ? value.trim() : '';
    if (normalized.length < 40 ||
        normalized.length > maximumEncodedLength ||
        !RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(normalized)) {
      throw const FileRequestMetadataException(
        'The protected request metadata envelope is invalid.',
      );
    }
    return normalized;
  }

  static String _normalizeTitle(Object? value) {
    final normalized = value is String ? value.trim() : '';
    if (normalized.isEmpty ||
        normalized.length > 160 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized)) {
      throw const FileRequestMetadataException(
        'The protected request title is invalid.',
      );
    }
    return normalized;
  }

  static String _normalizeFileName(Object? value) {
    final normalized = value is String ? value.trim() : '';
    if (normalized.isEmpty ||
        normalized.length > 512 ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.contains('/') ||
        normalized.contains(r'\') ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized)) {
      throw const FileRequestMetadataException(
        'The protected upload name is invalid.',
      );
    }
    return normalized;
  }

  static String _normalizeContentType(Object? value) {
    final normalized = value is String ? value.trim().toLowerCase() : '';
    if (normalized.isEmpty) return 'application/octet-stream';
    if (normalized.length > 200 ||
        !RegExp(
          r"^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$",
        ).hasMatch(normalized)) {
      throw const FileRequestMetadataException(
        'The protected upload content type is invalid.',
      );
    }
    return normalized;
  }
}
