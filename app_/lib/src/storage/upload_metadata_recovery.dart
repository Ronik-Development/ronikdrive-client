import 'transfer_journal.dart';

typedef RecordPendingUploadMetadata =
    Future<void> Function(Map<String, dynamic> payload);

class UploadMetadataRecoveryResult {
  const UploadMetadataRecoveryResult({
    required this.eligible,
    required this.attempted,
    required this.recovered,
    required this.failed,
  });

  final int eligible;
  final int attempted;
  final int recovered;
  final int failed;
}

Future<UploadMetadataRecoveryResult> recoverPendingUploadMetadata({
  required TransferJournal journal,
  required RecordPendingUploadMetadata recordMetadata,
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? prepareMetadata,
  void Function()? checkContext,
  int maxAttempts = 10,
  bool Function(Object error)? stopAfterError,
}) async {
  if (maxAttempts < 1) {
    throw ArgumentError.value(
      maxAttempts,
      'maxAttempts',
      'At least one metadata recovery attempt is required.',
    );
  }

  final candidates =
      journal.pendingEntries
          .where((entry) => entry.canRetryMetadata)
          .toList(growable: false)
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
  var attempted = 0;
  var recovered = 0;
  var failed = 0;
  for (final entry in candidates.take(maxAttempts)) {
    final payload = entry.metadataPayload;
    if (payload == null) continue;
    attempted += 1;
    try {
      checkContext?.call();
      final prepared = prepareMetadata == null
          ? Map<String, dynamic>.from(payload)
          : await prepareMetadata(Map<String, dynamic>.from(payload));
      if (prepareMetadata != null) {
        // Persist refreshed public envelopes before attempting the commit.
        await journal.stageMetadataCommit(entry.id, payload: prepared);
      }
      checkContext?.call();
      await recordMetadata(prepared);
      checkContext?.call();
      await journal.complete(entry.id);
      recovered += 1;
    } catch (error) {
      failed += 1;
      await journal.metadataCommitFailed(entry.id, error);
      if (stopAfterError?.call(error) ?? false) {
        break;
      }
    }
  }

  return UploadMetadataRecoveryResult(
    eligible: candidates.length,
    attempted: attempted,
    recovered: recovered,
    failed: failed,
  );
}
