abstract class MultipartUploadCheckpointSink {
  Future<void> multipartCreated({
    required String transferId,
    required String objectKey,
    required String uploadId,
  });

  Future<void> multipartPartCompleted({
    required String transferId,
    required int partNumber,
    required String eTag,
    required int uploadedBytes,
  });

  Future<void> multipartCompleted({required String transferId});

  Future<void> multipartAborted({required String transferId});

  Future<void> multipartCleanupRequired({
    required String transferId,
    required Object error,
  });
}

abstract class ResumableUploadCheckpointSink {
  Map<String, dynamic>? uploadCheckpoint(String transferId);
  Future<void> saveUploadCheckpoint(String transferId, Map<String, dynamic> checkpoint);
}
