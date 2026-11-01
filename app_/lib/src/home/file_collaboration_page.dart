import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';

import '../security/file_collaboration_cache.dart';
import '../security/file_collaboration_encryption.dart';
import '../security/file_collaboration_failure.dart';
import '../shared/app_page_title.dart';
import '../storage/secure_drive_service.dart';

class FileCollaborationPage extends StatefulWidget {
  const FileCollaborationPage({
    super.key,
    required this.fileId,
    required this.fileName,
    required this.userId,
    required this.userName,
    required this.encryptionKey,
    required this.firestore,
    required this.service,
    this.encryption,
  });

  final String fileId;
  final String fileName;
  final String userId;
  final String userName;
  final SecretKey encryptionKey;
  final FirebaseFirestore firestore;
  final SecureDriveService service;
  final FileCollaborationEncryption? encryption;

  @override
  State<FileCollaborationPage> createState() => _FileCollaborationPageState();
}

class _FileCollaborationPageState extends State<FileCollaborationPage> {
  final TextEditingController _commentController = TextEditingController();
  final Map<String, _CachedComment> _commentCache = <String, _CachedComment>{};
  final Set<String> _legacyMigrationsStarted = <String>{};
  final Set<String> _legacyMigrationFailures = <String>{};
  final Set<String> _legacyMigrationsBusy = <String>{};
  final Map<String, String> _legacyPendingPayloads = <String, String>{};
  late final FileCollaborationEncryption _encryption;
  _CachedReview? _reviewCache;
  String? _legacyReviewPendingPayload;
  String? _legacyReviewPendingFingerprint;
  String? _legacyReviewMigrationTarget;
  bool _legacyReviewMigrationFailed = false;
  bool _legacyReviewMigrationBusy = false;
  bool _sending = false;
  bool _reviewing = false;

