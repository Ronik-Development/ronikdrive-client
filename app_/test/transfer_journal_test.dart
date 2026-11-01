import 'dart:convert';

import 'package:cloud_storage/src/privacy/local_private_cache.dart';
import 'package:cloud_storage/src/storage/transfer_journal.dart';
import 'package:cloud_storage/src/storage/secure_upload_checkpoint.dart';
import 'package:cloud_storage/src/storage/upload_coordinator.dart';
import 'package:cloud_storage/src/storage/backup_upload_checkpoint.dart';
import 'package:cloud_storage/src/storage/upload_resume_context.dart';
import 'package:cloud_storage/src/storage/cancel_interrupted_upload.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryKeyStore implements LocalPrivateCacheKeyStore {
  final Map<String, String> values = <String, String>{};
  bool failReads = false;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    if (failReads) {
      throw StateError('credential store unavailable');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _AbortApi extends UploadSessionApi {
  _AbortApi(this.fail)
    : super(
        client: http.Client(),
        baseUri: Uri.parse('https://fixture.invalid/'),
        tokenProvider: () async => null,
      );
  final bool fail;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, dynamic> body,
  ) async {
    expect(operation, 'abort');
    calls.add(body['sessionId'] as String);
    if (fail) throw StateError('offline');
    return {'ok': true, 'cleanupPending': true};
  }
}

String _tamperCiphertext(String value) {
  final index = LocalPrivateCacheCodec.encryptedPrefix.length + 8;
  final replacement = value[index] == 'A' ? 'B' : 'A';
  return value.replaceRange(index, index + 1, replacement);
}

