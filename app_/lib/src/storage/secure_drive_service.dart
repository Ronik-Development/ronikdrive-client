import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import '../security/file_collaboration_encryption.dart';
import '../share/file_request_metadata_envelope.dart';
import '../shared/user_facing_cloud_error.dart';
import '../support/support_report_privacy.dart';

class SecureDriveException implements Exception {
  const SecureDriveException(this.message);

  final String message;

  @override
  String toString() => 'SecureDriveException: $message';
}

class CreatedFileRequest {
  const CreatedFileRequest({
    required this.token,
    required this.expiresAt,
    required this.maxFileBytes,
    required this.maxUploads,
  });

  final String token;
  final DateTime expiresAt;
  final int maxFileBytes;
  final int maxUploads;
}

class RewindResult {
  const RewindResult({required this.restoredCount, required this.truncated});

  final int restoredCount;
  final bool truncated;
}

class SecureDriveService {
  SecureDriveService({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _firestore = firestore,
       _functions = functions;

  factory SecureDriveService.forApp({
    required FirebaseApp app,
    required FirebaseFirestore firestore,
  }) {
    return SecureDriveService(
      firestore: firestore,
      functions: FirebaseFunctions.instanceFor(
        app: app,
        region: 'europe-west1',
      ),
    );
  }

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Future<void> moveFileToTrash(String fileId) async {
    await _call('moveFileToTrash', <String, Object?>{
      'fileId': SecureFeatureValidation.documentId(fileId),
    });
  }

  Future<void> restoreFile(String fileId) async {
    await _call('restoreFile', <String, Object?>{
      'fileId': SecureFeatureValidation.documentId(fileId),
    });
  }

  Future<void> recordFileAccess({required String fileId}) async {
    await _call('recordFileAccess', <String, Object?>{
      'fileId': SecureFeatureValidation.documentId(fileId),
    });
  }

  Future<void> setFileHotStoragePolicy({
    required String fileId,
    required String action,
    DateTime? hotUntil,
  }) async {
    const allowedActions = <String>{
      'automatic',
      'always_fast',
      'keep_fast_until',
      'archive_now',
    };
    if (!allowedActions.contains(action)) {
      throw const SecureDriveException('The storage speed choice is invalid.');
    }
    if (action == 'keep_fast_until' && hotUntil == null) {
      throw const SecureDriveException(
        'Choose how long to keep the file fast.',
      );
    }
    await _call('setFileHotStoragePolicy', <String, Object?>{
      'fileId': SecureFeatureValidation.documentId(fileId),
      'action': action,
      if (hotUntil != null) 'hotUntil': hotUntil.toUtc().toIso8601String(),
    });
  }

  Future<RewindResult> rewindFiles(DateTime since) async {
    final result = await _call('rewindFiles', <String, Object?>{
      'since': since.toUtc().toIso8601String(),
    });
    return RewindResult(
      restoredCount: _intValue(result['restoredCount']),
      truncated: result['truncated'] == true,
    );
  }

  Future<CreatedFileRequest> createFileRequest({
    required String encryptedTitleBase64,
    required String encryptedKeyBase64,
    required int expiryDays,
    required int maxFileBytes,
    required int maxUploads,
  }) async {
    final result = await _call(
      'createFileRequest',
      FileRequestMetadataEnvelope.protectedCreatePayload(
        encryptedTitleBase64: encryptedTitleBase64,
        encryptedKeyBase64: encryptedKeyBase64,
        expiryDays: expiryDays,
        maxFileBytes: maxFileBytes,
        maxUploads: maxUploads,
      ),
    );
    final token = result['token']?.toString().trim() ?? '';
    final expiresAt = DateTime.tryParse(result['expiresAt']?.toString() ?? '');
    if (token.isEmpty || expiresAt == null) {
      throw const SecureDriveException(
        'The server returned an incomplete file request.',
      );
    }
    return CreatedFileRequest(
      token: token,
      expiresAt: expiresAt,
      maxFileBytes: _intValue(result['maxFileBytes']),
      maxUploads: _intValue(result['maxUploads']),
    );
  }

  Future<void> revokeFileRequest(String token) async {
    final safeToken = SecureFeatureValidation.token(token);
    final reference = _firestore.collection('file_requests').doc(safeToken);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw StateError('The file request is unavailable.');
      }
      final privacyVersion = _intValue(data['requestPrivacyVersion']);
      transaction.update(reference, {
        'revoked': true,
        if (privacyVersion >= 2) 'createdAt': FieldValue.delete(),
        'revokedAt': FieldValue.delete(),
        'updatedAt': FieldValue.delete(),
        'lastUploadAt': FieldValue.delete(),
      });
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchFileRequests(String uid) {
    return _firestore
        .collection('file_requests')
        .where('uid', isEqualTo: uid)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRequestUploads(String uid) {
    return _firestore
        .collection('file_request_uploads')
        .where('uid', isEqualTo: uid)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchComments(String fileId) {
    final safeFileId = SecureFeatureValidation.documentId(fileId);
    return _firestore
        .collection('file_comments')
        .where('fileId', isEqualTo: safeFileId)
        .orderBy('createdAt')
        .snapshots();
  }

  String newFileCommentId() => _firestore.collection('file_comments').doc().id;

  Future<void> saveEncryptedComment({
    required String fileId,
    required String commentId,
    required String encryptedPayload,
    List<String> mentions = const <String>[],
  }) async {
    final normalizedMentions = mentions
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(25)
        .toList(growable: false);
    await _call(
      'saveEncryptedFileComment',
      <String, Object?>{
        'fileId': SecureFeatureValidation.documentId(fileId),
        'commentId': SecureFeatureValidation.documentId(commentId),
        'encryptionFormat': fileCollaborationEncryptionFormat,
        'encryptedPayload': SecureFeatureValidation.collaborationPayload(
          encryptedPayload,
        ),
        'mentions': normalizedMentions,
      },
      operation: UserFacingCloudOperation.collaboration,
    );
  }

  Future<void> setEncryptedReview({
    required String fileId,
    required String status,
    required String encryptedPayload,
    bool migrationOnly = false,
    String? legacyFingerprint,
  }) async {
    const allowed = <String>{'pending', 'approved', 'changes_requested'};
    if (!allowed.contains(status)) {
      throw const SecureDriveException('The review status is invalid.');
    }
    final normalizedLegacyFingerprint = legacyFingerprint?.trim().toLowerCase();
    if ((migrationOnly &&
            (normalizedLegacyFingerprint == null ||
                !RegExp(
                  r'^[a-f0-9]{64}$',
                ).hasMatch(normalizedLegacyFingerprint))) ||
        (!migrationOnly && normalizedLegacyFingerprint != null)) {
      throw const SecureDriveException(
        'The legacy review fingerprint is invalid.',
      );
    }
    await _call('setEncryptedFileReview', <String, Object?>{
      'fileId': SecureFeatureValidation.documentId(fileId),
      'status': status,
      'encryptionFormat': fileCollaborationEncryptionFormat,
      'encryptedPayload': SecureFeatureValidation.collaborationPayload(
        encryptedPayload,
      ),
      if (migrationOnly) 'migrationOnly': true,
      if (migrationOnly) 'legacyFingerprint': normalizedLegacyFingerprint!,
    }, operation: UserFacingCloudOperation.collaboration);
  }

  Future<SupportReportReceipt> submitSupportReport({
    required String title,
    required String description,
    required String stepsToReproduce,
    required String platform,
    required String buildMode,
    SupportReportCategory category = SupportReportCategory.issue,
  }) async {
    final payload = SupportReportPayload.prepare(
      category: category,
      title: title,
      description: description,
      stepsToReproduce: stepsToReproduce,
      platform: platform,
      buildMode: buildMode,
    );
    final result = await _call(
      'submitSupportReport',
      payload.toCallablePayload(),
    );
    return SupportReportReceipt.fromCallableResult(result);
  }

  /// Records a new conflict without overwriting an existing user decision.
  ///
  /// Returns a previously selected resolution, or `null` while the conflict
  /// still needs the user's attention. Reusing a deterministic conflict id
  /// makes retries idempotent and prevents a background scan from reopening a
  /// decision that the user already made.
  Future<String?> recordSyncConflict({
    required String uid,
    required String conflictId,
    required String backupPathHash,
    required String localPathHash,
    required String localIntegrityTag,
    required String remoteIntegrityTag,
    required String encryptedFileLabel,
  }) async {
    final safeId = SecureFeatureValidation.documentId(conflictId);
    final normalizedLabel = encryptedFileLabel.trim();
    final boundedLabel = normalizedLabel.length > 512
        ? normalizedLabel.substring(0, 512)
        : normalizedLabel;
    if (!boundedLabel.startsWith('enc--')) {
      throw const SecureDriveException(
        'The sync conflict label must be encrypted.',
      );
    }
    final normalizedLocalIntegrityTag = localIntegrityTag.trim();
    final normalizedRemoteIntegrityTag = remoteIntegrityTag.trim();
    if (!normalizedLocalIntegrityTag.startsWith('cit--') ||
        !normalizedRemoteIntegrityTag.startsWith('cit--')) {
      throw const SecureDriveException(
        'Sync conflict integrity values must be keyed tags.',
      );
    }
    final safeUid = SecureFeatureValidation.documentId(uid);
    final reference = _firestore.collection('sync_conflicts').doc(safeId);
    return _firestore.runTransaction<String?>((transaction) async {
      final existing = await transaction.get(reference);
      if (existing.exists) {
        final data = existing.data() ?? const <String, dynamic>{};
        if (data['uid'] != safeUid) {
          throw const SecureDriveException(
            'The sync conflict belongs to another account.',
          );
        }
        if (data['status'] == 'resolved') {
          final resolution = data['resolution']?.toString();
          const allowed = <String>{
            'keep_local',
            'keep_remote',
            'keep_both',
            'dismissed',
          };
          return allowed.contains(resolution) ? resolution : null;
        }
        return null;
      }
      transaction.set(reference, {
        'uid': safeUid,
        'conflictId': safeId,
        'backupPathHash': backupPathHash,
        'localPathHash': localPathHash,
        'localIntegrityTag': normalizedLocalIntegrityTag,
        'remoteIntegrityTag': normalizedRemoteIntegrityTag,
        'integrityTagVersion': 'hmac-sha256-v1',
        'encryptedFileLabel': boundedLabel,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOpenSyncConflicts(
    String uid,
  ) {
    return _firestore
        .collection('sync_conflicts')
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> resolveSyncConflict({
    required String conflictId,
    required String resolution,
  }) async {
    const allowed = <String>{
      'keep_local',
      'keep_remote',
      'keep_both',
      'dismissed',
    };
    if (!allowed.contains(resolution)) {
      throw const SecureDriveException('The conflict resolution is invalid.');
    }
    await _firestore
        .collection('sync_conflicts')
        .doc(SecureFeatureValidation.documentId(conflictId))
        .update({
          'status': 'resolved',
          'resolution': resolution,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> updateSharePolicy({
    required String token,
    required int maxDownloads,
    required bool notifyOnAccess,
  }) async {
    await _firestore
        .collection('shared_links')
        .doc(SecureFeatureValidation.token(token))
        .update({
          'maxDownloads': maxDownloads.clamp(1, 1000),
          'notifyOnAccess': notifyOnAccess,
          // New UI resolves the encrypted source filename locally. Editing a
          // policy also removes the plaintext label written by older clients.
          'linkLabel': FieldValue.delete(),
          'createdAt': FieldValue.delete(),
          'revokedAt': FieldValue.delete(),
          'updatedAt': FieldValue.delete(),
          'lastAccessAt': FieldValue.delete(),
          'firstAccessNotifiedAt': FieldValue.delete(),
        });
  }

  Future<Map<String, dynamic>> _call(
    String functionName,
    Map<String, Object?> data, {
    UserFacingCloudOperation operation = UserFacingCloudOperation.secureStorage,
  }) async {
    try {
      final result = await _functions
          .httpsCallable(functionName)
          .call<Object?>(data)
          .timeout(const Duration(seconds: 30));
      final value = result.data;
      if (value is Map) {
        return value.map((key, value) => MapEntry(key.toString(), value));
      }
      return const <String, dynamic>{};
    } on FirebaseFunctionsException catch (error) {
      throw SecureDriveException(
        userFacingCloudErrorMessage(operation: operation, code: error.code),
      );
    } on SecureDriveException {
      rethrow;
    } catch (_) {
      throw SecureDriveException(
        userFacingCloudErrorMessage(operation: operation),
      );
    }
  }

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class SecureFeatureValidation {
  const SecureFeatureValidation._();

  static String documentId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 2048 ||
        normalized.contains('/')) {
      throw const SecureDriveException('The document identifier is invalid.');
    }
    return normalized;
  }

  static String token(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalized)) {
      throw const SecureDriveException('The secure link token is invalid.');
    }
    return normalized;
  }

  static String requestTitle(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 160) {
      throw const SecureDriveException(
        'Request titles must contain 1 to 160 characters.',
      );
    }
    return normalized;
  }

  static String personName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 160) {
      throw const SecureDriveException('The display name is invalid.');
    }
    return normalized;
  }

  static String comment(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 4000) {
      throw const SecureDriveException(
        'Comments must contain 1 to 4000 characters.',
      );
    }
    return normalized;
  }

  static String collaborationPayload(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > fileCollaborationMaxEncryptedPayloadChars ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalized)) {
      throw const SecureDriveException(
        'The protected collaboration payload is invalid.',
      );
    }
    return normalized;
  }

  static List<String> mentionsFromComment(String body) {
    final matches = RegExp(
      r'(?<![A-Za-z0-9._%+-])@([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})',
    ).allMatches(body);
    return matches
        .map((match) => match.group(1)!.toLowerCase())
        .toSet()
        .take(25)
        .toList(growable: false);
  }

  static String encodeRequestKey(List<int> bytes) => base64Url.encode(bytes);
}
