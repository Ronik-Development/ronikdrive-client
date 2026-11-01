import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/encryption_service.dart';

const String shareMetadataEnvelopeFormat =
    'share-metadata-json-aes-ctr-hmac-sha256-v1';

class ShareMetadataEnvelopeException implements Exception {
  const ShareMetadataEnvelopeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProtectedShareMetadata {
  const ProtectedShareMetadata({
    required this.fileName,
    required this.contentType,
  });

  final String fileName;
  final String contentType;
}

/// Protects recipient-visible share metadata with the same user-held share
/// secret as the file body. The envelope contains no account, object, or token
/// identifiers and is opened only on the recipient's device.
abstract final class ShareMetadataEnvelope {
  static const int _version = 1;
  static const int maximumEncodedLength = 16 * 1024;
  static const int maximumPlaintextLength = 4 * 1024;

  static Future<String> seal({
    required String fileName,
    required String? contentType,
    required SecretKey key,
  }) async {
    final normalizedName = _normalizeFileName(fileName);
    final normalizedContentType = _normalizeContentType(contentType);
    final plaintext = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object>{
          'version': _version,
          'fileName': normalizedName,
          'contentType': normalizedContentType,
        }),
      ),
    );
    if (plaintext.length > maximumPlaintextLength) {
      throw const ShareMetadataEnvelopeException(
        'The protected share metadata is too large.',
      );
    }
    final encrypted = await EncryptionService.instance.encryptData(
      plaintext,
      key,
    );
    final encoded = base64Encode(encrypted);
    if (encoded.length > maximumEncodedLength) {
      throw const ShareMetadataEnvelopeException(
        'The protected share metadata envelope is too large.',
      );
    }
    return encoded;
  }

  static Future<ProtectedShareMetadata> open({
    required String encodedEnvelope,
    required SecretKey key,
  }) async {
    final normalizedEnvelope = encodedEnvelope.trim();
    if (normalizedEnvelope.isEmpty ||
        normalizedEnvelope.length > maximumEncodedLength) {
      throw const ShareMetadataEnvelopeException(
        'The protected share metadata envelope is invalid.',
      );
    }

    late final Uint8List encrypted;
    try {
      encrypted = base64Decode(normalizedEnvelope);
    } on FormatException {
      throw const ShareMetadataEnvelopeException(
        'The protected share metadata envelope is invalid.',
      );
    }
    final plaintext = await EncryptionService.instance.decryptData(
      encrypted,
      key,
    );
    if (plaintext.isEmpty || plaintext.length > maximumPlaintextLength) {
      throw const ShareMetadataEnvelopeException(
        'The protected share metadata payload is invalid.',
      );
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(plaintext));
    } on FormatException {
      throw const ShareMetadataEnvelopeException(
        'The protected share metadata payload is invalid.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ShareMetadataEnvelopeException(
        'The protected share metadata payload is invalid.',
      );
    }
    const allowedKeys = <String>{'version', 'fileName', 'contentType'};
    if (decoded.keys.any((key) => !allowedKeys.contains(key)) ||
        decoded.length != allowedKeys.length ||
        decoded['version'] != _version) {
      throw const ShareMetadataEnvelopeException(
        'The protected share metadata payload has an unsupported format.',
      );
    }

    return ProtectedShareMetadata(
      fileName: _normalizeFileName(decoded['fileName']),
      contentType: _normalizeContentType(decoded['contentType']),
    );
  }

  static String _normalizeFileName(Object? value) {
    if (value is! String) {
      throw const ShareMetadataEnvelopeException(
        'The protected filename is invalid.',
      );
    }
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 512 ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.contains('/') ||
        normalized.contains(r'\') ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized)) {
      throw const ShareMetadataEnvelopeException(
        'The protected filename is invalid.',
      );
    }
    return normalized;
  }

  static String _normalizeContentType(Object? value) {
    final normalized = value is String ? value.trim().toLowerCase() : '';
    if (normalized.isEmpty) {
      return 'application/octet-stream';
    }
    if (normalized.length > 200 ||
        !RegExp(
          r"^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$",
        ).hasMatch(normalized)) {
      throw const ShareMetadataEnvelopeException(
        'The protected content type is invalid.',
      );
    }
    return normalized;
  }
}
