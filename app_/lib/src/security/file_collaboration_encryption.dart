import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const String fileCollaborationEncryptionFormat =
    'file-collaboration-json-hkdf-sha256-aes-gcm-v1';
const int fileCollaborationMaxEncryptedPayloadChars = 49152;

class FileCollaborationEncryptionException implements Exception {
  const FileCollaborationEncryptionException(this.message);

  final String message;

  @override
  String toString() => 'FileCollaborationEncryptionException: $message';
}

class ProtectedFileComment {
  const ProtectedFileComment({
    required this.authorName,
    required this.body,
    this.mentions = const <String>[],
  });

  final String authorName;
  final String body;
  final List<String> mentions;
}

class ProtectedFileReview {
  const ProtectedFileReview({required this.reviewerName, this.note = ''});

  final String reviewerName;
  final String note;
}

/// Protects collaboration text with the same client-held key as its file.
///
/// The authenticated context binds ciphertext to its file, Firestore record,
/// record kind, and actor. Moving an otherwise valid envelope to another
/// comment, review, file, or author therefore fails authentication.
class FileCollaborationEncryption {
  FileCollaborationEncryption({AesGcm? algorithm, Hkdf? keyDerivation})
    : _algorithm = algorithm ?? AesGcm.with256bits(),
      _keyDerivation =
          keyDerivation ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static const int _schemaVersion = 1;
  static const int _maxPlaintextBytes = 32 * 1024;
  static final List<int> _keyDerivationSalt = utf8.encode(
    'ronikdrive-file-collaboration-hkdf-salt-v1',
  );
  static final RegExp _emailPattern = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  final AesGcm _algorithm;
  final Hkdf _keyDerivation;

  ProtectedFileComment normalizeLegacyComment({
    required Object? authorName,
    required Object? body,
    required Object? mentions,
  }) {
    return ProtectedFileComment(
      authorName: _personName(authorName, 'author name'),
      body: _comment(body),
      mentions: _mentions(mentions),
    );
  }

  ProtectedFileReview normalizeLegacyReview({
    required Object? reviewerName,
    required Object? note,
  }) {
    return ProtectedFileReview(
      reviewerName: _personName(reviewerName, 'reviewer name'),
      note: _reviewNote(note),
    );
  }

  Future<String> sealComment({
    required String fileId,
    required String commentId,
    required String authorUid,
    required String authorName,
    required String body,
    required List<String> mentions,
    required SecretKey key,
  }) async {
    final payload = <String, Object?>{
      'v': _schemaVersion,
      'authorName': _personName(authorName, 'author name'),
      'body': _comment(body),
      'mentions': _mentions(mentions),
    };
    return _seal(
      payload,
      context: _context(
        fileId: fileId,
        recordId: commentId,
        actorUid: authorUid,
        kind: 'comment',
      ),
      key: await _collaborationKey(key: key, fileId: fileId),
    );
  }

  Future<ProtectedFileComment> openComment({
    required String fileId,
    required String commentId,
    required String authorUid,
    required String encryptedPayload,
    required SecretKey key,
  }) async {
    final payload = await _open(
      encryptedPayload,
      context: _context(
        fileId: fileId,
        recordId: commentId,
        actorUid: authorUid,
        kind: 'comment',
      ),
      key: await _collaborationKey(key: key, fileId: fileId),
      expectedKeys: const <String>{'v', 'authorName', 'body', 'mentions'},
    );
    _requireVersion(payload);
    return ProtectedFileComment(
      authorName: _personName(payload['authorName'], 'author name'),
      body: _comment(payload['body']),
      mentions: _mentions(payload['mentions']),
    );
  }

  Future<String> sealReview({
    required String fileId,
    required String reviewerUid,
    required String reviewerName,
    String note = '',
    required SecretKey key,
  }) async {
    final payload = <String, Object?>{
      'v': _schemaVersion,
      'reviewerName': _personName(reviewerName, 'reviewer name'),
      'note': _reviewNote(note),
    };
    return _seal(
      payload,
      context: _context(
        fileId: fileId,
        recordId: fileId,
        actorUid: reviewerUid,
        kind: 'review',
      ),
      key: await _collaborationKey(key: key, fileId: fileId),
    );
  }

  Future<ProtectedFileReview> openReview({
    required String fileId,
    required String reviewerUid,
    required String encryptedPayload,
    required SecretKey key,
  }) async {
    final payload = await _open(
      encryptedPayload,
      context: _context(
        fileId: fileId,
        recordId: fileId,
        actorUid: reviewerUid,
        kind: 'review',
      ),
      key: await _collaborationKey(key: key, fileId: fileId),
      expectedKeys: const <String>{'v', 'reviewerName', 'note'},
    );
    _requireVersion(payload);
    return ProtectedFileReview(
      reviewerName: _personName(payload['reviewerName'], 'reviewer name'),
      note: _reviewNote(payload['note']),
    );
  }

  Future<String> _seal(
    Map<String, Object?> payload, {
    required List<int> context,
    required SecretKey key,
  }) async {
    final cleartext = utf8.encode(jsonEncode(payload));
    if (cleartext.isEmpty || cleartext.length > _maxPlaintextBytes) {
      throw const FileCollaborationEncryptionException(
        'The protected collaboration payload is too large.',
      );
    }
    final box = await _algorithm.encrypt(
      cleartext,
      secretKey: key,
      aad: context,
    );
    final bytes = BytesBuilder(copy: false)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    final encoded = base64Url.encode(bytes.takeBytes()).replaceAll('=', '');
    if (encoded.length > fileCollaborationMaxEncryptedPayloadChars) {
      throw const FileCollaborationEncryptionException(
        'The protected collaboration payload is too large.',
      );
    }
    return encoded;
  }

