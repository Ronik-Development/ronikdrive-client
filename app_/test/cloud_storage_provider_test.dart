import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_storage/src/storage/cloud_storage_provider.dart';
import 'package:cloud_storage/src/storage/multipart_upload_checkpoint_sink.dart';
import 'package:cloud_storage/src/storage/wasabi_storage_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCloudStorageProvider implements CloudStorageProvider {
  FakeCloudStorageProvider({this.configured = true});

  final bool configured;
  final Map<String, Uint8List> storedObjects = <String, Uint8List>{};
  final List<String> cleanedUpUploads = <String>[];

  @override
  bool get isConfigured => configured;

  @override
  Future<WasabiUploadResult> upload({
    required String objectKey,
    required Stream<List<int>> stream,
    required int length,
    String? contentType,
    SecretKey? encryptionKey,
    bool payloadAlreadyEncrypted = false,
    String? transferId,
    String? sourceFingerprint,
    MultipartUploadCheckpointSink? checkpointSink,
  }) async {
    if (encryptionKey != null && payloadAlreadyEncrypted) {
      throw const WasabiStorageException(
        'Upload protection is ambiguous. Provide an encryption key or mark '
        'the payload as already encrypted, but not both.',
      );
    }
    if (encryptionKey == null && !payloadAlreadyEncrypted) {
      throw const WasabiStorageException(
        'Upload blocked because client-side encryption was not provided.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    storedObjects[objectKey] = Uint8List.fromList(bytes);
    return WasabiUploadResult(
      objectKey: objectKey,
      bucket: 'fake-bucket',
      eTag: 'fake-etag',
    );
  }

  @override
  Future<WasabiUploadResult> uploadBytes({
    required String objectKey,
    required Uint8List bytes,
    String? contentType,
    SecretKey? encryptionKey,
    bool payloadAlreadyEncrypted = false,
    bool allowRetry = true,
  }) async {
    return upload(
      objectKey: objectKey,
      stream: Stream.value(bytes),
      length: bytes.length,
      contentType: contentType,
      encryptionKey: encryptionKey,
      payloadAlreadyEncrypted: payloadAlreadyEncrypted,
    );
  }

  @override
  Future<Stream<List<int>>> download({
    required String objectKey,
    SecretKey? encryptionKey,
    bool preferProxy = false,
    int? maxPlaintextBytes,
  }) async {
    final data = storedObjects[objectKey];
    if (data == null) {
      throw const WasabiStorageException('Object not found.');
    }
    return Stream.value(data);
  }

  @override
  Future<Uint8List> downloadObject({
    required String objectKey,
    SecretKey? encryptionKey,
    bool allowRetry = true,
  }) async {
    final data = storedObjects[objectKey];
    if (data == null) {
      throw const WasabiStorageException('Object not found.');
    }
    return data;
  }

  @override
  Future<Uint8List?> getObject(String objectKey) async {
    return storedObjects[objectKey];
  }

  @override
  Future<void> deleteObject(String objectKey) async {
    storedObjects.remove(objectKey);
  }

  @override
  Future<void> cleanupInterruptedMultipartUpload({
    required String objectKey,
    required String uploadId,
  }) async {
    cleanedUpUploads.add('$objectKey:$uploadId');
    storedObjects.remove(objectKey);
  }
}

void main() {
  group('CloudStorageProvider abstraction & implementation', () {
    test('WasabiStorageService satisfies CloudStorageProvider interface', () {
      final wasabi = WasabiStorageService.unconfigured();
      expect(wasabi, isA<CloudStorageProvider>());
      expect(wasabi.isConfigured, isFalse);
    });

    test('WasabiStorageService.serverManaged validates parameters', () {
      expect(
        () => WasabiStorageService.serverManaged(
          bucket: '',
          idTokenProvider: () async => 'test-token',
          authorizedObjectUri: Uri.parse('https://example.com/auth'),
          serverManagedPrefixes: ['users/123'],
        ),
        throwsA(isA<WasabiConfigurationException>()),
      );

      expect(
        () => WasabiStorageService.serverManaged(
          bucket: 'valid-bucket',
          idTokenProvider: () async => 'test-token',
          authorizedObjectUri: Uri.parse('https://example.com/auth'),
          serverManagedPrefixes: [],
        ),
        throwsA(isA<WasabiConfigurationException>()),
      );

      final service = WasabiStorageService.serverManaged(
        bucket: 'valid-bucket',
        idTokenProvider: () async => 'test-token',
        authorizedObjectUri: Uri.parse('https://example.com/auth'),
        serverManagedPrefixes: ['users/123'],
      );
      expect(service, isA<CloudStorageProvider>());
      expect(service.isConfigured, isTrue);
      expect(service.bucket, equals('valid-bucket'));
    });

    test(
      'FakeCloudStorageProvider upholds encryption safety invariant',
      () async {
        final provider = FakeCloudStorageProvider();
        expect(provider.isConfigured, isTrue);

        final unencryptedBytes = Uint8List.fromList([1, 2, 3, 4]);

        // Upload without encryption or alreadyEncrypted flag must fail
        expect(
          () => provider.uploadBytes(
            objectKey: 'test.bin',
            bytes: unencryptedBytes,
          ),
          throwsA(isA<WasabiStorageException>()),
        );

        // Upload marked as already encrypted succeeds
        final result = await provider.uploadBytes(
          objectKey: 'test.bin',
          bytes: unencryptedBytes,
          payloadAlreadyEncrypted: true,
        );
        expect(result.objectKey, equals('test.bin'));
        expect(result.bucket, equals('fake-bucket'));
        expect(result.eTag, equals('fake-etag'));

        final retrieved = await provider.getObject('test.bin');
        expect(retrieved, equals(unencryptedBytes));

        await provider.deleteObject('test.bin');
        final afterDelete = await provider.getObject('test.bin');
        expect(afterDelete, isNull);
      },
    );

    test('Rejects ambiguous encryption configuration', () async {
      final provider = FakeCloudStorageProvider();
      final algorithm = AesGcm.with256bits();
      final key = await algorithm.newSecretKey();

      expect(
        () => provider.uploadBytes(
          objectKey: 'test.bin',
          bytes: Uint8List.fromList([1, 2, 3]),
          encryptionKey: key,
          payloadAlreadyEncrypted: true,
        ),
        throwsA(isA<WasabiStorageException>()),
      );
    });

    test('Streams chunked upload accurately', () async {
      final provider = FakeCloudStorageProvider();
      final chunk1 = [10, 20, 30];
      final chunk2 = [40, 50, 60];
      final chunk3 = [70, 80, 90];

      final streamController = StreamController<List<int>>();
      final uploadFuture = provider.upload(
        objectKey: 'chunked.bin',
        stream: streamController.stream,
        length: 9,
        payloadAlreadyEncrypted: true,
      );

      streamController.add(chunk1);
      streamController.add(chunk2);
      streamController.add(chunk3);
      await streamController.close();

      final uploadResult = await uploadFuture;
      expect(uploadResult.objectKey, equals('chunked.bin'));

      final downloaded = await provider.downloadObject(
        objectKey: 'chunked.bin',
      );
      expect(
        downloaded,
        equals(Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80, 90])),
      );
    });

    test('Download operations handle missing objects gracefully', () async {
      final provider = FakeCloudStorageProvider();

      expect(
        () => provider.download(objectKey: 'missing.bin'),
        throwsA(isA<WasabiStorageException>()),
      );

      expect(
        () => provider.downloadObject(objectKey: 'missing.bin'),
        throwsA(isA<WasabiStorageException>()),
      );

      final nonExistent = await provider.getObject('missing.bin');
      expect(nonExistent, isNull);
    });

    test(
      'Cleans up interrupted multipart upload and tracks identifiers',
      () async {
        final provider = FakeCloudStorageProvider();
        await provider.uploadBytes(
          objectKey: 'in_progress.bin',
          bytes: Uint8List.fromList([1, 2]),
          payloadAlreadyEncrypted: true,
        );

        expect(await provider.getObject('in_progress.bin'), isNotNull);

        await provider.cleanupInterruptedMultipartUpload(
          objectKey: 'in_progress.bin',
          uploadId: 'upload-session-42',
        );

        expect(await provider.getObject('in_progress.bin'), isNull);
        expect(
          provider.cleanedUpUploads,
          contains('in_progress.bin:upload-session-42'),
        );
      },
    );

    test('Storage exception hierarchy formats messages clearly', () {
      const configException = WasabiConfigurationException('Missing key');
      expect(
        configException.toString(),
        equals('WasabiConfigurationException: Missing key'),
      );

      const storageException = WasabiStorageException('Network timeout');
      expect(
        storageException.toString(),
        equals('WasabiStorageException: Network timeout'),
      );

      const downloadLimit = WasabiDownloadLimitException();
      expect(downloadLimit, isA<WasabiStorageException>());
      expect(
        downloadLimit.toString(),
        contains('Storage returned more file data than expected'),
      );
    });
  });
}