  @override
  void initState() {
    super.initState();
    _encryption = widget.encryption ?? FileCollaborationEncryption();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _commentController.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      final body = SecureFeatureValidation.comment(_commentController.text);
      final mentions = SecureFeatureValidation.mentionsFromComment(body);
      final commentId = widget.service.newFileCommentId();
      final encryptedPayload = await _encryption.sealComment(
        fileId: widget.fileId,
        commentId: commentId,
        authorUid: widget.userId,
        authorName: widget.userName,
        body: body,
        mentions: mentions,
        key: widget.encryptionKey,
      );
      await widget.service.saveEncryptedComment(
        fileId: widget.fileId,
        commentId: commentId,
        encryptedPayload: encryptedPayload,
        mentions: mentions,
      );
      _commentController.clear();
    } catch (error) {
      _message(
        fileCollaborationFailureMessage(
          error,
          action: FileCollaborationAction.sendComment,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _review(String status) async {
    if (_reviewing) return;
    setState(() => _reviewing = true);
    try {
      final encryptedPayload = await _encryption.sealReview(
        fileId: widget.fileId,
        reviewerUid: widget.userId,
        reviewerName: widget.userName,
        key: widget.encryptionKey,
      );
      await widget.service.setEncryptedReview(
        fileId: widget.fileId,
        status: status,
        encryptedPayload: encryptedPayload,
      );
      _message(status == 'approved' ? 'File approved.' : 'Changes requested.');
    } catch (error) {
      _message(
        fileCollaborationFailureMessage(
          error,
          action: FileCollaborationAction.updateReview,
        ),
      );
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<_ResolvedComment> _resolveComment(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final cacheKey = fileCollaborationCacheFingerprint(<Object?>[
      data['encryptionFormat'],
      data['encryptedPayload'],
      data['authorUid'],
      data['authorName'],
      data['body'],
      data['mentions'],
      data['updatedAt'],
    ]);
    final cached = _commentCache[document.id];
    if (cached != null && cached.cacheKey == cacheKey) {
      return cached.value;
    }
    final value = _openComment(document.id, data);
    _commentCache[document.id] = _CachedComment(cacheKey, value);
    return value;
  }

  Future<_ResolvedComment> _openComment(
    String commentId,
    Map<String, dynamic> data,
  ) async {
    final authorUid = data['authorUid']?.toString().trim() ?? '';
    final encryptedPayload = data['encryptedPayload']?.toString().trim() ?? '';
    if (data['encryptionFormat'] == fileCollaborationEncryptionFormat &&
        encryptedPayload.isNotEmpty &&
        authorUid.isNotEmpty) {
      _legacyPendingPayloads.remove(commentId);
      _legacyMigrationFailures.remove(commentId);
      try {
        final protected = await _encryption.openComment(
          fileId: widget.fileId,
          commentId: commentId,
          authorUid: authorUid,
          encryptedPayload: encryptedPayload,
          key: widget.encryptionKey,
        );
        return _ResolvedComment(
          authorName: protected.authorName,
          body: protected.body,
        );
      } catch (_) {
        return const _ResolvedComment.unreadable();
      }
    }

    late final ProtectedFileComment legacy;
    try {
      legacy = _encryption.normalizeLegacyComment(
        authorName: data['authorName'],
        body: data['body'],
        mentions: data['mentions'] ?? const <String>[],
      );
    } catch (_) {
      return const _ResolvedComment.unreadable();
    }
    final canProtect = authorUid == widget.userId;
    if (canProtect && _legacyMigrationsStarted.add(commentId)) {
      unawaited(
        _protectLegacyComment(
          commentId: commentId,
          authorName: legacy.authorName,
          body: legacy.body,
          mentions: legacy.mentions,
        ),
      );
    }
    return _ResolvedComment(
      authorName: legacy.authorName,
      body: legacy.body,
      mentions: legacy.mentions,
      legacy: true,
      canProtect: canProtect,
      migrationFailed: _legacyMigrationFailures.contains(commentId),
    );
  }

  Future<void> _protectLegacyComment({
    required String commentId,
    required String authorName,
    required String body,
    required List<String> mentions,
  }) async {
    if (!_legacyMigrationsBusy.add(commentId)) return;
    _legacyMigrationFailures.remove(commentId);
    _commentCache.remove(commentId);
    try {
      final encryptedPayload =
          _legacyPendingPayloads[commentId] ??
          await _encryption.sealComment(
            fileId: widget.fileId,
            commentId: commentId,
            authorUid: widget.userId,
            authorName: authorName,
            body: body,
            mentions: mentions,
            key: widget.encryptionKey,
          );
      _legacyPendingPayloads[commentId] = encryptedPayload;
      await widget.service.saveEncryptedComment(
        fileId: widget.fileId,
        commentId: commentId,
        encryptedPayload: encryptedPayload,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _legacyMigrationFailures.add(commentId);
          _commentCache.remove(commentId);
        });
      }
    } finally {
      _legacyMigrationsBusy.remove(commentId);
      if (mounted) {
        setState(() => _commentCache.remove(commentId));
      }
    }
  }

  void _retryLegacyComment(String commentId, _ResolvedComment comment) {
    if (!comment.canProtect || !comment.legacy) return;
    setState(() {
      _legacyMigrationFailures.remove(commentId);
      _commentCache.remove(commentId);
    });
    unawaited(
      _protectLegacyComment(
        commentId: commentId,
        authorName: comment.authorName,
        body: comment.body,
        mentions: comment.mentions,
      ),
    );
  }

  Future<_ResolvedReview> _resolveReview(
    Map<String, dynamic>? data,
    String status,
  ) {
    if (data == null) {
      return Future<_ResolvedReview>.value(const _ResolvedReview());
    }
    final cacheKey = fileCollaborationCacheFingerprint(<Object?>[
      data['encryptionFormat'],
      data['encryptedPayload'],
      data['reviewerUid'],
      data['reviewerName'],
      data['note'],
      status,
      data['updatedAt'],
    ]);
    final cached = _reviewCache;
    if (cached != null && cached.cacheKey == cacheKey) {
      return cached.value;
    }
    final value = _openReview(data, status);
    _reviewCache = _CachedReview(cacheKey, value);
    return value;
  }

  Future<_ResolvedReview> _openReview(
    Map<String, dynamic> data,
    String status,
  ) async {
    final reviewerUid = data['reviewerUid']?.toString().trim() ?? '';
    final encryptedPayload = data['encryptedPayload']?.toString().trim() ?? '';
    if (data['encryptionFormat'] == fileCollaborationEncryptionFormat &&
        encryptedPayload.isNotEmpty &&
        reviewerUid.isNotEmpty) {
      _legacyReviewPendingPayload = null;
      _legacyReviewPendingFingerprint = null;
      _legacyReviewMigrationTarget = null;
      _legacyReviewMigrationFailed = false;
      try {
        final protected = await _encryption.openReview(
          fileId: widget.fileId,
          reviewerUid: reviewerUid,
          encryptedPayload: encryptedPayload,
          key: widget.encryptionKey,
        );
        return _ResolvedReview(
          reviewerName: protected.reviewerName,
          note: protected.note,
        );
      } catch (_) {
        return const _ResolvedReview(unreadable: true);
      }
    }
    late final ProtectedFileReview legacy;
    try {
      legacy = _encryption.normalizeLegacyReview(
        reviewerName: data['reviewerName'],
        note: data['note'] ?? '',
      );
    } catch (_) {
      return const _ResolvedReview(unreadable: true);
    }
    final canProtect =
        reviewerUid == widget.userId &&
        const <String>{
          'pending',
          'approved',
          'changes_requested',
        }.contains(status);
    final legacyFingerprint = fileCollaborationLegacyReviewFingerprint(
      fileId: widget.fileId,
      reviewerUid: reviewerUid,
      status: status,
      reviewerName: legacy.reviewerName,
      note: legacy.note,
    );
    if (canProtect &&
        !_legacyReviewMigrationBusy &&
        _legacyReviewMigrationTarget != legacyFingerprint) {
      _legacyReviewMigrationTarget = legacyFingerprint;
      _legacyReviewPendingPayload = null;
      _legacyReviewPendingFingerprint = null;
      _legacyReviewMigrationFailed = false;
      unawaited(
        _protectLegacyReview(
          status: status,
          reviewerName: legacy.reviewerName,
          note: legacy.note,
          legacyFingerprint: legacyFingerprint,
        ),
      );
    }
    return _ResolvedReview(
      reviewerName: legacy.reviewerName,
      note: legacy.note,
      legacy: true,
      canProtect: canProtect,
      legacyFingerprint: legacyFingerprint,
      migrationFailed: _legacyReviewMigrationFailed,
    );
  }

  Future<void> _protectLegacyReview({
    required String status,
    required String reviewerName,
    required String note,
    required String legacyFingerprint,
  }) async {
    if (_legacyReviewMigrationBusy) return;
    _legacyReviewMigrationBusy = true;
    _legacyReviewMigrationFailed = false;
    _reviewCache = null;
    try {
      if (_legacyReviewPendingFingerprint != legacyFingerprint) {
        _legacyReviewPendingPayload = null;
        _legacyReviewPendingFingerprint = legacyFingerprint;
      }
      final encryptedPayload =
          _legacyReviewPendingPayload ??
          await _encryption.sealReview(
            fileId: widget.fileId,
            reviewerUid: widget.userId,
            reviewerName: reviewerName,
            note: note,
            key: widget.encryptionKey,
          );
      _legacyReviewPendingPayload = encryptedPayload;
      await widget.service.setEncryptedReview(
        fileId: widget.fileId,
        status: status,
        encryptedPayload: encryptedPayload,
        migrationOnly: true,
        legacyFingerprint: legacyFingerprint,
      );
    } catch (_) {
      _legacyReviewMigrationFailed = true;
    } finally {
      _legacyReviewMigrationBusy = false;
      _reviewCache = null;
      if (mounted) setState(() {});
    }
  }

  void _retryLegacyReview(_ResolvedReview review, String status) {
    final legacyFingerprint = review.legacyFingerprint;
    if (!review.canProtect ||
        !review.legacy ||
        legacyFingerprint == null ||
        legacyFingerprint.isEmpty) {
      return;
    }
    setState(() {
      _legacyReviewMigrationFailed = false;
      _reviewCache = null;
    });
    unawaited(
      _protectLegacyReview(
        status: status,
        reviewerName: review.reviewerName,
        note: review.note,
        legacyFingerprint: legacyFingerprint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Discuss ${widget.fileName}')),
      body: SafeArea(
        child: Column(
          children: [
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: widget.firestore
                  .collection('file_reviews')
                  .doc(widget.fileId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _CollaborationUnavailableCard(
                    title: 'Review status unavailable',
                    message:
                        'The encrypted review could not be loaded. Check your connection, then retry.',
                    onRetry: () => setState(() {}),
                  );
                }
                final review = snapshot.data?.data();
                final status = review?['status']?.toString() ?? 'pending';
                return FutureBuilder<_ResolvedReview>(
                  future: _resolveReview(review, status),
                  builder: (context, protectedSnapshot) {
                    final details =
                        protectedSnapshot.data ?? const _ResolvedReview();
                    return _ReviewCard(
                      status: status,
                      details: details,
                      busy: _reviewing,
                      protectingLegacy: _legacyReviewMigrationBusy,
                      onRetryProtection: details.canProtect
                          ? () => _retryLegacyReview(details, status)
                          : null,
                      onRequestChanges: () => _review('changes_requested'),
                      onApprove: () => _review('approved'),
                    );
                  },
                );
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: Icon(Icons.enhanced_encryption_outlined),
                title: Text('Discussion text is encrypted on this device'),
                subtitle: Text(
                  'RonikCloud stores only ciphertext plus the file, account, '
                  'status, time, and minimum notification-routing identifiers. '
                  'Mention addresses are used transiently and are not stored.',
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: widget.service.watchComments(widget.fileId),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _CollaborationUnavailableView(
                      title: 'Encrypted comments unavailable',
                      message:
                          'Comments could not be loaded. Check your connection or file access, then retry.',
                      onRetry: () => setState(() {}),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final comments = snapshot.data?.docs ?? const [];
                  if (comments.isEmpty) {
                    return const Center(child: Text('No comments yet.'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final document = comments[index];
                      return FutureBuilder<_ResolvedComment>(
                        future: _resolveComment(document),
                        builder: (context, protectedSnapshot) {
                          if (!protectedSnapshot.hasData) {
                            return const Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Icon(Icons.lock_clock_outlined),
                                ),
                                title: Text('Opening protected comment...'),
                              ),
                            );
                          }
                          final comment = protectedSnapshot.data!;
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Icon(
                                  comment.unreadable
                                      ? Icons.gpp_bad_outlined
                                      : Icons.person_outline,
                                ),
                              ),
                              title: Text(comment.authorName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(comment.body),
                                  if (comment.legacy) ...[
                                    const SizedBox(height: 4),
                                    LegacyCollaborationProtectionNotice(
                                      kind:
                                          LegacyCollaborationEntryKind.comment,
                                      canProtect: comment.canProtect,
                                      failed: comment.migrationFailed,
                                      busy: _legacyMigrationsBusy.contains(
                                        document.id,
                                      ),
                                      onRetry: () => _retryLegacyComment(
                                        document.id,
                                        comment,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: Text(
                                _timeLabel(document.data()['createdAt']),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      decoration: const InputDecoration(
                        labelText: 'Encrypted comment',
                        hintText: 'Use @person@example.com to mention someone',
                        helperText: 'Encrypted before it leaves this device',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => unawaited(_send()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Encrypt and send comment',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).withAppPageTitle('File Discussion | RonikCloud');
  }

  static String _reviewLabel(String status) => switch (status) {
    'approved' => 'Approved',
    'changes_requested' => 'Changes requested',
    _ => 'Awaiting review',
  };

  static String _timeLabel(Object? value) {
    if (value is! Timestamp) return '';
    final local = value.toDate().toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _CollaborationUnavailableCard extends StatelessWidget {
  const _CollaborationUnavailableCard({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: ListTile(
        leading: const Icon(Icons.cloud_off_outlined),
        title: Text(title),
        subtitle: Text(message),
        trailing: IconButton(
          tooltip: 'Retry',
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ),
    );
  }
}

class _CollaborationUnavailableView extends StatelessWidget {
  const _CollaborationUnavailableView({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

enum LegacyCollaborationEntryKind { comment, review }

class LegacyCollaborationProtectionNotice extends StatelessWidget {
  const LegacyCollaborationProtectionNotice({
    super.key,
    required this.kind,
    required this.canProtect,
    required this.failed,
    required this.busy,
    this.onRetry,
  });

  final LegacyCollaborationEntryKind kind;
  final bool canProtect;
  final bool failed;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = failed && canProtect
        ? 'Protection could not be confirmed. Retry uses the same encrypted payload safely.'
        : canProtect
        ? kind == LegacyCollaborationEntryKind.comment
              ? 'Older readable comment; protecting it now on this device.'
              : 'Older readable reviewer details are being protected on this device.'
        : kind == LegacyCollaborationEntryKind.comment
        ? 'Older readable comment. Its original author must open it to remove the readable provider copy.'
        : 'Older reviewer details remain readable until the original reviewer opens this file or a new protected review replaces them.';
    final canRetry = failed && canProtect && onRetry != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: failed || !canProtect
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        ),
        if (canRetry)
          TextButton.icon(
            onPressed: busy ? null : onRetry,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.enhanced_encryption),
            label: const Text('Retry protection'),
          ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.status,
    required this.details,
    required this.busy,
    required this.protectingLegacy,
    required this.onRetryProtection,
    required this.onRequestChanges,
    required this.onApprove,
  });

  final String status;
  final _ResolvedReview details;
  final bool busy;
  final bool protectingLegacy;
  final VoidCallback? onRetryProtection;
  final VoidCallback onRequestChanges;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final description = details.unreadable
        ? 'Protected reviewer details could not be verified on this device.'
        : details.reviewerName.isEmpty
        ? null
        : details.note.isEmpty
        ? 'Reviewed by ${details.reviewerName}'
        : 'Reviewed by ${details.reviewerName}: ${details.note}';
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  status == 'approved'
                      ? Icons.verified_outlined
                      : status == 'changes_requested'
                      ? Icons.rate_review_outlined
                      : Icons.pending_actions_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_FileCollaborationPageState._reviewLabel(status)),
                      if (description != null)
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (details.legacy)
                        LegacyCollaborationProtectionNotice(
                          kind: LegacyCollaborationEntryKind.review,
                          canProtect: details.canProtect,
                          failed: details.migrationFailed,
                          busy: protectingLegacy,
                          onRetry: onRetryProtection,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: busy || protectingLegacy ? null : onRequestChanges,
                  child: const Text('Request changes'),
                ),
                FilledButton.tonal(
                  onPressed: busy || protectingLegacy ? null : onApprove,
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolvedComment {
  const _ResolvedComment({
    required this.authorName,
    required this.body,
    this.mentions = const <String>[],
    this.legacy = false,
    this.canProtect = false,
    this.migrationFailed = false,
  }) : unreadable = false;

  const _ResolvedComment.unreadable()
    : authorName = 'Protected comment',
      body = 'This comment could not be verified on this device.',
      mentions = const <String>[],
      legacy = false,
      canProtect = false,
      migrationFailed = false,
      unreadable = true;

  final String authorName;
  final String body;
  final List<String> mentions;
  final bool legacy;
  final bool canProtect;
  final bool migrationFailed;
  final bool unreadable;
}

class _ResolvedReview {
  const _ResolvedReview({
    this.reviewerName = '',
    this.note = '',
    this.legacy = false,
    this.canProtect = false,
    this.legacyFingerprint,
    this.migrationFailed = false,
    this.unreadable = false,
  });

  final String reviewerName;
  final String note;
  final bool legacy;
  final bool canProtect;
  final String? legacyFingerprint;
  final bool migrationFailed;
  final bool unreadable;
}

class _CachedComment {
  const _CachedComment(this.cacheKey, this.value);

  final String cacheKey;
  final Future<_ResolvedComment> value;
}

class _CachedReview {
  const _CachedReview(this.cacheKey, this.value);

  final String cacheKey;
  final Future<_ResolvedReview> value;
}
