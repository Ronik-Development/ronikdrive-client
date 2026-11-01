import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Represents a single authenticated encrypted chunk frame in the stream.
class AeadChunkFrame {
  const AeadChunkFrame({
    required this.chunkIndex,
    required this.isFinal,
    required this.nonce,
    required this.cipherText,
    required this.macBytes,
  });

  final int chunkIndex;
  final bool isFinal;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> macBytes;

  /// Serializes the frame into wire format:
  /// [4 bytes: chunkIndex] + [1 byte: isFinal] + [1 byte: nonceLength] +
  /// [nonce bytes] + [4 bytes: cipherTextLength] + [cipherText bytes] +
  /// [1 byte: macLength] + [mac bytes]
  Uint8List toBytes() {
    final totalSize = 4 + 1 + 1 + nonce.length + 4 + cipherText.length + 1 + macBytes.length;
    final buffer = Uint8List(totalSize);
    final byteData = ByteData.sublistView(buffer);

    var offset = 0;
    byteData.setUint32(offset, chunkIndex, Endian.big);
    offset += 4;

    buffer[offset] = isFinal ? 1 : 0;
    offset += 1;

    buffer[offset] = nonce.length;
    offset += 1;
    buffer.setRange(offset, offset + nonce.length, nonce);
    offset += nonce.length;

    byteData.setUint32(offset, cipherText.length, Endian.big);
    offset += 4;
    buffer.setRange(offset, offset + cipherText.length, cipherText);
    offset += cipherText.length;

    buffer[offset] = macBytes.length;
    offset += 1;
    buffer.setRange(offset, offset + macBytes.length, macBytes);

    return buffer;
  }

  /// Deserializes an [AeadChunkFrame] from wire format.
  static AeadChunkFrame fromBytes(Uint8List bytes) {
    if (bytes.length < 11) {
      throw const FormatException('Corrupted chunk frame: buffer is too short.');
    }

    final byteData = ByteData.sublistView(bytes);
    var offset = 0;

    final chunkIndex = byteData.getUint32(offset, Endian.big);
    offset += 4;

    final isFinal = bytes[offset] == 1;
    offset += 1;

    final nonceLength = bytes[offset];
    offset += 1;
    if (offset + nonceLength > bytes.length) {
      throw const FormatException('Corrupted chunk frame: invalid nonce length.');
    }
    final nonce = bytes.sublist(offset, offset + nonceLength);
    offset += nonceLength;

    if (offset + 4 > bytes.length) {
      throw const FormatException('Corrupted chunk frame: missing ciphertext header.');
    }
    final cipherTextLength = byteData.getUint32(offset, Endian.big);
    offset += 4;

    if (offset + cipherTextLength > bytes.length) {
      throw const FormatException('Corrupted chunk frame: truncated ciphertext.');
    }
    final cipherText = bytes.sublist(offset, offset + cipherTextLength);
    offset += cipherTextLength;

    if (offset + 1 > bytes.length) {
      throw const FormatException('Corrupted chunk frame: missing mac header.');
    }
    final macLength = bytes[offset];
    offset += 1;

    if (offset + macLength > bytes.length) {
      throw const FormatException('Corrupted chunk frame: truncated mac tag.');
    }
    final macBytes = bytes.sublist(offset, offset + macLength);

    return AeadChunkFrame(
      chunkIndex: chunkIndex,
      isFinal: isFinal,
      nonce: nonce,
      cipherText: cipherText,
      macBytes: macBytes,
    );
  }
}

/// Provides authenticated chunk-level AEAD stream encryption and decryption
/// to defend against stream truncation, out-of-order chunk replay, and bit flips.
class ChunkedAeadStream {
  ChunkedAeadStream({
    required this.objectKey,
    required this.secretKey,
    this.defaultChunkSize = 1024 * 1024, // 1 MiB default
  });

  final String objectKey;
  final SecretKey secretKey;
  final int defaultChunkSize;
  final AesGcm _cipher = AesGcm.with256bits();

  /// Computes deterministic Authenticated Associated Data (AAD) for a chunk.
  List<int> _buildAad({required int chunkIndex, required bool isFinal}) {
    final aadString = 'RonikCloud:AEAD:v1:$objectKey:$chunkIndex:${isFinal ? 1 : 0}';
    return utf8.encode(aadString);
  }

  /// Encrypts raw [plaintext] bytes into a list of [AeadChunkFrame]s.
  Future<List<AeadChunkFrame>> encryptBytes(Uint8List plaintext) async {
    final frames = <AeadChunkFrame>[];
    final totalLength = plaintext.length;

    if (totalLength == 0) {
      final aad = _buildAad(chunkIndex: 0, isFinal: true);
      final box = await _cipher.encrypt(
        <int>[],
        secretKey: secretKey,
        aad: aad,
      );
      frames.add(
        AeadChunkFrame(
          chunkIndex: 0,
          isFinal: true,
          nonce: box.nonce,
          cipherText: box.cipherText,
          macBytes: box.mac.bytes,
        ),
      );
      return frames;
    }

    var offset = 0;
    var index = 0;
    while (offset < totalLength) {
      final end = (offset + defaultChunkSize < totalLength)
          ? offset + defaultChunkSize
          : totalLength;
      final isFinal = end == totalLength;
      final chunkSlice = plaintext.sublist(offset, end);

      final aad = _buildAad(chunkIndex: index, isFinal: isFinal);
      final box = await _cipher.encrypt(
        chunkSlice,
        secretKey: secretKey,
        aad: aad,
      );

      frames.add(
        AeadChunkFrame(
          chunkIndex: index,
          isFinal: isFinal,
          nonce: box.nonce,
          cipherText: box.cipherText,
          macBytes: box.mac.bytes,
        ),
      );

      offset = end;
      index++;
    }

    return frames;
  }

  /// Decrypts a list of [AeadChunkFrame]s into the original plaintext bytes.
  ///
  /// Verifies index ordering, authenticity tags, and guarantees stream finality.
  Future<Uint8List> decryptFrames(List<AeadChunkFrame> frames) async {
    if (frames.isEmpty) {
      throw const FormatException('Cannot decrypt empty chunk list.');
    }

    final output = <int>[];
    var sawFinal = false;

    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];

      if (frame.chunkIndex != i) {
        throw FormatException(
          'Out-of-order chunk detected: expected index $i but got ${frame.chunkIndex}.',
        );
      }

      if (sawFinal) {
        throw const FormatException('Unexpected chunk frame received after final chunk.');
      }

      if (frame.isFinal) {
        sawFinal = true;
      }

      final aad = _buildAad(chunkIndex: frame.chunkIndex, isFinal: frame.isFinal);
      final box = SecretBox(
        frame.cipherText,
        nonce: frame.nonce,
        mac: Mac(frame.macBytes),
      );

      final decryptedChunk = await _cipher.decrypt(
        box,
        secretKey: secretKey,
        aad: aad,
      );

      output.addAll(decryptedChunk);
    }

    if (!sawFinal) {
      throw const FormatException(
        'Stream truncation detected: stream ended without a final chunk frame.',
      );
    }

    return Uint8List.fromList(output);
  }
}
