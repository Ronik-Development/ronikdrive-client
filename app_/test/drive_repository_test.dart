import 'package:cloud_storage/src/storage/drive_repository.dart';
import 'package:cloud_storage/src/storage/file_identity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriveRepository usage tracking', () {
    test(
      'upsertFileRecord updates stored usage for new files and overwrites',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = DriveRepository(firestore: firestore);
        const userId = 'user-123';
        const objectKey = 'user-123/My Drive/report.pdf';

        await firestore.collection('users').doc(userId).set({
          'name': 'Test User',
          'email': 'test@example.com',
          'usageBytes': 0,
        });

        await repository.upsertFileRecord(
          ownerId: userId,
          objectKey: objectKey,
          size: 120,
          encryptionMode: 'standard',
          contentEncryption: 'standard',
          encryptedName: 'enc--report-name',
          uploadedAt: DateTime.utc(2026, 4, 5, 8),
        );

        expect(await _usageBytesFor(firestore, userId), 120);
        final created = await _fileForObjectKey(firestore, objectKey);
        expect(created.id, isNot(hashedFileDocumentIdForObjectKey(objectKey)));
        expect(created.id, isNot(legacyFileDocumentIdForObjectKey(objectKey)));
        expect(created.data()['fileId'], created.id);

        await repository.upsertFileRecord(
          ownerId: userId,
          objectKey: objectKey,
          size: 300,
          encryptionMode: 'standard',
          contentEncryption: 'standard',
          encryptedName: 'enc--report-name',
          uploadedAt: DateTime.utc(2026, 4, 5, 9),
        );

        expect(await _usageBytesFor(firestore, userId), 300);

        await repository.upsertFileRecord(
          ownerId: userId,
          objectKey: objectKey,
          size: 80,
          encryptionMode: 'standard',
          contentEncryption: 'standard',
          encryptedName: 'enc--report-name',
          uploadedAt: DateTime.utc(2026, 4, 5, 10),
        );

        expect(await _usageBytesFor(firestore, userId), 80);
      },
    );

    test(
      'debug logs do not expose account IDs or legacy object paths',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = DriveRepository(firestore: firestore);
        const userId = 'private-account-id';
        const objectKey =
            'private-account-id/My Drive/Tax Returns/2025-private.pdf';
        final messages = <String>[];
        final originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) {
            messages.add(message);
          }
        };

        try {
          await firestore.collection('users').doc(userId).set({
            'usageBytes': 0,
          });
          await repository.upsertFileRecord(
            ownerId: userId,
            objectKey: objectKey,
            size: 120,
            encryptionMode: 'standard',
            contentEncryption: 'standard',
            encryptedName: 'enc--private-name',
          );
          await repository.upsertFileRecord(
            ownerId: userId,
            objectKey: objectKey,
            size: 80,
            encryptionMode: 'standard',
            contentEncryption: 'standard',
            encryptedName: 'enc--private-name',
          );
        } finally {
          debugPrint = originalDebugPrint;
        }

        final output = messages.join('\n');
        expect(output, isNot(contains(userId)));
        expect(output, isNot(contains(objectKey)));
        expect(output, isNot(contains('Tax Returns')));
        expect(output, isNot(contains('2025-private.pdf')));
      },
    );

    test(
      'upsertFileRecord rejects plaintext metadata before writing',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = DriveRepository(firestore: firestore);

        await expectLater(
          repository.upsertFileRecord(
            ownerId: 'user-plaintext',
            objectKey: 'user-plaintext/My Drive/plain.txt',
            size: 5,
            encryptionMode: 'unsecured',
            contentEncryption: 'unsecured',
            encryptedName: 'plain.txt',
          ),
          throwsArgumentError,
        );

        expect((await firestore.collection('files').get()).docs, isEmpty);
      },
    );

    test(
      'upsertFileRecord updates a matching legacy document in place',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = DriveRepository(firestore: firestore);
        const userId = 'legacy-user';
        const objectKey = 'legacy-user/My Drive/report.pdf';
        final legacyId = legacyFileDocumentIdForObjectKey(objectKey);

        await firestore.collection('users').doc(userId).set({'usageBytes': 10});
        await firestore.collection('files').doc(legacyId).set({
          'uid': userId,
          'fileName': objectKey,
          'sizeBytes': 10,
          'uploadedAt': '2026-04-05T08:00:00.000Z',
        });

        await repository.upsertFileRecord(
          ownerId: userId,
          objectKey: objectKey,
          size: 10,
          encryptionMode: 'standard',
          contentEncryption: 'standard',
          encryptedName: 'enc--report-name',
          uploadedAt: DateTime.utc(2026, 4, 5, 9),
        );

        expect(
          (await firestore.collection('files').doc(legacyId).get()).exists,
          isTrue,
        );
        expect(
          (await firestore
                  .collection('files')
                  .doc(hashedFileDocumentIdForObjectKey(objectKey))
                  .get())
              .exists,
          isFalse,
        );
        final data = (await firestore.collection('files').doc(legacyId).get())
            .data();
        expect(data?['objectKeyHash'], objectKeyHash(objectKey));
        expect(data?['fileId'], legacyId);
        expect(data?['fileIdVersion'], 3);
      },
    );

    test('syncUserUsageBytes reconciles totals from file records', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = DriveRepository(firestore: firestore);
      const userId = 'user-456';

      await firestore.collection('users').doc(userId).set({
        'name': 'Another User',
        'email': 'another@example.com',
        'usageBytes': 999,
      });

      await firestore.collection('files').doc('one').set({
        'uid': userId,
        'fileName': '$userId/one.txt',
        'sizeBytes': 125,
        'uploadedAt': '2026-04-05T08:00:00.000Z',
      });
      await firestore.collection('files').doc('two').set({
        'uid': userId,
        'fileName': '$userId/two.txt',
        'sizeBytes': 375,
        'uploadedAt': '2026-04-05T09:00:00.000Z',
      });

      final total = await repository.syncUserUsageBytes(ownerId: userId);

      expect(total, 500);
      expect(await _usageBytesFor(firestore, userId), 500);
    });

    test(
      'upsertFileRecord persists path segments for nested uploads',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = DriveRepository(firestore: firestore);
        const userId = 'user-paths';
        const objectKey = 'user-paths/folders/home/objects/aa/bb/file-token';

        await firestore.collection('users').doc(userId).set({
          'name': 'Path User',
          'email': 'paths@example.com',
          'usageBytes': 0,
        });

        await repository.upsertFileRecord(
          ownerId: userId,
          objectKey: objectKey,
          size: 64,
          encryptionMode: 'standard',
          contentEncryption: 'standard',
          encryptedName: 'enc--file-name',
          folderId: 'folder-home',
          pathSegments: const ['home', 'documents'],
          uploadedAt: DateTime.utc(2026, 4, 5, 11),
        );

        final snapshot = await _fileForObjectKey(firestore, objectKey);

        expect(snapshot.data()['pathSegments'], const ['home', 'documents']);
      },
    );

    test('upsertFileRecord persists secure shard metadata', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = DriveRepository(firestore: firestore);
      const userId = 'user-secure';
      const objectKey = 'user-secure/objects/aa/bb/file-token';
      final refreshedAt = DateTime.utc(2026, 6, 14, 10);
      final dueAt = DateTime.utc(2026, 9, 12, 10);

      await firestore.collection('users').doc(userId).set({
        'name': 'Secure User',
        'email': 'secure@example.com',
        'usageBytes': 0,
      });

      await repository.upsertFileRecord(
        ownerId: userId,
        objectKey: objectKey,
        size: 4096,
        encryptionMode: 'secured',
        storageLayout: 'sharded',
        shardCount: 2,
        shardSizeBytes: 4 * 1024 * 1024,
        shardScheme: 'passphrase-hmac-sha256-v1',
        contentEncryption: 'secure',
        secureContentEncoding: 'whole-file-aes-ctr-hmac-sha256-v1',
        secureRefreshedAt: refreshedAt,
        secureRefreshDueAt: dueAt,
        encryptedName: 'enc--name',
        uploadedAt: DateTime.utc(2026, 6, 14, 10),
      );

      final snapshot = await _fileForObjectKey(firestore, objectKey);
      final data = snapshot.data();

      expect(data['shardScheme'], 'passphrase-hmac-sha256-v1');
      expect(
        data['secureContentEncoding'],
        'whole-file-aes-ctr-hmac-sha256-v1',
      );
      expect(data['secureRefreshedAt'], isNotNull);
      expect(data['secureRefreshDueAt'], isNotNull);
      expect(data, isNot(contains('hashBase64')));
      expect(data, isNot(contains('contentIntegrityTag')));
    });

    test('upsert replaces a legacy public hash with a keyed tag', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = DriveRepository(firestore: firestore);
      const userId = 'user-integrity';
      const objectKey = 'user-integrity/objects/aa/bb/opaque-token';
      final integrityTag = 'cit--${List<String>.filled(43, 'I').join()}';

      await firestore.collection('users').doc(userId).set({
        'name': 'Integrity User',
        'email': 'integrity@example.com',
        'usageBytes': 128,
      });
      await firestore.collection('files').doc('legacy-integrity-file').set({
        'uid': userId,
        'fileName': objectKey,
        'objectKeyHash': objectKeyHash(objectKey),
        'sizeBytes': 128,
        'uploadedAt': '2026-06-14T10:00:00.000Z',
        'encryptionMode': 'standard',
        'contentEncryption': 'standard',
        'encryptedName': 'enc--legacy-name',
        'storageLayout': 'single',
        'hashBase64': 'legacy-public-fingerprint',
      });

      await repository.upsertFileRecord(
        ownerId: userId,
        objectKey: objectKey,
        size: 128,
        encryptionMode: 'standard',
        contentEncryption: 'standard',
        encryptedName: 'enc--legacy-name',
        contentIntegrityTag: integrityTag,
        contentIntegrityVersion: 'hmac-sha256-v1',
        uploadedAt: DateTime.utc(2026, 6, 14, 10),
      );

      final data =
          (await firestore
                  .collection('files')
                  .doc('legacy-integrity-file')
                  .get())
              .data();
      expect(data, isNot(contains('hashBase64')));
      expect(data?['contentIntegrityTag'], integrityTag);
      expect(data?['contentIntegrityVersion'], 'hmac-sha256-v1');
    });

    test('loadBackupCatalog includes files from descendant folders', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = DriveRepository(firestore: firestore);
      const userId = 'user-backup';
      final keyedIntegrityTag = 'cit--${List<String>.filled(43, 'A').join()}';

      await firestore.collection('users').doc(userId).set({
        'name': 'Backup User',
        'email': 'backup@example.com',
        'usageBytes': 0,
      });

      await firestore.collection('folders').doc('backup-root').set({
        'uid': userId,
        'name': 'Backup',
        'color': '#E8F0FE',
        'createdAt': '2026-04-05T08:00:00.000Z',
      });
      await firestore.collection('folders').doc('backup-child').set({
        'uid': userId,
        'name': 'Documents',
        'color': '#E8F0FE',
        'createdAt': '2026-04-05T08:00:00.000Z',
        'parentId': 'backup-root',
      });

      await firestore.collection('files').doc('nested-file').set({
        'uid': userId,
        'fileName': '$userId/backups/nested-file',
        'sizeBytes': 128,
        'uploadedAt': '2026-04-05T09:00:00.000Z',
        'folderId': 'backup-child',
        'backupPathHash': 'path-hash-1',
        'backupModifiedMillis': DateTime.utc(
          2026,
          4,
          5,
          9,
        ).millisecondsSinceEpoch,
        'contentIntegrityTag': keyedIntegrityTag,
        'contentIntegrityVersion': 'hmac-sha256-v1',
      });
      await firestore.collection('files').doc('legacy-file').set({
        'uid': userId,
        'fileName': '$userId/backups/legacy-file',
        'sizeBytes': 96,
        'uploadedAt': '2026-04-05T09:30:00.000Z',
        'folderId': 'backup-child',
        'backupPathHash': 'path-hash-legacy',
        'backupModifiedMillis': DateTime.utc(
          2026,
          4,
          5,
          9,
          30,
        ).millisecondsSinceEpoch,
        'hashBase64': 'legacy-public-hash',
      });
      await firestore.collection('files').doc('other-file').set({
        'uid': userId,
        'fileName': '$userId/backups/other-file',
        'sizeBytes': 256,
        'uploadedAt': '2026-04-05T10:00:00.000Z',
        'folderId': 'somewhere-else',
        'backupPathHash': 'path-hash-2',
        'backupModifiedMillis': DateTime.utc(
          2026,
          4,
          5,
          10,
        ).millisecondsSinceEpoch,
        'hashBase64': 'def456',
      });
      await firestore.collection('files').doc('old-version').set({
        'uid': userId,
        'fileName': '$userId/backups/old-version',
        'sizeBytes': 64,
        'uploadedAt': '2026-04-05T08:30:00.000Z',
        'folderId': 'backup-child',
        'backupPathHash': 'path-hash-version',
        'backupModifiedMillis': DateTime.utc(
          2026,
          4,
          5,
          8,
          30,
        ).millisecondsSinceEpoch,
        'hashBase64': 'old-version-hash',
        'lifecycleState': 'version',
      });
      await firestore.collection('files').doc('trashed-file').set({
        'uid': userId,
        'fileName': '$userId/backups/trashed-file',
        'sizeBytes': 32,
        'uploadedAt': '2026-04-05T08:45:00.000Z',
        'folderId': 'backup-child',
        'backupPathHash': 'path-hash-trashed',
        'backupModifiedMillis': DateTime.utc(
          2026,
          4,
          5,
          8,
          45,
        ).millisecondsSinceEpoch,
        'hashBase64': 'trashed-hash',
        'lifecycleState': 'trashed',
      });

      final catalog = await repository.loadBackupCatalog(
        ownerId: userId,
        folderId: 'backup-root',
      );

      expect(catalog.keys, contains('path-hash-1'));
      expect(catalog.keys, contains('path-hash-legacy'));
      expect(catalog.keys, isNot(contains('path-hash-2')));
      expect(catalog.keys, isNot(contains('path-hash-version')));
      expect(catalog.keys, isNot(contains('path-hash-trashed')));
      expect(catalog['path-hash-1']?.size, 128);
      expect(catalog['path-hash-1']?.contentIntegrityTag, keyedIntegrityTag);
      expect(catalog['path-hash-1']?.legacyHashBase64, isEmpty);
      expect(
        catalog['path-hash-legacy']?.legacyHashBase64,
        'legacy-public-hash',
      );
    });
  });
}

Future<int?> _usageBytesFor(
  FakeFirebaseFirestore firestore,
  String userId,
) async {
  final snapshot = await firestore.collection('users').doc(userId).get();
  final data = snapshot.data();
  final value = data?['usageBytes'];
  return value is int
      ? value
      : value is num
      ? value.round()
      : null;
}

Future<QueryDocumentSnapshot<Map<String, dynamic>>> _fileForObjectKey(
  FakeFirebaseFirestore firestore,
  String objectKey,
) async {
  final snapshot = await firestore
      .collection('files')
      .where('objectKeyHash', isEqualTo: objectKeyHash(objectKey))
      .get();
  return snapshot.docs.singleWhere(
    (doc) => doc.data()['fileName'] == objectKey,
  );
}
