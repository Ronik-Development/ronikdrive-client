import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../privacy/privacy_support_code.dart';
import '../privacy/temporary_plaintext_files_control.dart';
import '../share/share_link_security.dart';
import '../share/share_link_owner_service.dart';
import '../shared/app_error_reporter.dart';
import '../shared/app_page_title.dart';
import '../storage/secure_drive_service.dart';
import '../storage/transfer_journal.dart';
import '../storage/upload_metadata_recovery.dart';
import 'recovery_failure.dart';

class FileRequestDraft {
  const FileRequestDraft({
    required this.title,
    required this.expiryDays,
    required this.maxFileBytes,
    required this.maxUploads,
  });

  final String title;
  final int expiryDays;
  final int maxFileBytes;
  final int maxUploads;
}

typedef CreateSecureFileRequest =
    Future<String?> Function(FileRequestDraft draft);
typedef DownloadRequestedUpload =
    Future<void> Function(DocumentSnapshot<Map<String, dynamic>> upload);
typedef VerifyRestore = Future<bool> Function();
typedef RetryPendingUploadMetadata =
    Future<UploadMetadataRecoveryResult> Function();
typedef CleanupInterruptedTransfers = Future<void> Function();
typedef DecryptProtectedLabel = Future<String?> Function(String encryptedLabel);
typedef ResolveShareSourceLabel = Future<String?> Function(String sourceFileId);
typedef RevokeAllShareLinks = Future<ShareEmergencyRevocationResult> Function();
typedef ResolveFileRequestTitle =
    Future<String?> Function(
      String requestToken,
      Map<String, dynamic> requestData,
    );

class DataSafetyCenterPage extends StatelessWidget {
  const DataSafetyCenterPage({
    super.key,
    required this.uid,
    required this.firestore,
    required this.service,
    required this.createFileRequest,
    required this.downloadRequestedUpload,
    required this.transferJournal,
    required this.recoveryPathAvailable,
    required this.verifyRestore,
    required this.retryPendingMetadata,
    required this.cleanupInterruptedTransfers,
    required this.cleanupPlaintextTemporaryFiles,
    this.resolveFileRequestTitle,
    this.decryptProtectedLabel,
    this.resolveShareSourceLabel,
    this.revokeAllShareLinks,
    this.cancelInterruptedUpload,
  });

  final String uid;
  final FirebaseFirestore firestore;
  final SecureDriveService service;
  final CreateSecureFileRequest createFileRequest;
  final DownloadRequestedUpload downloadRequestedUpload;
  final TransferJournal transferJournal;
  final bool recoveryPathAvailable;
  final VerifyRestore verifyRestore;
  final RetryPendingUploadMetadata retryPendingMetadata;
  final CleanupInterruptedTransfers cleanupInterruptedTransfers;
  final CleanupPlaintextTemporaryFiles cleanupPlaintextTemporaryFiles;
  final ResolveFileRequestTitle? resolveFileRequestTitle;
  final DecryptProtectedLabel? decryptProtectedLabel;
  final ResolveShareSourceLabel? resolveShareSourceLabel;
  final RevokeAllShareLinks? revokeAllShareLinks;
  final Future<void> Function(String)? cancelInterruptedUpload;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Data safety center'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.health_and_safety_outlined), text: 'Status'),
              Tab(icon: Icon(Icons.history_rounded), text: 'Recovery'),
              Tab(icon: Icon(Icons.move_to_inbox_outlined), text: 'Requests'),
              Tab(icon: Icon(Icons.sync_problem_outlined), text: 'Conflicts'),
              Tab(icon: Icon(Icons.policy_outlined), text: 'Sharing'),
              Tab(icon: Icon(Icons.privacy_tip_outlined), text: 'Privacy'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TrustOverviewTab(
              cancelInterruptedUpload: cancelInterruptedUpload,
              uid: uid,
              service: service,
              transferJournal: transferJournal,
              recoveryPathAvailable: recoveryPathAvailable,
              verifyRestore: verifyRestore,
              retryPendingMetadata: retryPendingMetadata,
              cleanupInterruptedTransfers: cleanupInterruptedTransfers,
            ),
            _RecoveryTab(uid: uid, firestore: firestore, service: service),
            _RequestsTab(
              uid: uid,
              service: service,
              createFileRequest: createFileRequest,
              downloadRequestedUpload: downloadRequestedUpload,
              resolveFileRequestTitle: resolveFileRequestTitle,
            ),
            _ConflictsTab(
              uid: uid,
              service: service,
              decryptProtectedLabel: decryptProtectedLabel,
            ),
            _SharingTab(
              uid: uid,
              firestore: firestore,
              service: service,
              resolveSourceLabel: resolveShareSourceLabel,
              revokeAllShareLinks: revokeAllShareLinks,
            ),
            _PrivacyTab(
              uid: uid,
              cleanupPlaintextTemporaryFiles: cleanupPlaintextTemporaryFiles,
            ),
          ],
        ),
      ),
    ).withAppPageTitle('Data Safety Center | RonikCloud');
  }
}

class _PrivacyTab extends StatelessWidget {
  const _PrivacyTab({
    required this.uid,
    required this.cleanupPlaintextTemporaryFiles,
  });

  final String uid;
  final CleanupPlaintextTemporaryFiles cleanupPlaintextTemporaryFiles;

