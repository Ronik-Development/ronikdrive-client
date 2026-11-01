import 'package:cloud_storage/src/storage/file_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('object-key hashes avoid collisions in the legacy encoding', () {
    const first = 'user/a/b--c';
    const second = 'user/a--b/c';
    expect(
      legacyFileDocumentIdForObjectKey(first),
      legacyFileDocumentIdForObjectKey(second),
    );
    expect(
      pendingFileIdForObjectKey(first),
      isNot(pendingFileIdForObjectKey(second)),
    );
  });

  test('pending IDs are bounded and shards retain the base identity', () {
    final longKey = 'user/${List<String>.filled(4096, 'x').join()}';
    expect(pendingFileIdForObjectKey(longKey).length, 72);

    const key = 'user/folder/file.bin';
    expect(
      pendingFileIdForObjectKey('$key.parts/000001'),
      pendingFileIdForObjectKey(key),
    );
  });

  test('authoritative records replace only their optimistic identity', () {
    const objectKey = 'users/account/objects/aa/bb/opaque-token';
    final pendingId = pendingFileIdForObjectKey(objectKey);

    expect(
      pendingFileIdReplacedByServerRecord(
        serverFileId: 'server-file-id',
        objectKey: objectKey,
        knownFileIds: <String>{pendingId, 'another-server-file'},
      ),
      pendingId,
    );
    expect(
      pendingFileIdReplacedByServerRecord(
        serverFileId: 'server-file-id',
        objectKey: objectKey,
        knownFileIds: const <String>{'another-server-file'},
      ),
      isNull,
    );
    expect(
      pendingFileIdReplacedByServerRecord(
        serverFileId: pendingId,
        objectKey: objectKey,
        knownFileIds: <String>{pendingId},
      ),
      isNull,
    );
  });

  test('late optimistic records never replace an authoritative identity', () {
    const objectKey = 'users/account/objects/aa/bb/opaque-token';
    final pendingId = pendingFileIdForObjectKey(objectKey);

    expect(
      shouldApplyOptimisticFileRecord(
        candidateFileId: pendingId,
        objectKey: objectKey,
        existingFileIdForObjectKey: 'server-file-id',
      ),
      isFalse,
    );
    expect(
      shouldApplyOptimisticFileRecord(
        candidateFileId: pendingId,
        objectKey: objectKey,
        existingFileIdForObjectKey: pendingId,
      ),
      isTrue,
    );
    expect(
      shouldApplyOptimisticFileRecord(
        candidateFileId: pendingId,
        objectKey: objectKey,
        existingFileIdForObjectKey: null,
      ),
      isTrue,
    );
    expect(
      shouldApplyOptimisticFileRecord(
        candidateFileId: 'server-file-id',
        objectKey: objectKey,
        existingFileIdForObjectKey: pendingId,
      ),
      isTrue,
    );
  });

  test('preview keys preserve scope without provider-visible semantics', () {
    final personal = thumbnailStorageObjectKey(
      'user_opaque/objects/aa/bb/file-token',
      fallbackPrefix: 'user_opaque',
    );
    final business = thumbnailStorageObjectKey(
      'company_1234567890abcdef1234567890ab/groups/group_1/'
      'objects/aa/file-token.parts/000001',
      fallbackPrefix: 'user_opaque',
    );

    expect(
      personal,
      matches(
        RegExp(
          r'^user_opaque/objects/[a-z0-9_-]{2}/[a-z0-9_-]{2}/'
          r'[A-Za-z0-9_-]{22}$',
        ),
      ),
    );
    expect(
      business,
      matches(
        RegExp(
          r'^company_1234567890abcdef1234567890ab/groups/group_1/'
          r'objects/[a-z0-9_-]{2}/[a-z0-9_-]{2}/[A-Za-z0-9_-]{22}$',
        ),
      ),
    );
    expect(personal, isNot(contains('thumbnail')));
    expect(business, isNot(contains('thumbnail')));
    expect(
      thumbnailStorageObjectKey(
        'user_opaque/objects/aa/bb/file-token',
        fallbackPrefix: 'another-prefix',
      ),
      personal,
    );
    expect(
      thumbnailStorageObjectKey(
        'user_opaque/objects/ab/cd/source-token',
        fallbackPrefix: 'user_opaque',
      ),
      'user_opaque/objects/ev/n6/EVn6k7gIef2DlWYFAmVZvQ',
    );
  });

  test('legacy source names are absent from current and old preview keys', () {
    final key = thumbnailStorageObjectKey(
      'legacy-user/My Drive/Private family photo.jpg',
      fallbackPrefix: 'user_opaque',
    );
    final legacyKey = legacyThumbnailStorageObjectKey(
      'legacy-user/My Drive/Private family photo.jpg',
      fallbackPrefix: 'user_opaque',
    );

    expect(key, startsWith('user_opaque/objects/'));
    expect(key, isNot(contains('Private family photo.jpg')));
    expect(legacyKey, startsWith('user_opaque/thumbnails/'));
    expect(legacyKey, isNot(contains('Private family photo.jpg')));
    expect(legacyKey.split('/').last, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(
      thumbnailStorageObjectKeyCandidates(
        'legacy-user/My Drive/Private family photo.jpg',
        fallbackPrefix: 'user_opaque',
      ),
      <String>[key, legacyKey],
    );
  });
}
