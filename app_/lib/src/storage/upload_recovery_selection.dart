import 'transfer_journal.dart';

class UploadRecoverySelection {
  const UploadRecoverySelection({
    required this.source,
    required this.context,
    required this.secure,
    required this.browser,
  });
  final String source;
  final String context;
  final bool secure;
  final bool browser;
}

/// Selection only proposes a checkpoint; storage verifies the full source
/// fingerprint before reusing its nonce or sending any ciphertext.
Map<int, TransferJournalEntry> selectUploadRecoveryEntries(
  List<UploadRecoverySelection> selection,
  Iterable<TransferJournalEntry> entries,
) {
  final available = entries
      .where(
        (entry) =>
            entry.state == TransferJournalState.interrupted &&
            entry.objectKey != null &&
            entry.uploadCheckpoint != null,
      )
      .toList();
  final result = <int, TransferJournalEntry>{};
  for (var index = 0; index < selection.length; index++) {
    final source = selection[index];
    final match = available.indexWhere(
      (entry) =>
          entry.resumeContext == source.context &&
          (source.browser ? entry.label : entry.localPath) == source.source &&
          (entry.uploadCheckpoint?['secureSharded'] == true) == source.secure,
    );
    if (match >= 0) result[index] = available.removeAt(match);
  }
  return result;
}
