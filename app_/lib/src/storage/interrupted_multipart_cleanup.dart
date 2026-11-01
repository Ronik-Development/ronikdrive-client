import 'transfer_journal.dart';

typedef AbortMultipartUpload =
    Future<void> Function({
      required String objectKey,
      required String uploadId,
    });

class InterruptedMultipartCleanupResult {
  const InterruptedMultipartCleanupResult({
    required this.attempted,
    required this.completed,
  });

  final int attempted;
  final int completed;

  int get failed => attempted - completed;
}

Future<InterruptedMultipartCleanupResult> cleanupInterruptedMultipartUploads({
  required TransferJournal journal,
  required AbortMultipartUpload abortMultipartUpload,
}) async {
  final entries = journal.pendingEntries
      .where(
        (entry) =>
            entry.state == TransferJournalState.cleanupRequired &&
            entry.objectKey != null &&
            entry.multipartUploadId != null,
      )
      .toList(growable: false);
  var completed = 0;
  for (final entry in entries) {
    try {
      await abortMultipartUpload(
        objectKey: entry.objectKey!,
        uploadId: entry.multipartUploadId!,
      );
      await journal.cleanupCompleted(entry.id);
      completed += 1;
    } catch (error) {
      await journal.multipartCleanupRequired(
        transferId: entry.id,
        error: error,
      );
    }
  }
  return InterruptedMultipartCleanupResult(
    attempted: entries.length,
    completed: completed,
  );
}