  @override
  Widget build(BuildContext context) {
    final reporter = AppErrorReporter.instance;
    final supportCode = privacySupportCodeForUid(uid);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Privacy controls',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'RonikCloud minimizes the account and storage identifiers exposed in routine support and operational logs.',
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.confirmation_number_outlined),
            title: const Text('Support code'),
            subtitle: SelectableText(supportCode),
            trailing: IconButton(
              tooltip: 'Copy support code',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: supportCode));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Support code copied.')),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Use this code for ordinary troubleshooting. Share your account email only when support must verify ownership, billing, or an account/privacy request.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Workspace problem reports use this opaque code, remove common identifiers and secret-like values on your device, and never attach a file, key, log, or automatic diagnostic. The text you deliberately submit remains readable by support for at most 90 days.',
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder<bool>(
          valueListenable: reporter.diagnosticsEnabled,
          builder: (context, enabled, _) {
            return Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.bug_report_outlined),
                title: const Text('Share minimal diagnostics'),
                subtitle: Text(
                  enabled
                      ? 'Enabled. Only fixed error, reason, and library codes, platform, build mode, and fatal state may be sent after sign-in. Stored automatic reports have no account ID or Support code. Exception messages and stacks, filenames, paths, workspace labels, URLs, and provider object references are excluded.'
                      : 'Off by default. No automatic app diagnostic leaves this device.',
                ),
                value: enabled,
                onChanged: (value) async {
                  try {
                    await reporter.setDiagnosticsEnabled(value);
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not update the privacy setting.'),
                      ),
                    );
                  }
                },
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        TemporaryPlaintextFilesControl(onClear: cleanupPlaintextTemporaryFiles),
        const SizedBox(height: 16),
        const _PrivacyExplanationCard(
          icon: Icons.visibility_outlined,
          title: 'What the service must process',
          body:
              'Firebase Authentication must process your sign-in email, display name, account ID, and security state. New general workspace profiles do not duplicate the email or display name and do not supply readable company labels. Business navigation uses labels decrypted for the authorized session, or neutral protected placeholders. Bounded maintenance removes older company-label mirrors immediately and removes older profile identity copies after any legacy email-derived storage identity is migrated. The service also processes plan and billing state, workspace permissions, encrypted-object sizes and upload timestamps, opaque access relationships, a coarse weekly storage-lifecycle boundary, and limited security and abuse-prevention metadata. Encrypted image previews use neutral opaque object names, and new file metadata does not classify whether a preview exists. File requests require an owner relationship, opaque request and object IDs, hourly-rounded expiry, size/upload limits, counts, status, short-lived upload authorization expiry, and encrypted payload sizes; expired authorizations release their reserved slot exactly once, and a possible encrypted orphan is removed only after a safety delay and exact storage-scope validation. New request, secret, submission, and authorization records omit exact creation, close, completion, and status-update times. The request title, submitted filename, and submitted content type are client-encrypted, while the public metadata API omits the owner identity and storage references. Routine file access sends only the opaque file ID; it does not store whether the action was an open, preview, download, restore, or share, or the precise per-file access time. Service infrastructure can still observe request timing, IP/connection data, and traffic volume. Business invitations collect no recipient address or name and perform no account lookup. The pending invitation stores only a random code hash, policy, fingerprint, and expiry, and access begins only after a signed-in recipient claims the single-use code. An admin can atomically revoke the code and pending membership without affecting active members; the fixed audit event contains no recipient identity or pending-member reference. Copied codes use a bounded clipboard lease that retains only a digest for the delayed unchanged-value check. Company audit history stores fixed action types, timestamps, company-scoped pseudonymous member references, and small policy or aggregate changes. The authorized dashboard resolves current member labels only in memory; audit records do not duplicate emails, names, raw account IDs, workspace labels, or file references and expire after the configured retention period (365 days by default).',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.forum_outlined,
          title: 'Private collaboration',
          body:
              'Comment text, review notes, display labels, and mention addresses are encrypted on your device with the file key. The service retains only the file and account identifiers, review status, timestamps, ciphertext, and minimum notification-routing data needed to operate collaboration; mention addresses are used transiently and are not stored. An original author or reviewer automatically protects their own validated older readable entry. If the response is lost, Retry protection reuses the same encrypted payload and the server verifies that the legacy review did not change. In-memory cache keys are fingerprints rather than second copies of collaboration text. If loading or updating a discussion fails, RonikCloud shows fixed recovery guidance without copying a provider response, path, token, filename, or account address onto the screen.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.mark_email_read_outlined,
          title: 'Encrypted share delivery',
          body:
              'Password-protected shares can be emailed directly to one address you choose. RonikCloud and its email provider process that address and a token-only link; the password, private file label, and content key are not included. Send the password separately. Keyed recipient fingerprints and send receipts used for abuse prevention and safe retries expire after seven days; the external email provider processes the message under its own retention terms. Email accepted is not confirmation of inbox delivery. Links without a separate password carry a random key only in their private fragment and an owner-encrypted envelope. Their email action opens your own email app, where you review the message and press Send. Anyone with that complete link can decrypt the shared copy. Expiry, revocation, source authorization, secret-derived proof and encrypted download request budgets remain enforced in both modes; already-downloaded copies cannot be recalled.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.sync_lock_outlined,
          title: 'Private Business refresh',
          body:
              'Company-access and administration refreshes preserve the last verified encrypted workspace while they retry. Personal and assigned-company file and folder snapshots are kept as independent sources and merged by opaque ID, so one arriving update or removal cannot erase a record that remains authorized by the other source. The encrypted device cache retains only local source categories needed to restore this boundary. Any company, membership, scope, group, or storage-permission change clears decrypted Business keys, names, previews, and late preview work. Losing download permission also clears assigned records and their quota contribution from visible and encrypted local state, rejects late snapshots and downloaded buffers, and prevents an in-flight offline copy from being retained. Upload-only, read-only, and restricted states expose only the currently mirrored actions; the service still rechecks the live membership for every protected operation. Lower-level metadata, provider, and encryption failures are converted to fixed recovery guidance; member IDs, object references, filenames, folder labels, response details, and arbitrary exception text are not copied into the Business interface or file/folder diagnostics.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.rule_folder_outlined,
          title: 'Confirmed Business changes',
          body:
              'A lost response does not prove that an access or policy change failed—the service may already have committed it. RonikCloud keeps the last verified dashboard visible, blocks further Business changes, and asks an administrator to refresh status before repeating anything. The app never blindly replays a sensitive mutation, and assigned-company stream diagnostics omit raw provider exceptions.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.receipt_long_outlined,
          title: 'Verified Business history',
          body:
              'The Logs tab never treats a failed activity query as an empty history. It distinguishes unavailable, verified-empty, and bounded recent results, offers a safe refresh, and derives titles from a fixed action vocabulary. File and folder names, company and group labels, comments, raw account identifiers, arbitrary server titles, and provider errors are excluded from the view.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.security_update_warning_outlined,
          title: 'Private account and checkout recovery',
          body:
              'Authentication, Account Security, recovery-kit, tester-signup, subscription-status, Stripe-management, App Store purchase, and checkout failures use fixed guidance instead of exception text, WebView descriptions, portal URLs, or API response bodies. Recovery-kit and billing exception strings retain only closed categories. Sign-in connection, security-settings, subscription-status, and checkout failures keep a visible Retry action without exposing account, provider, endpoint, transaction, file, or device details.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.link_off_outlined,
          title: 'Private link failures',
          body:
              'Public file-request and encrypted-share pages do not display API response bodies or arbitrary exceptions. They translate status, timeout, network, key, expiry, limit, encryption-metadata, and upload failures into fixed recovery guidance. A failed metadata load keeps a visible Retry action, and an encrypted upload failure does not remove the original file from the sender’s device.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.drive_file_move_outline,
          title: 'Confirmed workspace changes',
          body:
              'A lost response to a rename, move, folder change, or recycle action does not prove that the service rejected it. RonikCloud preserves the last verified file and folder view, pauses further workspace changes and uploads, and requires a server refresh before another attempt. Recovery notices and diagnostics use closed categories without filenames, folder labels, object references, account details, provider responses, arbitrary exception text, or stacks.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.cloud_download_outlined,
          title: 'Private provider import failures',
          body:
              'Connected-drive sign-in, browsing, folder selection, download, and import failures use fixed recovery guidance. Provider response bodies, remote paths, account addresses, filenames, tokens, exceptions, and stacks are not copied into the interface or migration diagnostics. The current selection remains available for a safe retry, and completed destination uploads remain encrypted.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.enhanced_encryption_outlined,
          title: 'What stays secret',
          body:
              'Your encryption passphrase, private key, recovery-kit passphrase, and recovery-kit contents are not needed by support. A recovery kit is created and opened on the device; RonikCloud does not upload it. Protected uploads encrypt file contents, names, and new folder labels on your device before storage. While a device key is locked, raw name ciphertext and encrypted object suffixes stay hidden behind generic encrypted-item placeholders; the workspace provides an explicit local unlock action. Business member envelopes are opened only with the authorized Business identity, not the Personal password-derived key. Some older accounts may retain legacy storage identifiers for compatibility.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.compare_arrows_outlined,
          title: 'Private backup comparisons',
          body:
              'Cached Personal and Business file/folder listings, raw file fingerprints, and selected backup paths stay in an authenticated local cache encrypted with a key held by your device credential store. The service receives only an account-keyed integrity tag, so it cannot compare your files with a public hash list or another customer’s files. Backup diagnostics use temporary opaque references and fixed failure categories rather than filenames, folder labels, absolute paths, exception messages, or stacks. Legacy local cache entries are protected automatically when opened.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.photo_outlined,
          title: 'Bounded photo uploads',
          body:
              'The browser reads selected files in repeatable 1 MiB slices while encrypting them instead of copying the complete selection into memory. For one image within the 24 MiB preview limit, the device may keep one bounded source snapshot so the encrypted original and later preview use identical bytes; larger images remain streamed. Optional preview decoding starts only after the encrypted original reaches storage. Stored preview downloads, legacy proxy responses, Base64 decoding, and secure-shard fallback assembly use explicit local byte ceilings. The device validates and normalizes a candidate before display, discards a corrupt or oversized derivative, and rebuilds it only from the authenticated encrypted original. Automatic retries never request a password; choosing Unlock or retry image preview may open the local unlock deliberately. When encrypted bytes are safe but a validated private metadata commit needs another attempt, RonikCloud labels the item as waiting for automatic finalization rather than a failed source upload. Provider responses, file paths, account details, and raw exception text are not shown.',
        ),
        const SizedBox(height: 12),
        const _PrivacyExplanationCard(
          icon: Icons.phonelink_lock_outlined,
          title: 'Encrypted recovery and offline vault',
          body:
              'Interrupted-transfer checkpoints, multipart upload IDs, detailed Business member-access progress and affected-space reminders, offline mappings, and directory paths use authenticated device-local encryption. Business reminder details contain only opaque company/group identifiers, reason codes, revisions, and timestamps—not member identities or file details. To notice changes made on another admin device, RonikCloud stores only bounded required/completed counters on the already-known company or group record; it does not receive the reminder reason, member, file, or label. Offline file contents are stored as chunked authenticated vault objects bound to this environment, account, object, and file key. Secure-mode copies still require the secure workspace key. Older readable offline copies are upgraded in place when their file key is available. External handoff copies use opaque names, private OS permissions where available, short automatic expiry, crash recovery, and the manual cleanup control above. Receiving apps may still retain their own copies.',
        ),
      ],
    );
  }
}

