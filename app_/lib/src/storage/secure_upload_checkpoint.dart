import 'dart:convert';

import 'multipart_upload_checkpoint_sink.dart';
import 'upload_coordinator.dart';

/// Child sessions share one encrypted journal record and one parent nonce.
/// Serialize child updates so parallel shards cannot overwrite one another.
class SecureUploadCheckpoint
    implements MultipartUploadCheckpointSink, ResumableUploadCheckpointSink {
  SecureUploadCheckpoint._(this.sink, this.parentId, this.nonce);
  final ResumableUploadCheckpointSink sink;
  final String parentId;
  final List<int> nonce;
  Future<void> _writes = Future.value();

  static Future<SecureUploadCheckpoint> open({
    required ResumableUploadCheckpointSink sink,
    required String parentId,
    required String objectKey,
    required String fingerprint,
    required List<int> Function() newNonce,
  }) async {
    final saved = sink.uploadCheckpoint(parentId);
    if (saved != null &&
        (saved['secureSharded'] != true ||
            saved['objectKey'] != objectKey ||
            saved['sourceFingerprint'] != fingerprint)) {
      throw const UploadFailure('source_changed');
    }
    final nonce = saved == null
        ? newNonce()
        : base64Decode(saved['nonce'] as String);
    if (saved == null) {
      await sink.saveUploadCheckpoint(parentId, {
        'version': 1,
        'secureSharded': true,
        'objectKey': objectKey,
        'sourceFingerprint': fingerprint,
        'nonce': base64Encode(nonce),
        'shards': <String, dynamic>{},
      });
    }
    return SecureUploadCheckpoint._(sink, parentId, List.unmodifiable(nonce));
  }

  @override
  Map<String, dynamic>? uploadCheckpoint(String transferId) {
    final shards = sink.uploadCheckpoint(parentId)?['shards'] as Map?;
    final value = shards?[transferId];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  @override
  Future<void> saveUploadCheckpoint(
    String transferId,
    Map<String, dynamic> checkpoint,
  ) {
    final next = _writes.then((_) async {
      final parent = Map<String, dynamic>.from(
        sink.uploadCheckpoint(parentId)!,
      );
      final shards = Map<String, dynamic>.from(parent['shards'] as Map);
      shards[transferId] = {
        ...checkpoint,
        'sourceFingerprint': parent['sourceFingerprint'],
      };
      parent['shards'] = shards;
      await sink.saveUploadCheckpoint(parentId, parent);
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  // This adapter is passed only to the session-based upload path. Legacy MPU
  // callbacks must never erase or reinterpret the parent's secure checkpoint.
  @override
  Future<void> multipartCreated({
    required String transferId,
    required String objectKey,
    required String uploadId,
  }) async => throw StateError('Legacy multipart checkpoint');
  @override
  Future<void> multipartPartCompleted({
    required String transferId,
    required int partNumber,
    required String eTag,
    required int uploadedBytes,
  }) async => throw StateError('Legacy multipart checkpoint');
  @override
  Future<void> multipartCompleted({required String transferId}) async =>
      throw StateError('Legacy multipart checkpoint');
  @override
  Future<void> multipartAborted({required String transferId}) async =>
      throw StateError('Legacy multipart checkpoint');
  @override
  Future<void> multipartCleanupRequired({
    required String transferId,
    required Object error,
  }) async => throw StateError('Legacy multipart checkpoint');
}
