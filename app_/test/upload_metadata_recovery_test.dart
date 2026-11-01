import 'package:cloud_storage/src/privacy/local_private_cache.dart';
import 'package:cloud_storage/src/storage/transfer_journal.dart';
import 'package:cloud_storage/src/storage/upload_metadata_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryKeyStore implements LocalPrivateCacheKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Map<String, dynamic> _payload(String objectKey) => <String, dynamic>{
  'objectKey': objectKey,
  'size': 128,
  'encryptionMode': 'standard',
  'storageLayout': 'single',
  'contentEncryption': 'standard',
  'uploadedAt': '2026-08-02T00:00:00.000Z',
  'hasThumbnail': false,
  'encryptedName': 'enc--opaque-name',
  'storageScope': 'personal',
};

void main() {
  late SharedPreferences preferences;
  late TransferJournal journal;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 8, 2, 12);
    journal = await TransferJournal.open(
      preferences: preferences,
      uid: 'recovery-user',
      scope: 'test-project',
      codec: LocalPrivateCacheCodec(keyStore: _MemoryKeyStore()),
      clock: () => now,
    );
  });

  Future<void> stage(String id, String objectKey) async {
    await journal.begin(
      id: id,
      kind: TransferJournalKind.upload,
      label: 'Encrypted upload',
      objectKey: objectKey,
      totalBytes: 128,
    );
    await journal.stageMetadataCommit(id, payload: _payload(objectKey));
    await journal.metadataCommitFailed(id, StateError('network unavailable'));
    now = now.add(const Duration(seconds: 1));
  }

  test('account change while preparing metadata blocks submission', () async {
    await stage('changed-account', 'users/recovery-user/objects/changed');
    var current = true;
    var submitted = false;
    final result = await recoverPendingUploadMetadata(
      journal: journal,
      prepareMetadata: (payload) async {
        current = false;
        return payload;
      },
      checkContext: () {
        if (!current) {
          throw StateError('Account changed');
        }
      },
      recordMetadata: (_) async {
        submitted = true;
      },
    );
    expect(result.failed, 1);
    expect(submitted, isFalse);
    expect(journal.pendingEntries.single.canRetryMetadata, isTrue);
  });

  test(
    'prepared envelopes are durable before a failed metadata retry',
    () async {
      await stage('approval-upload', 'users/recovery-user/objects/approval');
      final result = await recoverPendingUploadMetadata(
        journal: journal,
        prepareMetadata: (payload) async => {...payload, 'approvalRevision': 2},
        recordMetadata: (payload) async {
          expect(
            journal.pendingEntries.single.metadataPayload!['approvalRevision'],
            2,
          );
          throw StateError('connection lost');
        },
      );
      expect(result.failed, 1);
      expect(journal.pendingEntries.single.canRetryMetadata, isTrue);
      expect(
        journal.pendingEntries.single.metadataPayload!['approvalRevision'],
        2,
      );
    },
  );

  test(
    'recovery replays oldest metadata first and completes each entry',
    () async {
      await stage('upload-1', 'users/recovery-user/objects/first');
      await stage('upload-2', 'users/recovery-user/objects/second');
      final recorded = <String>[];

      final result = await recoverPendingUploadMetadata(
        journal: journal,
        recordMetadata: (payload) async {
          recorded.add(payload['objectKey']! as String);
        },
      );

      expect(recorded, <String>[
        'users/recovery-user/objects/first',
        'users/recovery-user/objects/second',
      ]);
      expect(result.eligible, 2);
      expect(result.attempted, 2);
      expect(result.recovered, 2);
      expect(result.failed, 0);
      expect(journal.pendingEntries, isEmpty);
      expect(
        journal.entries.every((entry) => entry.metadataPayload == null),
        isTrue,
      );
    },
  );

  test(
    'authorization failure stops the bounded replay and stays retryable',
    () async {
      await stage('upload-1', 'users/recovery-user/objects/first');
      await stage('upload-2', 'users/recovery-user/objects/second');
      var attempts = 0;

      final result = await recoverPendingUploadMetadata(
        journal: journal,
        recordMetadata: (_) async {
          attempts += 1;
          throw StateError('unauthenticated');
        },
        stopAfterError: (error) => error.toString().contains('unauthenticated'),
      );

      expect(attempts, 1);
      expect(result.attempted, 1);
      expect(result.recovered, 0);
      expect(result.failed, 1);
      expect(journal.pendingEntries, hasLength(2));
      expect(
        journal.pendingEntries.every((entry) => entry.canRetryMetadata),
        isTrue,
      );
    },
  );
}