class _PrivacyExplanationCard extends StatelessWidget {
  const _PrivacyExplanationCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustOverviewTab extends StatefulWidget {
  const _TrustOverviewTab({
    required this.uid,
    required this.service,
    required this.transferJournal,
    required this.recoveryPathAvailable,
    required this.verifyRestore,
    required this.retryPendingMetadata,
    required this.cleanupInterruptedTransfers,
    this.cancelInterruptedUpload,
  });

  final String uid;
  final SecureDriveService service;
  final TransferJournal transferJournal;
  final bool recoveryPathAvailable;
  final VerifyRestore verifyRestore;
  final RetryPendingUploadMetadata retryPendingMetadata;
  final CleanupInterruptedTransfers cleanupInterruptedTransfers;
  final Future<void> Function(String)? cancelInterruptedUpload;

  @override
  State<_TrustOverviewTab> createState() => _TrustOverviewTabState();
}

class _TrustOverviewTabState extends State<_TrustOverviewTab> {
  bool _verifying = false;
  bool _cleaning = false;
  bool _retryingMetadata = false;
  String? _cancelingUpload;

  Future<void> _cancelSavedUpload(TransferJournalEntry entry) async {
    if (_cancelingUpload != null) return;
    setState(() => _cancelingUpload = entry.id);
    try {
      await widget.cancelInterruptedUpload!(entry.id);
      if (mounted) {
        _message(
          'Saved upload canceled. Select the file again to start fresh. Reserved space may take a few minutes to release.',
        );
      }
    } catch (_) {
      if (mounted) {
        _message(
          'Could not cancel this upload. Its saved progress is retained; try again when connected.',
        );
      }
    } finally {
      if (mounted) setState(() => _cancelingUpload = null);
    }
  }

