// Release/AOT benchmark of the production native cipher, no Flutter or network.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:cloud_storage/src/storage/upload_cipher_native.dart';

final block = Uint8List.fromList(
  List.generate(64 * 1024, (i) => (i * 17 + i ~/ 251) % 256),
);
Stream<List<int>> source(int length) async* {
  for (var offset = 0; offset < length; offset += block.length) {
    yield Uint8List.sublistView(block, 0, min(block.length, length - offset));
  }
}

Future<void> main(List<String> arguments) async {
  final sizes = arguments.isEmpty
      ? [10, 100, 1024]
      : arguments.map(int.parse).toList();
  final key = SecretKey(List.filled(32, 7));
  final algorithm = AesCtr.with256bits(macAlgorithm: Hmac.sha256());
  Future<void> measure(int mib, {bool warmup = false}) async {
    final bytes = mib * 1048576 - (mib == 1024 ? 48 : 0);
    final clock = Stopwatch()..start();
    var received = 0;
    await for (final chunk in encryptUploadStream(
      source(bytes),
      key,
      algorithm.newNonce(),
    )) {
      received += chunk.length;
    }
    if (received != bytes + 48) throw StateError('Unexpected cipher length');
    final seconds = clock.elapsedMicroseconds / 1000000;
    if (!warmup) {
      stdout.writeln(
        'BENCHMARK_RESULT ${jsonEncode({'benchmark': 'production-native-cipher-only', 'runtime': 'dart-AOT', 'plaintextBytes': bytes, 'seconds': seconds, 'MiBps': bytes / 1048576 / seconds, 'Mbps': bytes * 8 / 1000000 / seconds, 'processPeakRssMiB': ProcessInfo.maxRss / 1048576, 'processors': Platform.numberOfProcessors})}',
      );
    }
  }

  await measure(1, warmup: true);
  for (final size in sizes) {
    await measure(size);
  }
}
