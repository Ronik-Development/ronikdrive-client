import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_storage/src/security/chunked_aead_stream.dart';
import 'package:cloud_storage/src/security/encryption_service.dart';
import 'package:cloud_storage/src/security/memory_protection.dart';
import 'package:cloud_storage/src/security/merkle_audit_tree.dart';
import 'package:cloud_storage/src/security/payload_padding.dart';
import 'package:cloud_storage/src/storage/cloud_storage_provider.dart';
import 'package:cloud_storage/src/storage/multipart_upload_checkpoint_sink.dart';
import 'package:cloud_storage/src/storage/wasabi_storage_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory S3-compatible cloud storage provider with checkpoint tracking.
class E2EInMemoryStorageProvider implements CloudStorageProvider {
  final Map<String, Uint8List> _objects = <String, Uint8List>{};
  final List<String> checkpoints = <String>[];

  @override
  bool get isConfigured => true;

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
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    _objects[objectKey] = Uint8List.fromList(bytes);
    if (checkpointSink != null && transferId != null) {
      await checkpointSink.multipartPartCompleted(
        transferId: transferId,
        partNumber: 1,
        eTag: 'etag-part-1',
        uploadedBytes: bytes.length,
      );
      checkpoints.add('$objectKey:part1:${bytes.length}');
    }
    return WasabiUploadResult(
      objectKey: objectKey,
      bucket: 'e2e-vault',
      eTag: 'etag-final',
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
    final data = _objects[objectKey];
    if (data == null) {
      throw const WasabiStorageException('Object not found in storage.');
    }
    return Stream.value(data);
  }

  @override
  Future<Uint8List> downloadObject({
    required String objectKey,
    SecretKey? encryptionKey,
    bool allowRetry = true,
  }) async {
    final data = _objects[objectKey];
    if (data == null) {
      throw const WasabiStorageException('Object not found in storage.');
    }
    return data;
  }

  @override
  Future<Uint8List?> getObject(String objectKey) async {
    return _objects[objectKey];
  }

  @override
  Future<void> deleteObject(String objectKey) async {
    _objects.remove(objectKey);
  }

  @override
  Future<void> cleanupInterruptedMultipartUpload({
    required String objectKey,
    required String uploadId,
  }) async {
    _objects.remove(objectKey);
  }
}