  Future<SecretKey> _collaborationKey({
    required SecretKey key,
    required String fileId,
  }) {
    final normalizedFileId = _identifier(fileId, 'file id');
    return _keyDerivation.deriveKey(
      secretKey: key,
      nonce: _keyDerivationSalt,
      info: utf8.encode(
        'ronikdrive-file-collaboration-key-v1\n$normalizedFileId',
      ),
    );
  }

  Future<Map<String, Object?>> _open(
    String encryptedPayload, {
    required List<int> context,
    required SecretKey key,
    required Set<String> expectedKeys,
  }) async {
    final normalized = encryptedPayload.trim();
    if (normalized.isEmpty ||
        normalized.length > fileCollaborationMaxEncryptedPayloadChars ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalized)) {
      throw const FileCollaborationEncryptionException(
        'The protected collaboration payload is invalid.',
      );
    }

    try {
      var padded = normalized;
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      final combined = base64Url.decode(padded);
      if (base64Url.encode(combined).replaceAll('=', '') != normalized) {
        throw const FormatException('Non-canonical base64url.');
      }
      final nonceLength = _algorithm.nonceLength;
      final macLength = _algorithm.macAlgorithm.macLength;
      if (combined.length <= nonceLength + macLength) {
        throw const FormatException('Truncated payload.');
      }
      final cleartext = await _algorithm.decrypt(
        SecretBox(
          combined.sublist(nonceLength, combined.length - macLength),
          nonce: combined.sublist(0, nonceLength),
          mac: Mac(combined.sublist(combined.length - macLength)),
        ),
        secretKey: key,
        aad: context,
      );
      if (cleartext.isEmpty || cleartext.length > _maxPlaintextBytes) {
        throw const FormatException('Invalid plaintext size.');
      }
      final decoded = jsonDecode(utf8.decode(cleartext));
      if (decoded is! Map) {
        throw const FormatException('Expected a JSON object.');
      }
      final payload = decoded.map<String, Object?>((key, value) {
        if (key is! String) {
          throw const FormatException('Invalid JSON field name.');
        }
        return MapEntry<String, Object?>(key, value);
      });
      if (payload.keys.toSet().length != expectedKeys.length ||
          !payload.keys.toSet().containsAll(expectedKeys)) {
        throw const FormatException('Unexpected JSON fields.');
      }
      return payload;
    } catch (_) {
      throw const FileCollaborationEncryptionException(
        'This collaboration entry could not be verified on this device.',
      );
    }
  }

  static List<int> _context({
    required String fileId,
    required String recordId,
    required String actorUid,
    required String kind,
  }) {
    final normalizedFileId = _identifier(fileId, 'file id');
    final normalizedRecordId = _identifier(recordId, 'record id');
    final normalizedActorUid = _identifier(actorUid, 'actor id');
    return utf8.encode(
      jsonEncode(<String>[
        'ronikdrive-file-collaboration-v1',
        kind,
        normalizedFileId,
        normalizedRecordId,
        normalizedActorUid,
      ]),
    );
  }

  static void _requireVersion(Map<String, Object?> payload) {
    if (payload['v'] != _schemaVersion) {
      throw const FileCollaborationEncryptionException(
        'This collaboration entry uses an unsupported version.',
      );
    }
  }

  static String _identifier(Object? value, String label) {
    final normalized = value is String ? value.trim() : '';
    if (normalized.isEmpty ||
        normalized.length > 512 ||
        normalized.contains('/') ||
        RegExp(r'[\u0000-\u001f\u007f]').hasMatch(normalized)) {
      throw FileCollaborationEncryptionException('The $label is invalid.');
    }
    return normalized;
  }

  static String _personName(Object? value, String label) {
    final normalized = value is String ? value.trim() : '';
    if (normalized.isEmpty ||
        normalized.length > 160 ||
        RegExp(r'[\u0000-\u001f\u007f]').hasMatch(normalized)) {
      throw FileCollaborationEncryptionException('The $label is invalid.');
    }
    return normalized;
  }

  static String _comment(Object? value) {
    final normalized = value is String ? value.trim() : '';
    if (normalized.isEmpty || normalized.length > 4000) {
      throw const FileCollaborationEncryptionException(
        'Comments must contain 1 to 4000 characters.',
      );
    }
    return normalized;
  }

  static String _reviewNote(Object? value) {
    final normalized = value is String ? value.trim() : '';
    if (normalized.length > 1000) {
      throw const FileCollaborationEncryptionException(
        'Review notes can use at most 1000 characters.',
      );
    }
    return normalized;
  }

  static List<String> _mentions(Object? value) {
    if (value is! Iterable) {
      throw const FileCollaborationEncryptionException(
        'The protected mention list is invalid.',
      );
    }
    final mentions = <String>[];
    final seen = <String>{};
    for (final item in value) {
      final normalized = item is String ? item.trim().toLowerCase() : '';
      if (normalized.isEmpty ||
          normalized.length > 320 ||
          !_emailPattern.hasMatch(normalized)) {
        throw const FileCollaborationEncryptionException(
          'The protected mention list is invalid.',
        );
      }
      if (seen.add(normalized)) {
        mentions.add(normalized);
      }
      if (mentions.length > 25) {
        throw const FileCollaborationEncryptionException(
          'A comment can mention at most 25 people.',
        );
      }
    }
    return List<String>.unmodifiable(mentions);
  }
}
