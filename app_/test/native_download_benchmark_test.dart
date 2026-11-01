// Opt in: flutter test --dart-define=RUN_NATIVE_DOWNLOAD_BENCHMARK=true test/native_download_benchmark_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/privacy/native_download_pipeline.dart';
import 'package:cloud_storage/src/privacy/temporary_plaintext_lease.dart';

void main() {
  test(
    'synthetic native bounded-memory benchmark',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ronik-synthetic-benchmark-',
      );
      final manager = TemporaryPlaintextLeaseManager(
        rootDirectoryProvider: () async => Directory('${root.path}/leases'),
      );
      final block = Uint8List.fromList(List.generate(65536, (i) => i % 251));
      final algorithm = AesCtr.with256bits(macAlgorithm: Hmac.sha256()),
          key = SecretKey(List.generate(32, (i) => i)),
          nonce = List.filled(16, 2);
      Stream<List<int>> plain(int size) async* {
        for (var remaining = size; remaining > 0; remaining -= block.length) {
          yield remaining >= block.length
              ? block
              : Uint8List.sublistView(block, 0, remaining);
        }
      }

      try {
        for (final size in [
          10 * 1024 * 1024,
          100 * 1024 * 1024,
          1023 * 1024 * 1024,
        ]) {
          final expected = await hash.sha256.bind(plain(size)).first;
          for (var repetition = 0; repetition < 5; repetition++) {
            final fixture = await manager.create(extension: '.bin'),
                mac = Completer<Mac>();
            Stream<List<int>> encrypted() async* {
              yield nonce;
              yield* algorithm.encryptStream(
                plain(size),
                secretKey: key,
                nonce: nonce,
                onMac: mac.complete,
              );
              yield (await mac.future).bytes;
            }

            final preparation = Stopwatch()..start();
            await fixture.writeStream(encrypted());
            preparation.stop();
            final output = await manager.create(),
                baseline = ProcessInfo.currentRss;
            var peak = baseline;
            final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
              if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
            });
            final elapsed = Stopwatch()..start();
            try {
              expect(
                await output.writeStream(
                  decryptFramedDownload(
                    fixture.file.openRead(),
                    key: key,
                    manager: manager,
                    checkAccess: () {},
                  ),
                ),
                size,
              );
              elapsed.stop();
              expect(
                await hash.sha256.bind(output.file.openRead()).first,
                expected,
              );
              // ignore: avoid_print
              print(
                jsonEncode({
                  'nativeBytes': size,
                  'repetition': repetition + 1,
                  'preparationMs': preparation.elapsedMilliseconds,
                  'downloadMs': elapsed.elapsedMilliseconds,
                  'baselineRssBytes': baseline,
                  'peakRssBytes': peak,
                  'environment':
                      'Windows Flutter test JIT, synthetic local disk, not network',
                }),
              );
            } finally {
              timer.cancel();
              await output.release();
              await fixture.release();
            }
          }
        }
      } finally {
        await manager.cleanupActive(minimumAge: Duration.zero);
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RUN_NATIVE_DOWNLOAD_BENCHMARK'),
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