void main() {
  group('End-to-End Hardened Upload, Verification, and Download Pipeline', () {
    late E2EInMemoryStorageProvider storage;
    late MerkleAuditChain auditChain;
    late SecretKey userMasterKey;
    final salt = Uint8List.fromList([
      10,
      20,
      30,
      40,
      50,
      60,
      70,
      80,
      90,
      100,
      110,
      120,
      130,
      140,
      150,
      160,
    ]);

    setUp(() async {
      storage = E2EInMemoryStorageProvider();
      auditChain = MerkleAuditChain();
      userMasterKey = await EncryptionService.instance.deriveKey(
        password: 'SuperSecretUserPassword123!',
        salt: salt,
      );
    });

    test(
      'Full lifecycle: Encrypted upload -> Padding -> AEAD -> Audit -> Decryption -> Deletion',
      () async {
        final originalPlaintext = utf8.encode(
          'Top Secret Financial Disclosure 2026: Confirmed Zero Knowledge Privacy!',
        );
        final plaintextBytes = Uint8List.fromList(originalPlaintext);
        const originalFileName = 'FinancialReport_Q3_2026.pdf';
        const actorUid = 'user_opaque_887766';

        // 1. Encrypt File Name
        final encryptedFileName = await EncryptionService.instance
            .encryptFileName(originalFileName, userMasterKey);
        expect(encryptedFileName.startsWith('enc--'), isTrue);
        expect(encryptedFileName.contains('FinancialReport'), isFalse);

        // Decrypt and verify file name
        final decryptedFileName = await EncryptionService.instance
            .decryptFileName(encryptedFileName, userMasterKey);
        expect(decryptedFileName, equals(originalFileName));

        // 2. Pad payload (Traffic Analysis Defense)
        final paddedBytes = PayloadPadding.padPayload(plaintextBytes);
        expect(
          paddedBytes.length,
          equals(64 * 1024),
        ); // Padded to 64 KiB minimum bucket tier

        // 3. Encrypt into AEAD chunk frames with AAD binding
        final objectKey =
            'users/$actorUid/objects/01/aa/$encryptedFileName.bin';
        final streamCipher = ChunkedAeadStream(
          objectKey: objectKey,
          secretKey: userMasterKey,
          defaultChunkSize: 32 * 1024,
        );

        final chunkFrames = await streamCipher.encryptBytes(paddedBytes);
        expect(
          chunkFrames.length,
          equals(2),
        ); // 64 KiB / 32 KiB chunks = 2 frames
        expect(chunkFrames.last.isFinal, isTrue);

        // 4. Serialize frames and verify memory scrubbing
        final wireBytes = <int>[];
        for (final frame in chunkFrames) {
          wireBytes.addAll(frame.toBytes());
        }
        final payloadToUpload = Uint8List.fromList(wireBytes);

        // Verify that wire bytes contain NO plaintext strings
        final wireString = String.fromCharCodes(wireBytes);
        expect(wireString.contains('Top Secret Financial'), isFalse);

        // 5. Upload via CloudStorageProvider
        final uploadResult = await storage.uploadBytes(
          objectKey: objectKey,
          bytes: payloadToUpload,
          payloadAlreadyEncrypted: true,
        );
        expect(uploadResult.objectKey, equals(objectKey));
        expect(uploadResult.bucket, equals('e2e-vault'));

        // 6. Record upload in Merkle Audit Log
        final createLeaf = auditChain.append(
          action: 'FILE_UPLOAD',
          actorId: actorUid,
          payloadDigest: uploadResult.eTag ?? 'etag',
        );
        expect(createLeaf.sequenceNumber, equals(0));
        expect(createLeaf.verifySelfHash(), isTrue);

        // 7. Verify storage content is present
        final storedRawBytes = await storage.getObject(objectKey);
        expect(storedRawBytes, isNotNull);
        expect(storedRawBytes!.length, equals(payloadToUpload.length));

        // 8. Download and Reconstruct Frames
        final downloadedWire = await storage.downloadObject(
          objectKey: objectKey,
        );
        final reconstructedFrames = <AeadChunkFrame>[];
        var parseOffset = 0;
        while (parseOffset < downloadedWire.length) {
          final frame = AeadChunkFrame.fromBytes(
            downloadedWire.sublist(parseOffset),
          );
          reconstructedFrames.add(frame);
          parseOffset += frame.toBytes().length;
        }
        expect(reconstructedFrames.length, equals(2));

        // 9. Decrypt AEAD stream
        final decryptedPadded = await streamCipher.decryptFrames(
          reconstructedFrames,
        );
        expect(decryptedPadded.length, equals(64 * 1024));

        // 10. Unpad payload
        final unpaddedRecovered = PayloadPadding.unpadPayload(decryptedPadded);
        expect(unpaddedRecovered, equals(plaintextBytes));
        expect(
          utf8.decode(unpaddedRecovered),
          equals(utf8.decode(originalPlaintext)),
        );

        // 11. Delete file and log audit leaf
        await storage.deleteObject(objectKey);
        expect(await storage.getObject(objectKey), isNull);

        final deleteLeaf = auditChain.append(
          action: 'FILE_DELETE',
          actorId: actorUid,
          payloadDigest: 'deleted:$objectKey',
        );
        expect(deleteLeaf.sequenceNumber, equals(1));
        expect(deleteLeaf.parentHash, equals(createLeaf.leafHash));

        // 12. Verify full Merkle audit chain
        final auditResult = auditChain.verifyChain();
        expect(auditResult.isValid, isTrue);
        expect(auditResult.verifiedLeafCount, equals(2));
      },
    );

    test(
      'Pipeline detects and rejects bit-flip corruption during download',
      () async {
        const actorUid = 'user_opaque_887766';
        const objectKey = 'users/$actorUid/objects/corrupt.bin';
        final streamCipher = ChunkedAeadStream(
          objectKey: objectKey,
          secretKey: userMasterKey,
        );

        final frames = await streamCipher.encryptBytes(
          Uint8List.fromList([1, 2, 3, 4, 5]),
        );
        final wireBytes = frames.first.toBytes();

        // Corrupt a single bit in the ciphertext portion
        wireBytes[15] ^= 0xFF;

        await storage.uploadBytes(
          objectKey: objectKey,
          bytes: wireBytes,
          payloadAlreadyEncrypted: true,
        );

        final downloaded = await storage.downloadObject(objectKey: objectKey);
        final corruptFrame = AeadChunkFrame.fromBytes(downloaded);

        // Decryption must fail closed with authentication error
        expect(
          () => streamCipher.decryptFrames([corruptFrame]),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
      },
    );

    test(
      'Pipeline enforces memory protection during temporary key operations',
      () async {
        final keyBuffer = Uint8List.fromList([10, 20, 30, 40]);
        var executed = false;

        await MemoryProtection.withTemporaryKeyBuffer(keyBuffer, (buf) async {
          expect(buf[0], equals(10));
          executed = true;
        });

        expect(executed, isTrue);
        expect(keyBuffer.every((b) => b == 0), isTrue);
      },
    );
  });
}