void main() {
  const cacheScope = 'test-project';
  late _MemoryKeyStore keyStore;

  Future<TransferJournal> openJournal({
    required SharedPreferences preferences,
    required String uid,
    DateTime Function()? clock,
  }) {
    return TransferJournal.open(
      preferences: preferences,
      uid: uid,
      scope: cacheScope,
      codec: LocalPrivateCacheCodec(keyStore: keyStore),
      clock: clock,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    keyStore = _MemoryKeyStore();
  });

  for (final offline in [false, true]) {
    test(
      'cancel interrupted shards retains retry state when offline=$offline',
      () async {
        final journal = await openJournal(
          preferences: await SharedPreferences.getInstance(),
          uid: 'owner',
        );
        final api = _AbortApi(offline);
        addTearDown(() {
          api.client.close();
          journal.dispose();
        });
        await journal.begin(
          id: 'saved',
          kind: TransferJournalKind.upload,
          label: 'file',
        );
        await journal.saveUploadCheckpoint('saved', {
          'version': 1,
          'secureSharded': true,
          'shards': {
            'one': {'sessionId': 'one'},
            'two': {'sessionId': 'two'},
          },
        });
        await journal.fail('saved', StateError('interrupted'));
        final cancel = cancelInterruptedUpload(
          journal: journal,
          entryId: 'saved',
          api: api,
        );
        if (offline) {
          await expectLater(cancel, throwsStateError);
          expect(
            journal.entries.single.state,
            TransferJournalState.interrupted,
          );
        } else {
          await cancel;
          expect(api.calls, ['one', 'two']);
          expect(journal.entries.single.state, TransferJournalState.canceled);
          await expectLater(
            cancelInterruptedUpload(
              journal: journal,
              entryId: 'saved',
              api: api,
            ),
            throwsA(isA<UploadFailure>()),
          );
        }
      },
    );
  }

  test(
    'restart preserves destination scope without matching a different folder',
    () async {
      final preferences = await SharedPreferences.getInstance();
      String scope(String folder, {bool secure = false}) => uploadResumeContext(
        uid: 'owner',
        storageScope: 'personal',
        groupId: null,
        folderId: folder,
        relativeFolders: ['child'],
        secure: secure,
      );
      var journal = await openJournal(preferences: preferences, uid: 'owner');
      await journal.begin(
        id: 'upload',
        kind: TransferJournalKind.upload,
        label: 'source',
        localPath: 'private/source',
        resumeContext: scope('original'),
      );
      await journal.saveUploadCheckpoint('upload', {
        'version': 1,
        'sessionId': 'session',
      });
      await journal.updateProgress('upload', transferredBytes: 42);
      journal.dispose();
      journal = await openJournal(preferences: preferences, uid: 'owner');
      final entry = journal.pendingEntries.single;
      expect(entry.state, TransferJournalState.interrupted);
      expect(entry.resumeContext, scope('original'));
      expect(entry.resumeContext, isNot(scope('other')));
      expect(entry.resumeContext, isNot(scope('original', secure: true)));
      journal.dispose();
    },
  );

  test(
    'background restart reuses identity and rejects changed photo exports',
    () async {
      final preferences = await SharedPreferences.getInstance();
      var journal = await openJournal(
        preferences: preferences,
        uid: 'backup-user',
      );
      final original = await openBackupUploadCheckpoint(
        journal: journal,
        sourcePath: 'photo-library:stable-asset',
        folderId: 'folder',
        fingerprint: 'source-digest',
        length: 123,
        createObjectKey: () => 'opaque-object',
      );
      await journal.saveUploadCheckpoint(original.id, {
        ...original.uploadCheckpoint!,
        'nonce': 'saved-nonce',
        'sessionId': 'saved-session',
      });
      journal.dispose();
      journal = await openJournal(preferences: preferences, uid: 'backup-user');
      final restored = await openBackupUploadCheckpoint(
        journal: journal,
        sourcePath: 'photo-library:stable-asset',
        folderId: 'folder',
        fingerprint: 'source-digest',
        length: 123,
        createObjectKey: () => throw StateError('No duplicate allocation'),
      );
      expect(restored.id, original.id);
      expect(restored.objectKey, 'opaque-object');
      expect(restored.uploadCheckpoint?['nonce'], 'saved-nonce');
      await expectLater(
        openBackupUploadCheckpoint(
          journal: journal,
          sourcePath: 'photo-library:stable-asset',
          folderId: 'folder',
          fingerprint: 'changed-export',
          length: 123,
          createObjectKey: () => throw StateError('No duplicate allocation'),
        ),
        throwsA(
          isA<UploadFailure>().having((e) => e.code, 'code', 'source_changed'),
        ),
      );
      expect(journal.entries.length, 1);
    },
  );

  test(
    'secure parent nonce and parallel shard checkpoints survive encrypted restart',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final journal = await openJournal(
        preferences: preferences,
        uid: 'secure-user',
      );
      await journal.begin(
        id: 'parent',
        kind: TransferJournalKind.upload,
        label: 'private',
        objectKey: 'opaque',
        totalBytes: 20,
      );
      final parent = await SecureUploadCheckpoint.open(
        sink: journal,
        parentId: 'parent',
        objectKey: 'opaque',
        fingerprint: 'unchanged',
        newNonce: () => [1, 2, 3],
      );
      await Future.wait(
        List.generate(
          8,
          (i) => parent.saveUploadCheckpoint('shard:$i', {
            'sessionId': 'session-$i',
            'parts': {'1': 'digest-$i'},
            'eTags': {'1': 'etag-$i'},
          }),
        ),
      );
      final reopened = await openJournal(
        preferences: preferences,
        uid: 'secure-user',
      );
      final restored = await SecureUploadCheckpoint.open(
        sink: reopened,
        parentId: 'parent',
        objectKey: 'opaque',
        fingerprint: 'unchanged',
        newNonce: () => throw StateError('Must retain the nonce'),
      );
      expect(restored.nonce, [1, 2, 3]);
      for (var i = 0; i < 8; i++) {
        expect(
          restored.uploadCheckpoint('shard:$i')?['sessionId'],
          'session-$i',
        );
        expect(
          restored.uploadCheckpoint('shard:$i')?['sourceFingerprint'],
          'unchanged',
        );
      }
      await expectLater(
        SecureUploadCheckpoint.open(
          sink: reopened,
          parentId: 'parent',
          objectKey: 'opaque',
          fingerprint: 'changed',
          newNonce: () => [4],
        ),
        throwsA(
          isA<UploadFailure>().having((e) => e.code, 'code', 'source_changed'),
        ),
      );
      expect(restored.nonce, [1, 2, 3]);
    },
  );

  test(
    'version two checkpoints survive encrypted restart without storing keys',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final journal = await openJournal(
        preferences: preferences,
        uid: 'resumable-user',
      );
      await journal.begin(
        id: 'resume',
        kind: TransferJournalKind.upload,
        label: 'private name',
        objectKey: 'opaque-object',
        totalBytes: 100,
      );
      await journal.saveUploadCheckpoint('resume', {
        'version': 1,
        'nonce': 'saved-nonce',
        'sourceFingerprint': 'fingerprint',
        'sessionId': 'session-identifier',
        'parts': {'1': 'digest'},
        'eTags': {'1': 'provider-etag'},
        'partBytes': 8388608,
      });
      await expectLater(
        journal.saveUploadCheckpoint('resume', {'encryptionKey': 'secret'}),
        throwsFormatException,
      );
      final reopened = await openJournal(
        preferences: preferences,
        uid: 'resumable-user',
      );
      expect(reopened.entries.single.state, TransferJournalState.interrupted);
      expect(reopened.uploadCheckpoint('resume')?['nonce'], 'saved-nonce');
      expect(reopened.uploadCheckpoint('resume')?['eTags'], {
        '1': 'provider-etag',
      });
      for (final key in preferences.getKeys()) {
        expect(preferences.get(key).toString(), isNot(contains('saved-nonce')));
        expect(
          preferences.get(key).toString(),
          isNot(contains('private name')),
        );
      }
    },
  );

  test(
    'an interrupted multipart upload survives restart and requires cleanup',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final journal = await openJournal(
        preferences: preferences,
        uid: 'user-1',
      );
      await journal.begin(
        id: 'upload-1',
        kind: TransferJournalKind.upload,
        label: 'archive.zip',
        objectKey: 'user_1/archive.zip',
        localPath: r'C:\files\archive.zip',
        totalBytes: 20,
      );
      await journal.multipartCreated(
        transferId: 'upload-1',
        objectKey: 'user_1/archive.zip',
        uploadId: 'multipart-123',
      );
      await journal.multipartPartCompleted(
        transferId: 'upload-1',
        partNumber: 1,
        eTag: 'etag-1',
        uploadedBytes: 8,
      );
      final storedCiphertext = preferences.getString(
        LocalPrivateCachePreferences.scopedPreferenceKey(
          LocalPrivateCacheCodec.transferJournalPreferenceKey,
          'user-1',
          scope: cacheScope,
        ),
      );
      expect(
        storedCiphertext,
        startsWith(LocalPrivateCacheCodec.encryptedPrefix),
      );
      expect(storedCiphertext, isNot(contains('archive.zip')));
      expect(storedCiphertext, isNot(contains(r'C:\files')));
      expect(storedCiphertext, isNot(contains('multipart-123')));
      journal.dispose();

      final restored = await openJournal(
        preferences: preferences,
        uid: 'user-1',
      );
      final entry = restored.entries.single;
      expect(entry.state, TransferJournalState.cleanupRequired);
      expect(entry.multipartUploadId, 'multipart-123');
      expect(entry.completedParts, <int, String>{1: 'etag-1'});
      expect(entry.transferredBytes, 8);

      await restored.cleanupCompleted('upload-1');
      expect(restored.entries.single.state, TransferJournalState.cleanedUp);
      expect(restored.entries.single.multipartUploadId, isNull);
      expect(restored.entries.single.lastError, isNull);
      expect(restored.pendingEntries, isEmpty);
    },
  );

  test('completed uploads and trust timestamps persist', () async {
    final preferences = await SharedPreferences.getInstance();
    final journal = await openJournal(preferences: preferences, uid: 'user-2');
    await journal.begin(
      id: 'upload-2',
      kind: TransferJournalKind.upload,
      label: 'photo.jpg',
      totalBytes: 12,
    );
    await journal.complete('upload-2');
    await journal.markBackupScan(successful: true);
    await journal.markRestoreVerified();

    final restored = await openJournal(preferences: preferences, uid: 'user-2');
    expect(restored.entries.single.state, TransferJournalState.completed);
    expect(restored.entries.single.transferredBytes, 12);
    expect(restored.lastSuccessfulUploadAt, isNotNull);
    expect(restored.lastBackupScanAt, isNotNull);
    expect(restored.lastBackupScanSuccessful, isTrue);
    expect(restored.lastVerifiedRestoreAt, isNotNull);
  });

  test(
    'an object uploaded before metadata failure remains actionable',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final journal = await openJournal(
        preferences: preferences,
        uid: 'user-3',
      );
      await journal.begin(
        id: 'upload-3',
        kind: TransferJournalKind.upload,
        label: 'document.pdf',
        objectKey: 'users/user-3/objects/document',
        totalBytes: 128,
      );
      await journal.stageMetadataCommit(
        'upload-3',
        payload: <String, dynamic>{
          'objectKey': 'users/user-3/objects/document',
          'size': 128,
          'encryptionMode': 'standard',
          'storageLayout': 'single',
          'contentEncryption': 'standard',
          'uploadedAt': '2026-07-24T00:00:00.000Z',
          'hasThumbnail': false,
          'encryptedName': 'enc--opaque-name',
          'storageScope': 'personal',
        },
      );
      await journal.metadataCommitFailed(
        'upload-3',
        StateError('firestore unavailable'),
      );
      final protectedJournal = preferences.getString(
        LocalPrivateCachePreferences.scopedPreferenceKey(
          LocalPrivateCacheCodec.transferJournalPreferenceKey,
          'user-3',
          scope: cacheScope,
        ),
      );
      expect(protectedJournal, isNot(contains('enc--opaque-name')));
      expect(protectedJournal, isNot(contains('objects/document')));

      final restored = await openJournal(
        preferences: preferences,
        uid: 'user-3',
      );
      expect(
        restored.pendingEntries.single.state,
        TransferJournalState.awaitingMetadata,
      );
      expect(
        restored.pendingEntries.single.lastError,
        transferJournalMetadataRetryMessage,
      );
      expect(
        restored.pendingEntries.single.lastError,
        isNot(contains('firestore unavailable')),
      );
      expect(restored.pendingEntries.single.canRetryMetadata, isTrue);
      expect(
        restored.pendingEntries.single.metadataPayload?['encryptedName'],
        'enc--opaque-name',
      );

      await restored.complete('upload-3');
      expect(restored.entries.single.metadataPayload, isNull);
      expect(restored.pendingEntries, isEmpty);
    },
  );

  test('legacy raw journal errors are replaced and re-encrypted', () async {
    final preferences = await SharedPreferences.getInstance();
    final privateCache = LocalPrivateCachePreferences(
      preferences: preferences,
      uid: 'legacy-error-user',
      scope: cacheScope,
      codec: LocalPrivateCacheCodec(keyStore: keyStore),
    );
    final timestamp = DateTime.utc(2026, 8, 2, 12);
    final entry = TransferJournalEntry(
      id: 'legacy-upload',
      kind: TransferJournalKind.upload,
      state: TransferJournalState.awaitingMetadata,
      label: 'Encrypted upload',
      createdAt: timestamp,
      updatedAt: timestamp,
      objectKey: 'users/legacy-error-user/objects/opaque',
      metadataPayload: <String, dynamic>{
        'objectKey': 'users/legacy-error-user/objects/opaque',
      },
      lastError: 'FirebaseException host=private.example file=secret-plan.pdf',
    );
    await privateCache.write(
      baseKey: LocalPrivateCacheCodec.transferJournalPreferenceKey,
      namespace: LocalPrivateCacheCodec.transferJournalNamespace,
      value: jsonEncode(<String, Object?>{
        'version': 1,
        'entries': <Object?>[entry.toJson()],
      }),
    );

    final journal = await openJournal(
      preferences: preferences,
      uid: 'legacy-error-user',
    );
    expect(
      journal.entries.single.lastError,
      transferJournalMetadataRetryMessage,
    );
    final rewritten = await privateCache.read(
      baseKey: LocalPrivateCacheCodec.transferJournalPreferenceKey,
      namespace: LocalPrivateCacheCodec.transferJournalNamespace,
    );
    expect(rewritten.value, isNot(contains('private.example')));
    expect(rewritten.value, isNot(contains('secret-plan.pdf')));
    expect(rewritten.value, contains(transferJournalMetadataRetryMessage));
  });

  test('replayed multipart checkpoints do not double-count progress', () async {
    final preferences = await SharedPreferences.getInstance();
    final journal = await openJournal(preferences: preferences, uid: 'user-4');
    await journal.begin(
      id: 'upload-4',
      kind: TransferJournalKind.upload,
      label: 'large.bin',
      totalBytes: 20,
    );
    await journal.multipartPartCompleted(
      transferId: 'upload-4',
      partNumber: 1,
      eTag: 'etag-1',
      uploadedBytes: 8,
    );
    await journal.multipartPartCompleted(
      transferId: 'upload-4',
      partNumber: 1,
      eTag: 'etag-1-replayed',
      uploadedBytes: 8,
    );

    expect(journal.entries.single.transferredBytes, 8);
    expect(journal.entries.single.completedParts, <int, String>{
      1: 'etag-1-replayed',
    });
  });

  test('successful backup uploads contribute to upload health', () async {
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime.utc(2026, 7, 21, 12);
    final journal = await openJournal(
      preferences: preferences,
      uid: 'user-5',
      clock: () => now,
    );
    await journal.begin(
      id: 'backup-1',
      kind: TransferJournalKind.backup,
      label: 'backup.txt',
    );
    await journal.complete('backup-1');

    expect(journal.lastSuccessfulUploadAt, now);
  });

  test('upload health survives terminal-entry pruning', () async {
    final preferences = await SharedPreferences.getInstance();
    final journal = await openJournal(preferences: preferences, uid: 'user-6');
    await journal.begin(
      id: 'upload-6',
      kind: TransferJournalKind.upload,
      label: 'keep-health.txt',
    );
    await journal.complete('upload-6');
    final completedAt = journal.lastSuccessfulUploadAt;
    final codec = LocalPrivateCacheCodec(keyStore: keyStore);
    final storageKey = LocalPrivateCachePreferences.scopedPreferenceKey(
      LocalPrivateCacheCodec.transferJournalPreferenceKey,
      'user-6',
      scope: cacheScope,
    );
    final opened = await codec.open(
      uid: '$cacheScope\nuser-6',
      namespace: LocalPrivateCacheCodec.transferJournalNamespace,
      value: preferences.getString(storageKey)!,
    );
    final stored = jsonDecode(opened.plaintext) as Map<String, dynamic>;
    stored['entries'] = <Object>[];
    final protected = await codec.seal(
      uid: '$cacheScope\nuser-6',
      namespace: LocalPrivateCacheCodec.transferJournalNamespace,
      plaintext: jsonEncode(stored),
    );
    await preferences.setString(storageKey, protected);

    final restored = await openJournal(preferences: preferences, uid: 'user-6');
    expect(restored.entries, isEmpty);
    expect(restored.lastSuccessfulUploadAt, completedAt);
  });

  test(
    'legacy plaintext journal migrates without exposing its contents',
    () async {
      const uid = 'legacy-user';
      const legacyKey = 'transfer_journal_v1_legacy-user';
      SharedPreferences.setMockInitialValues(<String, Object>{
        legacyKey: jsonEncode(<String, Object?>{
          'version': 1,
          'entries': <Object?>[
            <String, Object?>{
              'id': 'legacy-upload',
              'kind': 'upload',
              'state': 'inProgress',
              'label': 'private-contract.pdf',
              'createdAt': '2026-07-24T00:00:00Z',
              'updatedAt': '2026-07-24T00:00:00Z',
              'localPath': r'C:\Sensitive\private-contract.pdf',
            },
          ],
        }),
      });
      final preferences = await SharedPreferences.getInstance();

      final journal = await openJournal(preferences: preferences, uid: uid);

      expect(journal.migratedLegacyState, isTrue);
      expect(journal.entries.single.state, TransferJournalState.interrupted);
      expect(preferences.containsKey(legacyKey), isFalse);
      final protected = preferences.getString(
        LocalPrivateCachePreferences.scopedPreferenceKey(
          LocalPrivateCacheCodec.transferJournalPreferenceKey,
          uid,
          scope: cacheScope,
        ),
      );
      expect(protected, startsWith(LocalPrivateCacheCodec.encryptedPrefix));
      expect(protected, isNot(contains('private-contract')));
      expect(protected, isNot(contains('Sensitive')));
    },
  );

  test('tampered journal is discarded and reported as recovered', () async {
    const uid = 'tampered-user';
    final preferences = await SharedPreferences.getInstance();
    final journal = await openJournal(preferences: preferences, uid: uid);
    await journal.begin(
      id: 'upload-tampered',
      kind: TransferJournalKind.upload,
      label: 'secret.txt',
    );
    final storageKey = LocalPrivateCachePreferences.scopedPreferenceKey(
      LocalPrivateCacheCodec.transferJournalPreferenceKey,
      uid,
      scope: cacheScope,
    );
    final protected = preferences.getString(storageKey)!;
    await preferences.setString(storageKey, _tamperCiphertext(protected));

    final restored = await openJournal(preferences: preferences, uid: uid);

    expect(restored.entries, isEmpty);
    expect(restored.recoveredCorruptState, isTrue);
    expect(preferences.containsKey(storageKey), isFalse);
  });

  test('keychain failure keeps ciphertext and pauses journal writes', () async {
    const uid = 'locked-user';
    final preferences = await SharedPreferences.getInstance();
    final journal = await openJournal(preferences: preferences, uid: uid);
    await journal.begin(
      id: 'upload-locked',
      kind: TransferJournalKind.upload,
      label: 'locked.txt',
    );
    final storageKey = LocalPrivateCachePreferences.scopedPreferenceKey(
      LocalPrivateCacheCodec.transferJournalPreferenceKey,
      uid,
      scope: cacheScope,
    );
    final protected = preferences.getString(storageKey);
    keyStore.failReads = true;

    final locked = await openJournal(preferences: preferences, uid: uid);

    expect(locked.storageAvailable, isFalse);
    expect(preferences.getString(storageKey), protected);
    await expectLater(
      locked.begin(
        id: 'blocked-write',
        kind: TransferJournalKind.upload,
        label: 'blocked.txt',
      ),
      throwsA(
        isA<LocalPrivateCacheException>().having(
          (error) => error.failure,
          'failure',
          LocalPrivateCacheFailure.keyUnavailable,
        ),
      ),
    );
  });
}
