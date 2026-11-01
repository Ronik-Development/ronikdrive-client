import 'transfer_journal.dart';
import 'upload_coordinator.dart';

Future<void> cancelInterruptedUpload({
  required TransferJournal journal,
  required String entryId,
  required UploadSessionApi api,
}) async {
  final entry = journal.entries
      .where((entry) => entry.id == entryId)
      .firstOrNull;
  if (entry == null ||
      entry.state != TransferJournalState.interrupted ||
      entry.canRetryMetadata ||
      entry.uploadCheckpoint == null) {
    throw const UploadFailure('unavailable');
  }
  final checkpoint = entry.uploadCheckpoint!;
  final ids = <String>{};
  if (checkpoint['sessionId'] is String) {
    ids.add(checkpoint['sessionId'] as String);
  }
  final shards = checkpoint['shards'];
  if (shards is Map) {
    for (final child in shards.values) {
      if (child is Map && child['sessionId'] is String) {
        ids.add(child['sessionId'] as String);
      }
    }
  }
  // Server abort fences finalization and retains quota until outstanding signed
  // URLs expire. Unacknowledged starts remain covered by server expiry cleanup.
  for (final id in ids) {
    await api.call('abort', {'sessionId': id});
  }
  await journal.cancel(entryId);
}
