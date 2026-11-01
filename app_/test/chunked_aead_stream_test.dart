import 'dart:typed_data';

import 'package:cloud_storage/src/security/chunked_aead_stream.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChunkedAeadStream tests', () {
    late SecretKey secretKey;
    late SecretKey wrongKey;

    setUp(() async {
      final cipher = AesGcm.with256bits();
      secretKey = await cipher.newSecretKey();
      wrongKey = await cipher.newSecretKey();
    });

    test('Encrypts and decrypts single-chunk data cleanly', () async {
      final streamCipher = ChunkedAeadStream(
        objectKey: 'users/123/doc.pdf',
        secretKey: secretKey,
        defaultChunkSize: 1024,
      );

      final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final frames = await streamCipher.encryptBytes(payload);

      expect(frames.length, equals(1));
      expect(frames.first.isFinal, isTrue);
      expect(frames.first.chunkIndex, equals(0));

      final decrypted = await streamCipher.decryptFrames(frames);
      expect(decrypted, equals(payload));
    });

    test('Handles empty payload with single final frame', () async {
      final streamCipher = ChunkedAeadStream(
        objectKey: 'empty.bin',
        secretKey: secretKey,
      );

      final frames = await streamCipher.encryptBytes(Uint8List(0));
      expect(frames.length, equals(1));
      expect(frames.first.isFinal, isTrue);

      final decrypted = await streamCipher.decryptFrames(frames);
      expect(decrypted.length, equals(0));
    });

    test('Encrypts and decrypts multi-chunk streams in order', () async {
      final streamCipher = ChunkedAeadStream(
        objectKey: 'videos/stream.mp4',
        secretKey: secretKey,
        defaultChunkSize: 10, // Small chunk size to force multiple chunks
      );

      final payload = Uint8List.fromList(List.generate(25, (i) => i));
      final frames = await streamCipher.encryptBytes(payload);

      expect(frames.length, equals(3)); // 10 + 10 + 5 bytes
      expect(frames[0].isFinal, isFalse);
      expect(frames[1].isFinal, isFalse);
      expect(frames[2].isFinal, isTrue);

      final decrypted = await streamCipher.decryptFrames(frames);
      expect(decrypted, equals(payload));
    });

    test('Detects and rejects stream truncation attacks', () async {
      final streamCipher = ChunkedAeadStream(
        objectKey: 'large.iso',
        secretKey: secretKey,
        defaultChunkSize: 10,
      );

      final payload = Uint8List.fromList(List.generate(30, (i) => i));
      final frames = await streamCipher.encryptBytes(payload);

      // Drop the final frame (simulating network cut or truncated upload)
      final truncatedFrames = frames.sublist(0, 2);

      expect(
        () => streamCipher.decryptFrames(truncatedFrames),
        throwsA(isA<FormatException>()),
      );
    });

    test('Detects out-of-order chunk swaps or replays', () async {
      final streamCipher = ChunkedAeadStream(
        objectKey: 'data.bin',
        secretKey: secretKey,
        defaultChunkSize: 10,
      );

      final payload = Uint8List.fromList(List.generate(30, (i) => i));
      final frames = await streamCipher.encryptBytes(payload);

      // Swap chunk 0 and chunk 1
      final swappedFrames = [frames[1], frames[0], frames[2]];

      expect(
        () => streamCipher.decryptFrames(swappedFrames),
        throwsA(isA<FormatException>()),
      );
    });

    test('Rejects decryption with incorrect secret key', () async {
      final streamCipher = ChunkedAeadStream(
        objectKey: 'secret.txt',
        secretKey: secretKey,
      );

      final wrongCipher = ChunkedAeadStream(
        objectKey: 'secret.txt',
        secretKey: wrongKey,
      );

      final payload = Uint8List.fromList([10, 20, 30]);
      final frames = await streamCipher.encryptBytes(payload);

      expect(
        () => wrongCipher.decryptFrames(frames),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('AeadChunkFrame binary serialization round-trip', () {
      const frame = AeadChunkFrame(
        chunkIndex: 42,
        isFinal: true,
        nonce: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        cipherText: [100, 101, 102],
        macBytes: [200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215],
      );

      final bytes = frame.toBytes();
      final recovered = AeadChunkFrame.fromBytes(bytes);

      expect(recovered.chunkIndex, equals(42));
      expect(recovered.isFinal, isTrue);
      expect(recovered.nonce, equals(frame.nonce));
      expect(recovered.cipherText, equals(frame.cipherText));
      expect(recovered.macBytes, equals(frame.macBytes));
    });
  });
}
