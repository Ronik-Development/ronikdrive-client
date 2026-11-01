import 'transfer_journal.dart';
import 'upload_coordinator.dart';

/// Selects a durable source identity, including photo-library identities whose
/// temporary export path changes between background tasks.
Future<TransferJournalEntry> openBackupUploadCheckpoint({
  required TransferJournal journal,
  required String sourcePath,
  required String folderId,
  required String fingerprint,
  required int length,
  required String Function() createObjectKey,
}) async {
  if (!journal.storageAvailable) throw const UploadFailure('unavailable');
  final existing = journal.pendingEntries
      .where(
        (entry) => entry.localPath == sourcePath && entry.label == folderId,
      )
      .firstOrNull;
  if (existing != null) {
    if (existing.objectKey == null ||
        existing.canRetryMetadata ||
        existing.uploadCheckpoint?['sourceFingerprint'] != fingerprint) {
      throw const UploadFailure('source_changed');
    }
    return existing;
  }
  final id = UploadCoordinator.instance.newId();
  final objectKey = createObjectKey();
  await journal.begin(
    id: id,
    kind: TransferJournalKind.backup,
    label: folderId,
    objectKey: objectKey,
    localPath: sourcePath,
    totalBytes: length,
  );
  await journal.saveUploadCheckpoint(id, {
    'version': 1,
    'sourceFingerprint': fingerprint,
    'objectKey': objectKey,
  });
  return journal.entries.singleWhere((entry) => entry.id == id);
}