  Future<void> _verifyRestore() async {
    if (_verifying) return;
    setState(() => _verifying = true);
    try {
      final verified = await widget.verifyRestore();
      if (!mounted) return;
      _message(
        verified
            ? 'Restore verification succeeded.'
            : 'Restore verification did not complete.',
      );
    } catch (_) {
      if (mounted) _message('Restore verification could not complete.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _cleanup() async {
    if (_cleaning) return;
    setState(() => _cleaning = true);
    try {
      await widget.cleanupInterruptedTransfers();
      if (!mounted) return;
      final remaining = widget.transferJournal.pendingEntries
          .where((entry) => entry.state == TransferJournalState.cleanupRequired)
          .length;
      _message(
        remaining == 0
            ? 'Interrupted multipart uploads were cleaned up safely.'
            : '$remaining multipart cleanup attempt(s) remain queued for retry.',
      );
    } catch (_) {
      if (mounted) {
        _message('Interrupted transfer cleanup could not complete.');
      }
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  Future<void> _retryMetadata() async {
    if (_retryingMetadata) return;
    setState(() => _retryingMetadata = true);
    try {
      final result = await widget.retryPendingMetadata();
      if (!mounted) return;
      final remaining = widget.transferJournal.pendingEntries
          .where((entry) => entry.canRetryMetadata)
          .length;
      _message(
        result.recovered > 0 && remaining == 0
            ? 'Finished saving ${result.recovered} previously uploaded file(s).'
            : result.attempted == 0 && result.eligible > 0
            ? 'Sign in again before finishing these uploaded files.'
            : result.attempted == 0
            ? 'No uploaded files are ready for metadata recovery.'
            : '$remaining uploaded file(s) remain queued for a safe retry.',
      );
    } catch (_) {
      if (mounted) {
        _message('Uploaded file recovery could not complete.');
      }
    } finally {
      if (mounted) setState(() => _retryingMetadata = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.transferJournal,
      builder: (context, _) {
        final journal = widget.transferJournal;
        final pending = journal.pendingEntries;
        final cleanupCount = pending
            .where(
              (entry) => entry.state == TransferJournalState.cleanupRequired,
            )
            .length;
        final metadataRetryCount = pending
            .where((entry) => entry.canRetryMetadata)
            .length;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: widget.service.watchOpenSyncConflicts(widget.uid),
          builder: (context, conflictSnapshot) {
            final conflictCount = conflictSnapshot.data?.docs.length;
            final conflictCheckFailed = conflictSnapshot.hasError;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Can I recover my files?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'These checks reflect this device and the latest durable transfer history.',
                ),
                const SizedBox(height: 16),
                _TrustStatusTile(
                  icon: Icons.manage_search_rounded,
                  title: 'Last backup scan',
                  value: _backupScanLabel(journal),
                  healthy: journal.lastBackupScanSuccessful,
                ),
                _TrustStatusTile(
                  icon: Icons.cloud_done_outlined,
                  title: 'Last successful upload',
                  value: _timeLabel(journal.lastSuccessfulUploadAt),
                  healthy: journal.lastSuccessfulUploadAt == null ? null : true,
                ),
                _TrustStatusTile(
                  icon: Icons.restore_page_outlined,
                  title: 'Last verified restore',
                  value: _timeLabel(journal.lastVerifiedRestoreAt),
                  healthy: journal.lastVerifiedRestoreAt == null ? null : true,
                ),
                _TrustStatusTile(
                  icon: Icons.sync_problem_outlined,
                  title: 'Unresolved conflicts',
                  value: conflictCheckFailed
                      ? 'Status unavailable'
                      : conflictCount == null
                      ? 'Checking…'
                      : '$conflictCount',
                  healthy: conflictCheckFailed
                      ? false
                      : conflictCount == null
                      ? null
                      : conflictCount == 0,
                ),
                _TrustStatusTile(
                  icon: Icons.queue_outlined,
                  title: 'Queued or interrupted transfers',
                  value: '${pending.length}',
                  healthy: pending.isEmpty,
                ),
                _TrustStatusTile(
                  icon: Icons.key_outlined,
                  title: 'Working recovery path on this device',
                  value: widget.recoveryPathAvailable
                      ? 'Encryption keys are available'
                      : 'Unlock or restore your encryption keys',
                  healthy: widget.recoveryPathAvailable,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _verifying || !widget.recoveryPathAvailable
                          ? null
                          : _verifyRestore,
                      icon: _verifying
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_outlined),
                      label: const Text('Verify a restore'),
                    ),
                    if (metadataRetryCount > 0)
                      OutlinedButton.icon(
                        onPressed: _retryingMetadata ? null : _retryMetadata,
                        icon: _retryingMetadata
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_sync_outlined),
                        label: Text(
                          _retryingMetadata
                              ? 'Finishing uploads…'
                              : 'Finish $metadataRetryCount upload(s)',
                        ),
                      ),
                    if (cleanupCount > 0)
                      OutlinedButton.icon(
                        onPressed: _cleaning ? null : _cleanup,
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: Text(
                          _cleaning
                              ? 'Cleaning…'
                              : 'Clean up $cleanupCount transfer(s)',
                        ),
                      ),
                  ],
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Transfer journal',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final entry in pending.take(10))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_journalIcon(entry.state)),
                      title: Text(entry.label),
                      trailing:
                          entry.state == TransferJournalState.interrupted &&
                              entry.uploadCheckpoint != null &&
                              widget.cancelInterruptedUpload != null
                          ? TextButton(
                              onPressed: _cancelingUpload != null
                                  ? null
                                  : () => _cancelSavedUpload(entry),
                              child: Text(
                                _cancelingUpload == entry.id
                                    ? 'Canceling…'
                                    : 'Cancel upload',
                              ),
                            )
                          : null,
                      subtitle: Text(
                        '${_journalStateLabel(entry)} · updated ${_timeLabel(entry.updatedAt)}',
                      ),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _TrustStatusTile extends StatelessWidget {
  const _TrustStatusTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.healthy,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool? healthy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = healthy == null
        ? colorScheme.onSurfaceVariant
        : healthy!
        ? colorScheme.primary
        : colorScheme.error;
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(value),
        trailing: Icon(
          healthy == null
              ? Icons.help_outline
              : healthy!
              ? Icons.check_circle_outline
              : Icons.error_outline,
          color: statusColor,
        ),
      ),
    );
  }
}

String _backupScanLabel(TransferJournal journal) {
  final timestamp = _timeLabel(journal.lastBackupScanAt);
  return switch (journal.lastBackupScanSuccessful) {
    true => '$timestamp · completed',
    false => '$timestamp · interrupted or failed',
    null => timestamp,
  };
}

String _timeLabel(DateTime? value) {
  if (value == null) return 'Never';
  final local = value.toLocal();
  final now = DateTime.now();
  final date =
      local.year == now.year && local.month == now.month && local.day == now.day
      ? 'Today'
      : '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  return '$date ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

IconData _journalIcon(TransferJournalState state) => switch (state) {
  TransferJournalState.cleanupRequired => Icons.cleaning_services_outlined,
  TransferJournalState.awaitingMetadata => Icons.cloud_sync_outlined,
  TransferJournalState.interrupted => Icons.pause_circle_outline,
  _ => Icons.sync_outlined,
};

String _journalStateLabel(TransferJournalEntry entry) => switch (entry.state) {
  TransferJournalState.awaitingMetadata =>
    entry.canRetryMetadata
        ? 'Encrypted upload complete; workspace entry is ready to finish'
        : 'Encrypted upload complete; retry details are unavailable',
  TransferJournalState.cleanupRequired => 'Multipart cleanup required',
  TransferJournalState.interrupted => 'Interrupted by app restart',
  TransferJournalState.inProgress => 'In progress',
  TransferJournalState.queued => 'Queued',
  _ => entry.state.name,
};

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.verified_user_outlined),
        title: const Text('Security boundary'),
        subtitle: Text(text),
      ),
    );
  }
}

