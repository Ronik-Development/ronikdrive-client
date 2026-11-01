import 'package:cloud_storage/src/storage/transfer_journal.dart';
import 'package:cloud_storage/src/storage/upload_recovery_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TransferJournalEntry saved({
    String context = 'folder',
    bool secure = false,
  }) => TransferJournalEntry(
    id: 'original',
    kind: TransferJournalKind.upload,
    state: TransferJournalState.interrupted,
    label: 'file.bin',
    localPath: '/source/file.bin',
    resumeContext: context,
    objectKey: 'opaque',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    uploadCheckpoint: {
      'sourceFingerprint': 'digest',
      'nonce': 'original',
      if (secure) 'secureSharded': true,
    },
  );
  const web = UploadRecoverySelection(
    source: 'file.bin',
    context: 'folder',
    secure: false,
    browser: true,
  );
  test('browser reselection retains the original verified checkpoint', () {
    final matches = selectUploadRecoveryEntries([web], [saved()]);
    expect(matches[0]!.uploadCheckpoint!['sourceFingerprint'], 'digest');
    expect(matches[0]!.uploadCheckpoint!['nonce'], 'original');
    expect(
      selectUploadRecoveryEntries([web], [saved(context: 'different')]),
      isEmpty,
    );
    expect(selectUploadRecoveryEntries([web], [saved(secure: true)]), isEmpty);
  });
  test('duplicate selections never receive the same interrupted session', () {
    final matches = selectUploadRecoveryEntries([web, web], [saved()]);
    expect(matches.keys, [0]);
  });
  test('native reselection requires the original path', () {
    expect(
      selectUploadRecoveryEntries(
        [
          const UploadRecoverySelection(
            source: '/other/file.bin',
            context: 'folder',
            secure: false,
            browser: false,
          ),
        ],
        [saved()],
      ),
      isEmpty,
    );
    expect(
      selectUploadRecoveryEntries(
        [
          const UploadRecoverySelection(
            source: '/source/file.bin',
            context: 'folder',
            secure: false,
            browser: false,
          ),
        ],
        [saved()],
      )[0]!.id,
      'original',
    );
  });
}
