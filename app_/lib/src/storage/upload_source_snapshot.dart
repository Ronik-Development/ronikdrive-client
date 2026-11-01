import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'upload_coordinator.dart';
import 'upload_block_hashes.dart';

/// Only fingerprints are retained. Every bounded plaintext block is verified
/// again before encryption, including when a source changes between reads.
class UploadSourceSnapshot {
  UploadSourceSnapshot._(this.length, this._blocks, this.fingerprint);
  static const blockBytes = 256 * 1024;
  final int length;
  final List<String> _blocks;
  final String fingerprint;

  static Future<UploadSourceSnapshot> capture(Stream<List<int>> source) async {
    final hashes = <String>[];
    var length = 0;
    await for (final (block, digest) in hashUploadBlocks(_bounded(source))) {
      hashes.add(digest);
      length += block.length;
    }
    // Domain-separated digest of fixed-boundary block hashes and total length.
    final fingerprint = sha256.convert([
      ...'upload-source-v1:$length:'.codeUnits,
      ...hashes.join(':').codeUnits,
    ]).toString();
    return UploadSourceSnapshot._(length, hashes, fingerprint);
  }

  Stream<List<int>> verify(Stream<List<int>> source) async* {
    var index = 0;
    var bytes = 0;
    await for (final (block, digest) in hashUploadBlocks(_bounded(source))) {
      if (index >= _blocks.length || digest != _blocks[index]) {
        throw const UploadFailure('source_changed');
      }
      index++;
      bytes += block.length;
      yield block;
    }
    if (index != _blocks.length || bytes != length) {
      throw const UploadFailure('source_changed');
    }
  }

  static Stream<Uint8List> _bounded(Stream<List<int>> source) async* {
    var block = Uint8List(blockBytes);
    var filled = 0;
    await for (final chunk in source) {
      var offset = 0;
      while (offset < chunk.length) {
        final take = (chunk.length - offset).clamp(0, blockBytes - filled);
        block.setRange(filled, filled + take, chunk, offset);
        filled += take;
        offset += take;
        if (filled == blockBytes) {
          yield block;
          block = Uint8List(blockBytes);
          filled = 0;
        }
      }
    }
    if (filled > 0) yield Uint8List.sublistView(block, 0, filled);
  }
}
