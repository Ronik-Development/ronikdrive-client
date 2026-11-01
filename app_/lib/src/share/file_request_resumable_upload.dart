import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import '../storage/transfer_journal.dart';
import '../storage/upload_coordinator.dart';
import '../storage/upload_source_snapshot.dart';
import '../storage/upload_cipher.dart';
import '../storage/upload_part_transport.dart';
import 'file_request_metadata_envelope.dart';
import 'public_transfer_failure.dart';

class FileRequestSessionApi extends UploadSessionApi {
  FileRequestSessionApi({
    required super.client,
    required super.baseUri,
    required this.requestToken,
  }) : super(tokenProvider: () async => null);
  final String requestToken;
  Map<String, dynamic>? authorization;

  Future<Map<String, dynamic>> post(
    String operation,
    Map<String, dynamic> body, {
    int expectedStatus = 200,
  }) async {
    final response = await client
        .post(
          baseUri.resolve(
            'file-requests/${Uri.encodeComponent(requestToken)}/$operation',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            ...body,
            'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          }),
        )
        .timeout(const Duration(seconds: 90));
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      data = {};
    }
    if (data['code'] == 'recipient_full') {
      throw const PublicTransferException(
        PublicTransferFailureKind.recipientStorageFull,
      );
    }
    if (response.statusCode == 410 && data['code'] == 'upload_expired') {
      throw const UploadFailure('upload_expired');
    }
    if (response.statusCode != expectedStatus) {
      throw PublicTransferException(
        PublicTransferFailureKind.httpStatus,
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, dynamic> body,
  ) async {
    if (operation == 'start') return authorization!;
    return post('uploads/$operation', {
      ...body,
      'uploadId': authorization!['uploadId'],
    });
  }
}

Future<void> uploadResumableFileRequest({
  required FileRequestSessionApi api,
  required UploadCoordinator coordinator,
  required TransferJournal journal,
  required SecretKey key,
  required String name,
  required String contentType,
  required int length,
  required Stream<List<int>> Function() openRead,
  bool Function()? isActive,
}) async {
  void requireActive() {
    if (isActive?.call() == false) throw const UploadFailure('canceled');
  }

  requireActive();
  if (!journal.storageAvailable) throw const UploadFailure('unavailable');
  final snapshot = await UploadSourceSnapshot.capture(openRead());
  requireActive();
  if (snapshot.length != length) throw const UploadFailure('source_changed');
  var previous = journal.pendingEntries
      .where(
        (entry) =>
            entry.label == name &&
            entry.uploadCheckpoint?['sourceFingerprint'] ==
                snapshot.fingerprint,
      )
      .firstOrNull;
  if (previous?.canRetryMetadata == true) {
    final payload = Map<String, dynamic>.from(previous!.metadataPayload!)
      ..remove('objectKey');
    await api.post('complete', payload, expectedStatus: 201);
    await journal.complete(previous.id);
    return;
  }
  var id = previous?.id ?? coordinator.newId();
  Future<void> beginAttempt() async {
    // Persist the idempotency key before the first request: an uncertain
    // authorization response must not consume a second recipient slot.
    await journal.begin(
      id: id,
      kind: TransferJournalKind.upload,
      label: name,
      totalBytes: length,
    );
    await journal.saveUploadCheckpoint(id, {
      'version': 1,
      'sourceFingerprint': snapshot.fingerprint,
    });
  }

  Future<Map<String, dynamic>> authorize() => api.post('authorize', {
    'protocol': 'resumable-v1',
    'clientUploadId': id,
    'plainSize': length,
    'encryptedSize': length + 48,
  });
  if (previous == null) await beginAttempt();
  Map<String, dynamic> authorization;
  try {
    authorization = await authorize();
  } on UploadFailure catch (error) {
    // Only a definite server expiry permits a new identity and nonce. Network
    // errors and ambiguous conflicts must keep the original idempotency key.
    if (error.code != 'upload_expired' || previous == null) rethrow;
    await journal.cancel(id);
    requireActive();
    previous = null;
    id = coordinator.newId();
    await beginAttempt();
    authorization = await authorize();
  }
  if (authorization['objectKey'] is! String ||
      authorization['sessionId'] is! String ||
      authorization['uploadId'] is! String) {
    throw const PublicTransferException(
      PublicTransferFailureKind.authorizationIncomplete,
    );
  }
  api.authorization = authorization;
  if (isActive?.call() == false) {
    try {
      await api.call('abort', {'sessionId': authorization['sessionId']});
    } catch (_) {}
    await journal.cancel(id);
    throw const UploadFailure('canceled');
  }
  final objectKey = authorization['objectKey'] as String;
  if (previous?.objectKey != null && previous!.objectKey != objectKey) {
    throw const UploadFailure('source_changed');
  }
  if (previous?.objectKey == null) {
    await journal.begin(
      id: id,
      kind: TransferJournalKind.upload,
      label: name,
      objectKey: objectKey,
      totalBytes: length,
    );
  }
  final saved = journal.uploadCheckpoint(id);
  final nonce = saved?['nonce'] is String
      ? base64Decode(saved!['nonce'] as String)
      : AesCtr.with256bits(macAlgorithm: Hmac.sha256()).newNonce();
  await journal.saveUploadCheckpoint(id, {
    ...?saved,
    'version': 1,
    'nonce': base64Encode(nonce),
    'sourceFingerprint': snapshot.fingerprint,
    'objectKey': objectKey,
  });
  try {
    await coordinator.upload(
      objectKey: objectKey,
      length: length + 48,
      ciphertext: encryptUploadStream(snapshot.verify(openRead()), key, nonce),
      api: api,
      transferId: id,
      checkpointSink: journal,
      put: (_, _) async => throw StateError('Cancellable transport required'),
      putCancellable: (url, bytes, abort, headers) => putUploadPart(
        client: api.client,
        url: url,
        bytes: bytes,
        abortSignal: abort,
        headers: headers,
      ),
    );
    final metadata = await FileRequestMetadataEnvelope.sealUpload(
      fileName: name,
      contentType: contentType,
      key: key,
    );
    final payload = Map<String, dynamic>.from(
      FileRequestMetadataEnvelope.protectedCompletionPayload(
        uploadId: authorization['uploadId'] as String,
        encryptedMetadataBase64: metadata,
      ),
    );
    await journal.stageMetadataCommit(
      id,
      payload: {...payload, 'objectKey': objectKey},
    );
    await api.post('complete', payload, expectedStatus: 201);
    await journal.complete(id);
  } catch (error) {
    if (error is UploadFailure && error.code == 'canceled') {
      await journal.cancel(id);
    } else if (!journal.entries.any(
      (entry) => entry.id == id && entry.canRetryMetadata,
    )) {
      await journal.fail(id, error);
    }
    rethrow;
  }
}
