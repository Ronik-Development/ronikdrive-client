import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_storage/src/storage/cloud_storage_provider.dart';
import 'package:cloud_storage/src/storage/multipart_upload_checkpoint_sink.dart';
import 'package:cloud_storage/src/storage/wasabi_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FallbackResilientStorageClient {
  FallbackResilientStorageClient({
    required this.primary,
    required this.secondary,
  });

  final CloudStorageProvider primary;
  final CloudStorageProvider secondary;

  Future<Uint8List> resilientDownload({required String objectKey}) async {
    try {
      return await primary.downloadObject(objectKey: objectKey);
    } catch (_) {
      return await secondary.downloadObject(objectKey: objectKey);
    }
  }
}

class MemoryStorageProvider implements CloudStorageProvider {
  MemoryStorageProvider({this.configured = true, this.shouldFail = false});

  final bool configured;
  bool shouldFail;
  final Map<String, Uint8List> _storage = <String, Uint8List>{};

  @override
  bool get isConfigured => configured;

  @override
  Future<WasabiUploadResult> upload({
    required String objectKey,
    required Stream<List<int>> stream,
    required int length,
    String? contentType,
    dynamic encryptionKey,
    bool payloadAlreadyEncrypted = false,
    String? transferId,
    String? sourceFingerprint,
    MultipartUploadCheckpointSink? checkpointSink,
  }) async {
    if (shouldFail) {
      throw const WasabiStorageException('Storage backend unavailable.');
    }
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    _storage[objectKey] = Uint8List.fromList(bytes);
    return WasabiUploadResult(objectKey: objectKey, bucket: 'mem-bucket');
  }

  @override
  Future<WasabiUploadResult> uploadBytes({
    required String objectKey,
    required Uint8List bytes,
    String? contentType,
    dynamic encryptionKey,
    bool payloadAlreadyEncrypted = false,
    bool allowRetry = true,
  }) async {
    if (shouldFail) {
      throw const WasabiStorageException('Storage backend unavailable.');
    }
    _storage[objectKey] = bytes;
    return WasabiUploadResult(objectKey: objectKey, bucket: 'mem-bucket');
  }

  @override
  Future<Stream<List<int>>> download({
    required String objectKey,
    dynamic encryptionKey,
    bool preferProxy = false,
    int? maxPlaintextBytes,
  }) async {
    if (shouldFail) {
      throw const WasabiStorageException('Storage backend unavailable.');
    }
    final data = _storage[objectKey];
    if (data == null) {
      throw const WasabiStorageException('Not found.');
    }
    return Stream.value(data);
  }

  @override
  Future<Uint8List> downloadObject({
    required String objectKey,
    dynamic encryptionKey,
    bool allowRetry = true,
  }) async {
    if (shouldFail) {
      throw const WasabiStorageException('Storage backend unavailable.');
    }
    final data = _storage[objectKey];
    if (data == null) {
      throw const WasabiStorageException('Not found.');
    }
    return data;
  }

  @override
  Future<Uint8List?> getObject(String objectKey) async {
    if (shouldFail) {
      return null;
    }
    return _storage[objectKey];
  }

  @override
  Future<void> deleteObject(String objectKey) async {
    if (shouldFail) {
      throw const WasabiStorageException('Storage backend unavailable.');
    }
    _storage.remove(objectKey);
  }

  @override
  Future<void> cleanupInterruptedMultipartUpload({
    required String objectKey,
    required String uploadId,
  }) async {
    _storage.remove(objectKey);
  }
}

void main() {
  group('Multi-provider resilience and fallback integration', () {
    test('Fallback client recovers from primary provider failure', () async {
      final primary = MemoryStorageProvider(shouldFail: true);
      final secondary = MemoryStorageProvider();

      final payload = Uint8List.fromList([100, 101, 102]);
      await secondary.uploadBytes(
        objectKey: 'doc.bin',
        bytes: payload,
        payloadAlreadyEncrypted: true,
      );

      final client = FallbackResilientStorageClient(
        primary: primary,
        secondary: secondary,
      );

      final retrieved = await client.resilientDownload(objectKey: 'doc.bin');
      expect(retrieved, equals(payload));
    });

    test('Primary provider used when healthy', () async {
      final primary = MemoryStorageProvider();
      final secondary = MemoryStorageProvider();

      final primaryPayload = Uint8List.fromList([1, 2, 3]);
      final secondaryPayload = Uint8List.fromList([4, 5, 6]);

      await primary.uploadBytes(
        objectKey: 'doc.bin',
        bytes: primaryPayload,
        payloadAlreadyEncrypted: true,
      );
      await secondary.uploadBytes(
        objectKey: 'doc.bin',
        bytes: secondaryPayload,
        payloadAlreadyEncrypted: true,
      );

      final client = FallbackResilientStorageClient(
        primary: primary,
        secondary: secondary,
      );

      final retrieved = await client.resilientDownload(objectKey: 'doc.bin');
      expect(retrieved, equals(primaryPayload));
    });
  });
}
