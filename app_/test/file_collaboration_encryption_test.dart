import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_storage/src/security/file_collaboration_encryption.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy collaboration text is validated before display or migration',
    () {
      final encryption = FileCollaborationEncryption();
      final comment = encryption.normalizeLegacyComment(
        authorName: ' Legacy Author ',
        body: ' Legacy body ',
        mentions: const <String>['person@example.test'],
      );
      final review = encryption.normalizeLegacyReview(
        reviewerName: ' Legacy Reviewer ',
        note: ' Legacy note ',
      );

      expect(comment.authorName, 'Legacy Author');
      expect(comment.body, 'Legacy body');
      expect(comment.mentions, const <String>['person@example.test']);
      expect(review.reviewerName, 'Legacy Reviewer');
      expect(review.note, 'Legacy note');
      expect(
        () => encryption.normalizeLegacyComment(
          authorName: 'Bad\u0000name',
          body: 'Body',
          mentions: const <String>[],
        ),
        throwsA(isA<FileCollaborationEncryptionException>()),
      );
      expect(
        () => encryption.normalizeLegacyReview(
          reviewerName: 'Reviewer',
          note: List<String>.filled(1001, 'N').join(),
        ),
        throwsA(isA<FileCollaborationEncryptionException>()),
      );
    },
  );

  final key = SecretKey(List<int>.generate(32, (index) => index));
  final otherKey = SecretKey(List<int>.generate(32, (index) => 255 - index));
  final encryption = FileCollaborationEncryption();

  test(
    'comment text, author name, and mention addresses round-trip only with the file key',
    () async {
      final encrypted = await encryption.sealComment(
        fileId: 'file-1',
        commentId: 'comment-1',
        authorUid: 'author-1',
        authorName: 'Alice Example',
        body: 'Please review @bob@example.test',
        mentions: const <String>['bob@example.test'],
        key: key,
      );

      expect(encrypted, isNot(contains('Alice')));
      expect(encrypted, isNot(contains('review')));
      expect(encrypted, isNot(contains('bob@example.test')));
      expect(encrypted, matches(RegExp(r'^[A-Za-z0-9_-]+$')));

      final opened = await encryption.openComment(
        fileId: 'file-1',
        commentId: 'comment-1',
        authorUid: 'author-1',
        encryptedPayload: encrypted,
        key: key,
      );
      expect(opened.authorName, 'Alice Example');
      expect(opened.body, 'Please review @bob@example.test');
      expect(opened.mentions, const <String>['bob@example.test']);

      await expectLater(
        encryption.openComment(
          fileId: 'file-1',
          commentId: 'comment-1',
          authorUid: 'author-1',
          encryptedPayload: encrypted,
          key: otherKey,
        ),
        throwsA(isA<FileCollaborationEncryptionException>()),
      );
    },
  );

  test(
    'authenticated context rejects moving a comment between records, files, or authors',
    () async {
      final encrypted = await encryption.sealComment(
        fileId: 'file-1',
        commentId: 'comment-1',
        authorUid: 'author-1',
        authorName: 'Alice',
        body: 'Bound message',
        mentions: const <String>[],
        key: key,
      );

      for (final binding
          in <({String fileId, String commentId, String authorUid})>[
            (fileId: 'file-2', commentId: 'comment-1', authorUid: 'author-1'),
            (fileId: 'file-1', commentId: 'comment-2', authorUid: 'author-1'),
            (fileId: 'file-1', commentId: 'comment-1', authorUid: 'author-2'),
          ]) {
        await expectLater(
          encryption.openComment(
            fileId: binding.fileId,
            commentId: binding.commentId,
            authorUid: binding.authorUid,
            encryptedPayload: encrypted,
            key: key,
          ),
          throwsA(isA<FileCollaborationEncryptionException>()),
        );
      }
    },
  );

  test('tampering and non-canonical payloads fail authentication', () async {
    final encrypted = await encryption.sealReview(
      fileId: 'file-1',
      reviewerUid: 'reviewer-1',
      reviewerName: 'Reviewer',
      note: 'Ready',
      key: key,
    );
    final replacement = encrypted.endsWith('A') ? 'B' : 'A';
    final tampered =
        '${encrypted.substring(0, encrypted.length - 1)}$replacement';

    await expectLater(
      encryption.openReview(
        fileId: 'file-1',
        reviewerUid: 'reviewer-1',
        encryptedPayload: tampered,
        key: key,
      ),
      throwsA(isA<FileCollaborationEncryptionException>()),
    );
    await expectLater(
      encryption.openReview(
        fileId: 'file-1',
        reviewerUid: 'reviewer-1',
        encryptedPayload: '$encrypted=',
        key: key,
      ),
      throwsA(isA<FileCollaborationEncryptionException>()),
    );
  });

  test(
    'reviewer details and note are encrypted while status remains a separate operational field',
    () async {
      final encrypted = await encryption.sealReview(
        fileId: 'file-1',
        reviewerUid: 'reviewer-1',
        reviewerName: 'Reviewer Name',
        note: 'Publish after the final check.',
        key: key,
      );

      expect(encrypted, isNot(contains('Reviewer Name')));
      expect(encrypted, isNot(contains('Publish')));
      final opened = await encryption.openReview(
        fileId: 'file-1',
        reviewerUid: 'reviewer-1',
        encryptedPayload: encrypted,
        key: key,
      );
      expect(opened.reviewerName, 'Reviewer Name');
      expect(opened.note, 'Publish after the final check.');
    },
  );

  test(
    'strict parser rejects authenticated payloads with unknown fields or versions',
    () async {
      final unknownField = await _sealRaw(
        <String, Object?>{
          'v': 1,
          'authorName': 'Alice',
          'body': 'Hello',
          'mentions': <String>[],
          'extra': 'not allowed',
        },
        key: key,
        kind: 'comment',
        fileId: 'file-1',
        recordId: 'comment-1',
        actorUid: 'author-1',
      );
      await expectLater(
        encryption.openComment(
          fileId: 'file-1',
          commentId: 'comment-1',
          authorUid: 'author-1',
          encryptedPayload: unknownField,
          key: key,
        ),
        throwsA(isA<FileCollaborationEncryptionException>()),
      );

      final futureVersion = await _sealRaw(
        <String, Object?>{
          'v': 2,
          'authorName': 'Alice',
          'body': 'Hello',
          'mentions': <String>[],
        },
        key: key,
        kind: 'comment',
        fileId: 'file-1',
        recordId: 'comment-1',
        actorUid: 'author-1',
      );
      await expectLater(
        encryption.openComment(
          fileId: 'file-1',
          commentId: 'comment-1',
          authorUid: 'author-1',
          encryptedPayload: futureVersion,
          key: key,
        ),
        throwsA(isA<FileCollaborationEncryptionException>()),
      );
    },
  );

  test('comment and mention limits fail before encryption', () async {
    expect(
      () => encryption.sealComment(
        fileId: 'file-1',
        commentId: 'comment-1',
        authorUid: 'author-1',
        authorName: 'Alice',
        body: 'x' * 4001,
        mentions: const <String>[],
        key: key,
      ),
      throwsA(isA<FileCollaborationEncryptionException>()),
    );
    expect(
      () => encryption.sealComment(
        fileId: 'file-1',
        commentId: 'comment-1',
        authorUid: 'author-1',
        authorName: 'Alice',
        body: 'Hello',
        mentions: const <String>['not-an-email'],
        key: key,
      ),
      throwsA(isA<FileCollaborationEncryptionException>()),
    );
  });
}

Future<String> _sealRaw(
  Map<String, Object?> payload, {
  required SecretKey key,
  required String kind,
  required String fileId,
  required String recordId,
  required String actorUid,
}) async {
  final algorithm = AesGcm.with256bits();
  final collaborationKey = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
      .deriveKey(
        secretKey: key,
        nonce: utf8.encode('ronikdrive-file-collaboration-hkdf-salt-v1'),
        info: utf8.encode('ronikdrive-file-collaboration-key-v1\n$fileId'),
      );
  final aad = utf8.encode(
    jsonEncode(<String>[
      'ronikdrive-file-collaboration-v1',
      kind,
      fileId,
      recordId,
      actorUid,
    ]),
  );
  final box = await algorithm.encrypt(
    utf8.encode(jsonEncode(payload)),
    secretKey: collaborationKey,
    aad: aad,
  );
  final bytes = BytesBuilder(copy: false)
    ..add(box.nonce)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  return base64Url.encode(bytes.takeBytes()).replaceAll('=', '');
}
