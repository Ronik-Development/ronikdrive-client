// Opt in: flutter test --dart-define=RUN_NATIVE_ZIP_BENCHMARK=true test/native_zip_benchmark_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/privacy/native_download_pipeline.dart';
import 'package:cloud_storage/src/privacy/temporary_plaintext_lease.dart';

void main() {
  test(
    'native ZIP memory and independently extracted-byte equality',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ronik-synthetic-zip-benchmark-',
      );
      final manager = TemporaryPlaintextLeaseManager(
        rootDirectoryProvider: () async => Directory('${root.path}/leases'),
      );
      final random = Random(73),
          block = Uint8List.fromList(
            List.generate(65536, (_) => random.nextInt(256)),
          );
      Stream<List<int>> plain(int size) async* {
        for (var left = size; left > 0; left -= block.length) {
          yield left >= block.length
              ? block
              : Uint8List.sublistView(block, 0, left);
        }
      }

      try {
        for (final size in [
          10 * 1024 * 1024,
          100 * 1024 * 1024,
          1023 * 1024 * 1024,
        ]) {
          final input = await manager.create();
          await input.writeStream(plain(size));
          final expected = (await hash.sha256.bind(input.file.openRead()).first)
              .toString();
          try {
            for (var repetition = 0; repetition < 5; repetition++) {
              final output = await manager.create(extension: '.zip'),
                  baseline = ProcessInfo.currentRss;
              var peak = baseline, ticks = 0;
              final timer = Timer.periodic(const Duration(milliseconds: 10), (
                _,
              ) {
                ticks++;
                if (ProcessInfo.currentRss > peak) {
                  peak = ProcessInfo.currentRss;
                }
              });
              final watch = Stopwatch()..start();
              NativeStreamingZip? zip;
              try {
                zip = await NativeStreamingZip.create(output);
                await zip.add(input, 'synthetic.bin');
                await zip.close();
                await output.seal();
                watch.stop();
                timer.cancel();
                final check = await Process.run('python', [
                  '-c',
                  r'import hashlib,json,sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); h=hashlib.sha256(); n=0; f=z.open("synthetic.bin"); exec("while True:\n b=f.read(1048576)\n if not b: break\n h.update(b); n+=len(b)"); print(json.dumps({"bytes":n,"digest":h.hexdigest(),"names":z.namelist()}))',
                  output.file.path,
                ]);
                expect(check.exitCode, 0);
                final evidence = jsonDecode(check.stdout as String) as Map;
                expect(evidence['bytes'], size);
                expect(evidence['digest'], expected);
                expect(evidence['names'], ['synthetic.bin']);
                // ignore: avoid_print
                print(
                  jsonEncode({
                    'nativeZipBytes': size,
                    'repetition': repetition + 1,
                    'zipMs': watch.elapsedMilliseconds,
                    'zipBytes': await output.file.length(),
                    'baselineRssBytes': baseline,
                    'peakRssBytes': peak,
                    'uiTimerTicks': ticks,
                    'environment':
                        'Windows Flutter test JIT, synthetic incompressible-block fixture, Python extraction',
                  }),
                );
              } finally {
                timer.cancel();
                zip?.cancel();
                await output.release();
              }
            }
          } finally {
            await input.release();
          }
        }
      } finally {
        await manager.cleanupActive(minimumAge: Duration.zero);
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RUN_NATIVE_ZIP_BENCHMARK'),
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
