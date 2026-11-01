import 'package:cloud_storage/src/privacy/local_private_cache.dart';
import 'package:cloud_storage/src/storage/interrupted_multipart_cleanup.dart';
import 'package:cloud_storage/src/storage/transfer_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryKeyStore implements LocalPrivateCacheKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'cleanup completes safe aborts and preserves failures for retry',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final keyStore = _MemoryKeyStore();
      final activeJournal = await TransferJournal.open(
        preferences: preferences,
        uid: 'cleanup-user',
        scope: 'test-project',
        codec: LocalPrivateCacheCodec(keyStore: keyStore),
      );
      for (final id in <String>['safe', 'retry']) {
        await activeJournal.begin(
          id: id,
          kind: TransferJournalKind.upload,
          label: '$id.bin',
          objectKey: 'user/$id.bin',
        );
        await activeJournal.multipartCreated(
          transferId: id,
          objectKey: 'user/$id.bin',
          uploadId: '$id-upload',
        );
      }
      activeJournal.dispose();
      final journal = await TransferJournal.open(
        preferences: preferences,
        uid: 'cleanup-user',
        scope: 'test-project',
        codec: LocalPrivateCacheCodec(keyStore: keyStore),
      );

      final result = await cleanupInterruptedMultipartUploads(
        journal: journal,
        abortMultipartUpload: ({required objectKey, required uploadId}) async {
          if (uploadId == 'retry-upload') {
            throw StateError('provider unavailable');
          }
        },
      );

      expect(result.attempted, 2);
      expect(result.completed, 1);
      expect(result.failed, 1);
      final entries = {for (final entry in journal.entries) entry.id: entry};
      expect(entries['safe']!.state, TransferJournalState.cleanedUp);
      expect(entries['safe']!.multipartUploadId, isNull);
      expect(entries['retry']!.state, TransferJournalState.cleanupRequired);
      expect(entries['retry']!.lastError, transferJournalCleanupRetryMessage);
      expect(
        entries['retry']!.lastError,
        isNot(contains('provider unavailable')),
      );
    },
  );
}
