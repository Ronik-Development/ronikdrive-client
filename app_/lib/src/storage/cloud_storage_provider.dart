import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'multipart_upload_checkpoint_sink.dart';
import 'wasabi_storage_service.dart';

/// Abstract contract for S3-compatible cloud storage providers
/// (Wasabi, Cloudflare R2, AWS S3, Backblaze B2, and local edge/cache nodes).
///
/// Implementations must enforce client-side encryption boundaries before transmission.
abstract class CloudStorageProvider {
  /// Whether the storage provider is configured and ready for read/write operations.
  bool get isConfigured;

  /// Uploads a stream to the object store.
  ///
  /// Either [encryptionKey] must be provided for client-side encryption or
  /// [payloadAlreadyEncrypted] must be explicitly set to true.
  Future<WasabiUploadResult> upload({
    required String objectKey,
    required Stream<List<int>> stream,
    required int length,
    String? contentType,
    SecretKey? encryptionKey,
    bool payloadAlreadyEncrypted = false,
    String? transferId,
    MultipartUploadCheckpointSink? checkpointSink,
    String? sourceFingerprint,
  });

  /// Uploads in-memory bytes to the object store.
  Future<WasabiUploadResult> uploadBytes({
    required String objectKey,
    required Uint8List bytes,
    String? contentType,
    SecretKey? encryptionKey,
    bool payloadAlreadyEncrypted = false,
    bool allowRetry = true,
  });

  /// Streams object bytes from the storage backend, with optional range and proxy fallback.
  Future<Stream<List<int>>> download({
    required String objectKey,
    SecretKey? encryptionKey,
    bool preferProxy = false,
    int? maxPlaintextBytes,
  });

  /// Downloads and decrypts an entire object into memory.
  Future<Uint8List> downloadObject({
    required String objectKey,
    SecretKey? encryptionKey,
    bool allowRetry = true,
  });

  /// Fetches raw bytes for an object, returning `null` if the object does not exist.
  Future<Uint8List?> getObject(String objectKey);

  /// Deletes an object by its storage key.
  Future<void> deleteObject(String objectKey);

  /// Cleans up any interrupted multipart upload.
  Future<void> cleanupInterruptedMultipartUpload({
    required String objectKey,
    required String uploadId,
  });
}
