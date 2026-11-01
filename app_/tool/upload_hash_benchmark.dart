// Synthetic CPU-only comparison; no customer files, credentials or network.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cloud_storage/src/storage/upload_block_hashes_native.dart';

String digest(Uint8List bytes) => sha256.convert(bytes).toString();
Stream<(Uint8List, String)> baseline(Stream<Uint8List> blocks) async* {
  await for (final block in blocks) {
    yield (block, await Isolate.run(() => digest(block)));
  }
}

Future<void> main() async {
  final block = Uint8List.fromList(List.generate(256 * 1024, (i) => i % 251));
  final expected = digest(block);
  for (var repetition = 0; repetition < 4; repetition++) {
    final entries = [
      ('per-block-worker', baseline),
      ('reused-worker', hashUploadBlocks),
    ];
    for (final (name, hash) in repetition.isEven ? entries : entries.reversed) {
      final count = repetition == 0 ? 4 : 400;
      final clock = Stopwatch()..start();
      var received = 0;
      await for (final (_, result) in hash(
        Stream.fromIterable(Iterable.generate(count, (_) => block)),
      )) {
        if (result != expected) throw StateError('Digest mismatch');
        received++;
      }
      if (received != count) throw StateError('Missing blocks');
      if (repetition != 0) {
        stdout.writeln(
          jsonEncode({
            'method': name,
            'repetition': repetition,
            'MiB': count / 4,
            'seconds': clock.elapsedMicroseconds / 1000000,
          }),
        );
      }
    }
  }
}
