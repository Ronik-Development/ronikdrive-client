import 'dart:typed_data';
import '../privacy/memory_preview.dart';

class SecureShardReadException implements Exception {
  const SecureShardReadException({required this.shardIndex, this.cause});

  final int shardIndex;
  final Object? cause;

  @override
  String toString() =>
      'Secure shard $shardIndex could not be read${cause == null ? '' : ': $cause'}.';
}

Future<Uint8List> assembleSecureShards({
  required int shardCount,
  required Future<Stream<List<int>>> Function(int shardIndex) openShard,
  Future<Uint8List> Function(Uint8List ciphertext)? decryptWholeFile,
  int? maxBufferedBytes,
}) async {
  if (shardCount <= 0) {
    throw const FormatException(
      'A secure file must contain at least one shard.',
    );
  }
  if (maxBufferedBytes != null && maxBufferedBytes <= 0) {
    throw const FormatException('The secure file buffer limit is invalid.');
  }
  final builder = SensitiveByteBuffer(maximumBytes: maxBufferedBytes);
  try {
    for (var index = 0; index < shardCount; index += 1) {
      try {
        final stream = await openShard(index);
        await for (final chunk in stream) {
          if (maxBufferedBytes != null &&
              builder.length + chunk.length > maxBufferedBytes) {
            throw const FormatException(
              'The secure file exceeded its local buffer limit.',
            );
          }
          builder.add(chunk);
        }
      } catch (error) {
        throw SecureShardReadException(shardIndex: index, cause: error);
      }
    }
    final ciphertext = builder.takeBytes();
    if (decryptWholeFile == null) return ciphertext;
    try {
      final plaintext = await decryptWholeFile(ciphertext);
      // A custom decoder can return its input; transfer ownership in that case.
      if (identical(plaintext, ciphertext) ||
          plaintext.buffer == ciphertext.buffer) {
        return Uint8List.fromList(plaintext);
      }
      return plaintext;
    } finally {
      ciphertext.fillRange(0, ciphertext.length, 0);
    }
  } finally {
    builder.clear();
  }
}