class _RecoveryTab extends StatefulWidget {
  const _RecoveryTab({
    required this.uid,
    required this.firestore,
    required this.service,
  });

  final String uid;
  final FirebaseFirestore firestore;
  final SecureDriveService service;

  @override
  State<_RecoveryTab> createState() => _RecoveryTabState();
}

class _RecoveryTabState extends State<_RecoveryTab> {
  bool _busy = false;

  Future<void> _rewind(Duration duration) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore deleted files?'),
        content: Text(
          'This restores files moved to the recycle bin during the last ${duration.inHours <= 24 ? '24 hours' : '${duration.inDays} days'}. Existing encrypted objects are not overwritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.service.rewindFiles(
        DateTime.now().toUtc().subtract(duration),
      );
      if (!mounted) return;
      _message(
        result.restoredCount == 0
            ? 'No deleted files were found in that period.'
            : 'Restored ${result.restoredCount} file(s).${result.truncated ? ' Run Rewind again to restore the next batch.' : ''}',
      );
    } catch (error) {
      _message(recoveryFailureMessage(RecoveryFailureAction.rewind, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.firestore
        .collection('files')
        .where('uid', isEqualTo: widget.uid)
        .where('lifecycleState', whereIn: const ['trashed', 'version']);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        final recoverable = (snapshot.data?.docs ?? const []).toList(
          growable: false,
        )..sort((a, b) => _dateOf(b.data()).compareTo(_dateOf(a.data())));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SecurityNotice(
              text:
                  'Trash and version changes are authenticated server operations. Ciphertext remains encrypted and immutable during recovery.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () => _rewind(const Duration(days: 1)),
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Rewind 24 hours'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () => _rewind(const Duration(days: 7)),
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: const Text('Rewind 7 days'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Recycle bin and versions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (recoverable.isEmpty)
              const ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('Nothing needs recovery'),
                subtitle: Text(
                  'Deleted files and older versions will appear here.',
                ),
              )
            else
              for (final doc in recoverable)
                _RecoveryTile(
                  document: doc,
                  onRestore: () async {
                    try {
                      await widget.service.restoreFile(doc.id);
                      _message('File restored.');
                    } catch (error) {
                      _message(
                        recoveryFailureMessage(
                          RecoveryFailureAction.restoreFile,
                          error,
                        ),
                      );
                    }
                  },
                ),
          ],
        );
      },
    );
  }

  static DateTime _dateOf(Map<String, dynamic> data) {
    final raw = data['trashedAt'] ?? data['versionedAt'] ?? data['uploadedAt'];
    if (raw is Timestamp) return raw.toDate();
    return DateTime.tryParse(raw?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _RecoveryTile extends StatelessWidget {
  const _RecoveryTile({required this.document, required this.onRestore});

  final QueryDocumentSnapshot<Map<String, dynamic>> document;
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    final data = document.data();
    final state = data['lifecycleState']?.toString() ?? 'version';
    final display = _safeFileLabel(data, document.id);
    return Card(
      child: ListTile(
        leading: Icon(
          state == 'trashed' ? Icons.delete_outline : Icons.history,
        ),
        title: Text(display),
        subtitle: Text(
          state == 'trashed'
              ? 'Recycle bin · retained for recovery'
              : 'Revision ${data['revision'] ?? '?'} · older encrypted version',
        ),
        trailing: TextButton.icon(
          onPressed: () => unawaited(onRestore()),
          icon: const Icon(Icons.restore),
          label: const Text('Restore'),
        ),
      ),
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({
    required this.uid,
    required this.service,
    required this.createFileRequest,
    required this.downloadRequestedUpload,
    required this.resolveFileRequestTitle,
  });

  final String uid;
  final SecureDriveService service;
  final CreateSecureFileRequest createFileRequest;
  final DownloadRequestedUpload downloadRequestedUpload;
  final ResolveFileRequestTitle? resolveFileRequestTitle;

  Future<void> _create(BuildContext context) async {
    final draft = await _showFileRequestDialog(context);
    if (draft == null || !context.mounted) return;
    final url = await createFileRequest(draft);
    if (url == null || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Private request link copied'),
          content: SelectableText(
            '$url\n\nThe encryption key is in the URL fragment and is not sent to RonikCloud servers. Anyone with this complete link can submit encrypted files.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SecurityNotice(
          text:
              'Uploaders encrypt file contents, names, and types in their browser. Request titles are encrypted too. The public metadata API returns no owner identity, and the request key stays in the URL fragment plus an owner-encrypted envelope. New requests round expiry up to the next UTC hour and retain no exact creation, close, or submission-status time.',
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _create(context),
          icon: const Icon(Icons.add_link_rounded),
          label: const Text('Create secure file request'),
        ),
        const SizedBox(height: 18),
        Text('Incoming files', style: Theme.of(context).textTheme.titleLarge),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: service.watchRequestUploads(uid),
          builder: (context, snapshot) {
            final docs = (snapshot.data?.docs ?? const []).toList()
              ..sort(_compareRequestedUploadsForOwner);
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (docs.isEmpty) {
              return const ListTile(
                leading: Icon(Icons.inbox_outlined),
                title: Text('No requested uploads yet'),
              );
            }
            return Column(
              children: [
                for (final doc in docs)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: Text('Encrypted submission ${_shortId(doc.id)}'),
                      subtitle: Text(
                        '${_formatBytes(_number(doc.data()['plainSize']))} · ${doc.data()['status'] ?? 'pending'}',
                      ),
                      trailing: TextButton.icon(
                        onPressed: () =>
                            unawaited(downloadRequestedUpload(doc)),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Decrypt'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Text('Active requests', style: Theme.of(context).textTheme.titleLarge),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: service.watchFileRequests(uid),
          builder: (context, snapshot) {
            final docs = (snapshot.data?.docs ?? const []).toList()
              ..sort(_compareFileRequestsForOwner);
            if (docs.isEmpty) {
              return const ListTile(title: Text('No requests created yet'));
            }
            return Column(
              children: [
                for (final doc in docs)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        doc.data()['revoked'] == true
                            ? Icons.link_off
                            : Icons.upload_file,
                      ),
                      title: _FileRequestTitle(
                        documentId: doc.id,
                        data: doc.data(),
                        resolver: resolveFileRequestTitle,
                      ),
                      subtitle: Text(_fileRequestOwnerSubtitle(doc.data())),
                      trailing: doc.data()['revoked'] == true
                          ? const Text('Closed')
                          : TextButton(
                              onPressed: () =>
                                  unawaited(service.revokeFileRequest(doc.id)),
                              child: const Text('Close'),
                            ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

int _compareRequestedUploadsForOwner(
  QueryDocumentSnapshot<Map<String, dynamic>> left,
  QueryDocumentSnapshot<Map<String, dynamic>> right,
) {
  int statusRank(String value) => switch (value) {
    'pending' => 0,
    'rejected' => 1,
    'accepted' => 2,
    _ => 3,
  };

  final statusOrder = statusRank(
    left.data()['status']?.toString() ?? '',
  ).compareTo(statusRank(right.data()['status']?.toString() ?? ''));
  return statusOrder != 0 ? statusOrder : left.id.compareTo(right.id);
}

int _compareFileRequestsForOwner(
  QueryDocumentSnapshot<Map<String, dynamic>> left,
  QueryDocumentSnapshot<Map<String, dynamic>> right,
) {
  final leftClosed = left.data()['revoked'] == true;
  final rightClosed = right.data()['revoked'] == true;
  if (leftClosed != rightClosed) return leftClosed ? 1 : -1;

  final leftExpiry = _shareTimestamp(left.data()['expiresAt']);
  final rightExpiry = _shareTimestamp(right.data()['expiresAt']);
  if (leftExpiry != null && rightExpiry != null) {
    final expiryOrder = leftExpiry.compareTo(rightExpiry);
    if (expiryOrder != 0) return expiryOrder;
  } else if (leftExpiry != null) {
    return -1;
  } else if (rightExpiry != null) {
    return 1;
  }
  return left.id.compareTo(right.id);
}

String _fileRequestOwnerSubtitle(Map<String, dynamic> data) {
  final base = '${data['uploadCount'] ?? 0}/${data['maxUploads'] ?? 0} uploads';
  final expiry = _shareTimestamp(data['expiresAt']);
  return expiry == null ? base : '$base · Expires around ${_timeLabel(expiry)}';
}

class _FileRequestTitle extends StatefulWidget {
  const _FileRequestTitle({
    required this.documentId,
    required this.data,
    required this.resolver,
  });

  final String documentId;
  final Map<String, dynamic> data;
  final ResolveFileRequestTitle? resolver;

  @override
  State<_FileRequestTitle> createState() => _FileRequestTitleState();
}

class _FileRequestTitleState extends State<_FileRequestTitle> {
  Future<String?>? _resolvedTitle;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _FileRequestTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId ||
        oldWidget.data['encryptedTitleBase64'] !=
            widget.data['encryptedTitleBase64'] ||
        oldWidget.resolver != widget.resolver) {
      _resolve();
    }
  }

  void _resolve() {
    final resolver = widget.resolver;
    _resolvedTitle = resolver == null
        ? null
        : resolver(widget.documentId, widget.data);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _resolvedTitle,
      builder: (context, snapshot) {
        final resolved = snapshot.data?.trim();
        final legacy = widget.data['title']?.toString().trim();
        final title = resolved != null && resolved.isNotEmpty
            ? resolved
            : legacy != null && legacy.isNotEmpty
            ? legacy
            : 'Private request ${_shortId(widget.documentId)}';
        return Text(title);
      },
    );
  }
}

class _ConflictsTab extends StatelessWidget {
  const _ConflictsTab({
    required this.uid,
    required this.service,
    this.decryptProtectedLabel,
  });

  final String uid;
  final SecureDriveService service;
  final DecryptProtectedLabel? decryptProtectedLabel;

  Widget _conflictTitle(Map<String, dynamic> data) {
    final legacyLabel = data['fileLabel']?.toString().trim();
    if (legacyLabel != null && legacyLabel.isNotEmpty) {
      return Text(legacyLabel);
    }
    final encryptedLabel = data['encryptedFileLabel']?.toString().trim();
    final decrypt = decryptProtectedLabel;
    if (encryptedLabel == null || encryptedLabel.isEmpty || decrypt == null) {
      return const Text('Encrypted changed file');
    }
    return FutureBuilder<String?>(
      future: decrypt(encryptedLabel),
      builder: (context, snapshot) {
        final label = snapshot.data?.trim();
        return Text(
          label == null || label.isEmpty ? 'Encrypted changed file' : label,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SecurityNotice(
          text:
              'When both the local and remote copy changed, automatic upload stops. RonikCloud never silently overwrites either copy.',
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: service.watchOpenSyncConflicts(uid),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? const [];
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (docs.isEmpty) {
              return const ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('No unresolved sync conflicts'),
              );
            }
            return Column(
              children: [
                for (final doc in docs)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.sync_problem_outlined),
                      title: _conflictTitle(doc.data()),
                      subtitle: Text(
                        doc.data()['encryptedFileLabel'] == null
                            ? 'Both local and remote content changed.'
                            : 'Both copies changed. The filename remains '
                                  'encrypted in the service record.',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) => unawaited(
                          service.resolveSyncConflict(
                            conflictId: doc.id,
                            resolution: value,
                          ),
                        ),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'keep_both',
                            child: Text('Upload local as separate copy'),
                          ),
                          PopupMenuItem(
                            value: 'keep_local',
                            child: Text('Upload local as next version'),
                          ),
                          PopupMenuItem(
                            value: 'keep_remote',
                            child: Text('Keep remote; ignore local once'),
                          ),
                          PopupMenuItem(
                            value: 'dismissed',
                            child: Text('Dismiss and ignore once'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SharingTab extends StatefulWidget {
  const _SharingTab({
    required this.uid,
    required this.firestore,
    required this.service,
    this.resolveSourceLabel,
    this.revokeAllShareLinks,
  });

  final String uid;
  final FirebaseFirestore firestore;
  final SecureDriveService service;
  final ResolveShareSourceLabel? resolveSourceLabel;
  final RevokeAllShareLinks? revokeAllShareLinks;

  @override
  State<_SharingTab> createState() => _SharingTabState();
}

class _SharingTabState extends State<_SharingTab> {
  bool _revokingAll = false;

  @override
  Widget build(BuildContext context) {
    final query = widget.firestore
        .collection('shared_links')
        .where('uid', isEqualTo: widget.uid);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SecurityNotice(
          text:
              'Passwords remain client-side decryption secrets. New links send a password-derived proof before encrypted bytes can leave storage. Every new link has a request budget; expiry, revocation and counters are enforced atomically by the backend. Generic first-access, near-budget, and blocked-proof alerts contain no filename, recipient, token, or file identifier. New expiry boundaries are rounded up to the next UTC hour; exact creation, revocation, update, and access times are not retained. Every metadata or download request also rechecks that the source is active and that the creator still has current Business membership plus share and download permission. File-card badges are derived on this device from links owned by your account; no share flag, count, or exact last-share time is copied onto the file record. Other Business members do not receive your badge.',
        ),
        if (widget.revokeAllShareLinks != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _revokingAll ? null : _revokeEveryShare,
            icon: _revokingAll
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.emergency_outlined),
            label: Text(
              _revokingAll
                  ? 'Revoking every link...'
                  : 'Emergency: revoke every link',
            ),
          ),
        ],
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? const [];
            if (docs.isEmpty) {
              return const ListTile(title: Text('No share links yet'));
            }
            return Column(
              children: [
                for (final doc in docs)
                  Card(
                    child: Builder(
                      builder: (context) {
                        final summary = ShareLinkOwnerSummary.fromMap(
                          doc.data(),
                          timestampParser: _shareTimestamp,
                        );
                        return ListTile(
                          leading: Icon(
                            summary.requiresSecurityAttention
                                ? Icons.gpp_maybe_outlined
                                : summary.statusLabel(DateTime.now().toUtc()) ==
                                      'Active'
                                ? Icons.link
                                : Icons.link_off,
                          ),
                          title: _ShareSourceTitle(
                            documentId: doc.id,
                            data: doc.data(),
                            resolver: widget.resolveSourceLabel,
                          ),
                          subtitle: Text(
                            '${summary.requestCountLabel}\n'
                            '${summary.proofLabel}\n'
                            '${summary.alertLabel}\n'
                            '${summary.budgetAlertLabel}'
                            '${summary.abuseAlertLabel == null ? '' : '\n${summary.abuseAlertLabel}'}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Edit link policy',
                            icon: const Icon(Icons.tune_rounded),
                            onPressed: () =>
                                _editSharePolicy(context, widget.service, doc),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _revokeEveryShare() async {
    final action = widget.revokeAllShareLinks;
    if (action == null || _revokingAll) {
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Revoke every share link?'),
            content: const Text(
              'This immediately closes every active share link owned by '
              'this account, across Personal and Business files. Existing '
              'downloaded copies cannot be recalled. This action cannot be '
              'undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep links'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('Revoke every link'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _revokingAll = true);
    try {
      final result = await action();
      if (!mounted) {
        return;
      }
      final noun = result.revokedCount == 1 ? 'link' : 'links';
      _showMessage(
        result.complete
            ? 'Revoked ${result.revokedCount} active password $noun.'
            : 'Revoked ${result.revokedCount} password $noun. More remain; run emergency revoke again.',
      );
    } on ShareOwnerException catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(switch (error.kind) {
        ShareOwnerFailureKind.sessionExpired =>
          'Sign in again before revoking share links.',
        ShareOwnerFailureKind.temporarilyLimited =>
          'Share links were revoked recently. Refresh and retry shortly.',
        ShareOwnerFailureKind.unavailable ||
        ShareOwnerFailureKind.invalidResponse =>
          'Could not verify that every share link was revoked. Refresh and retry.',
      });
    } finally {
      if (mounted) {
        setState(() => _revokingAll = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ShareSourceTitle extends StatefulWidget {
  const _ShareSourceTitle({
    required this.documentId,
    required this.data,
    required this.resolver,
  });

  final String documentId;
  final Map<String, dynamic> data;
  final ResolveShareSourceLabel? resolver;

  @override
  State<_ShareSourceTitle> createState() => _ShareSourceTitleState();
}

class _ShareSourceTitleState extends State<_ShareSourceTitle> {
  Future<String?>? _resolvedLabel;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _ShareSourceTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId ||
        oldWidget.data['sourceFileId'] != widget.data['sourceFileId'] ||
        oldWidget.resolver != widget.resolver) {
      _resolve();
    }
  }

  void _resolve() {
    final sourceFileId = widget.data['sourceFileId']?.toString().trim() ?? '';
    _resolvedLabel = sourceFileId.isEmpty || widget.resolver == null
        ? null
        : widget.resolver!(sourceFileId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _resolvedLabel,
      builder: (context, snapshot) {
        final resolved = snapshot.data?.trim();
        final legacyLabel = widget.data['linkLabel']?.toString().trim();
        final title = resolved != null && resolved.isNotEmpty
            ? resolved
            : legacyLabel != null && legacyLabel.isNotEmpty
            ? legacyLabel
            : 'Share ${_shortId(widget.documentId)}';
        return Text(title);
      },
    );
  }
}

Future<FileRequestDraft?> _showFileRequestDialog(BuildContext context) async {
  final title = TextEditingController();
  var expiryDays = 7;
  var maxMegabytes = 25;
  var maxUploads = 10;
  try {
    return await showDialog<FileRequestDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create secure file request'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 160,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Request title',
                    hintText: 'Send me the event photos',
                  ),
                ),
                DropdownButtonFormField<int>(
                  initialValue: expiryDays,
                  decoration: const InputDecoration(labelText: 'Expires after'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 day')),
                    DropdownMenuItem(value: 7, child: Text('7 days')),
                    DropdownMenuItem(value: 14, child: Text('14 days')),
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                  ],
                  onChanged: (value) => setState(() => expiryDays = value ?? 7),
                ),
                DropdownButtonFormField<int>(
                  initialValue: maxMegabytes,
                  decoration: const InputDecoration(
                    labelText: 'Maximum file size',
                  ),
                  items: const [
                    DropdownMenuItem(value: 10, child: Text('10 MB')),
                    DropdownMenuItem(value: 25, child: Text('25 MB')),
                    DropdownMenuItem(value: 50, child: Text('50 MB')),
                    DropdownMenuItem(value: 100, child: Text('100 MB')),
                  ],
                  onChanged: (value) =>
                      setState(() => maxMegabytes = value ?? 25),
                ),
                DropdownButtonFormField<int>(
                  initialValue: maxUploads,
                  decoration: const InputDecoration(labelText: 'Upload count'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 file')),
                    DropdownMenuItem(value: 5, child: Text('5 files')),
                    DropdownMenuItem(value: 10, child: Text('10 files')),
                    DropdownMenuItem(value: 25, child: Text('25 files')),
                  ],
                  onChanged: (value) =>
                      setState(() => maxUploads = value ?? 10),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: title.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      FileRequestDraft(
                        title: title.text.trim(),
                        expiryDays: expiryDays,
                        maxFileBytes: maxMegabytes * 1024 * 1024,
                        maxUploads: maxUploads,
                      ),
                    ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  } finally {
    title.dispose();
  }
}

Future<void> _editSharePolicy(
  BuildContext context,
  SecureDriveService service,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) async {
  final current = _number(doc.data()['maxDownloads']);
  final controller = TextEditingController(
    text: (current >= 1 && current <= 1000 ? current : 10).toString(),
  );
  var notify = doc.data()['notifyOnAccess'] == true;
  String? budgetError;
  final firstAccessNotified =
      doc.data()['firstAccessNotified'] == true ||
      _shareTimestamp(doc.data()['firstAccessNotifiedAt']) != null;
  try {
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Share policy'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Encrypted payload request budget',
                  helperText:
                      'Choose 1 to 1000 requests. Unlimited links are not created.',
                ).copyWith(errorText: budgetError),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: notify,
                title: Text(
                  !firstAccessNotified
                      ? 'Record a generic first-access event'
                      : 'First-access event already recorded',
                ),
                subtitle: Text(
                  !firstAccessNotified
                      ? 'No recipient, filename, token or file identifier is '
                            'added to the event.'
                      : 'The one-bit sent state prevents repeats; an exact '
                            'share-access timestamp is not retained.',
                ),
                onChanged: !firstAccessNotified
                    ? (value) => setState(() => notify = value)
                    : null,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null || parsed < 1 || parsed > 1000) {
                  setState(() {
                    budgetError = 'Enter a request budget from 1 to 1000.';
                  });
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await service.updateSharePolicy(
        token: doc.id,
        maxDownloads: int.parse(controller.text.trim()),
        notifyOnAccess: notify,
      );
    }
  } finally {
    controller.dispose();
  }
}

String _safeFileLabel(Map<String, dynamic> data, String id) {
  for (final key in const ['originalName', 'encryptedName']) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  final objectKey = data['fileName']?.toString() ?? '';
  final tail = objectKey.split('/').last.trim();
  return tail.isEmpty ? 'File ${_shortId(id)}' : tail;
}

String _shortId(String value) =>
    value.length <= 8 ? value : value.substring(0, 8);

int _number(Object? value) {
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _formatBytes(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB'
    : '${(bytes / 1024).toStringAsFixed(0)} KB';

DateTime? _shareTimestamp(Object? value) {
  if (value is Timestamp) {
    return value.toDate().toUtc();
  }
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}
