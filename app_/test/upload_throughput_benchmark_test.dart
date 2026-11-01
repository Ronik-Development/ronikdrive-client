// Opt-in local benchmark. Uses synthetic bytes and loopback HTTP only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_storage/src/storage/upload_cipher_native.dart';
import 'package:cloud_storage/src/storage/upload_coordinator.dart';
import 'package:cloud_storage/src/storage/upload_source_snapshot.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _enabled = bool.fromEnvironment('RUN_UPLOAD_BENCHMARK');
const _sizes = String.fromEnvironment('BENCH_MIB', defaultValue: '10,100,1024');
const _repetitions = int.fromEnvironment('BENCH_REPETITIONS', defaultValue: 1);
const _uplinkMbps = int.fromEnvironment('BENCH_UPLINK_MBPS', defaultValue: 0);
const _smallFiles = int.fromEnvironment('BENCH_SMALL_FILES', defaultValue: 0);
final _block = Uint8List.fromList(
  List.generate(64 * 1024, (i) => (i * 17 + i ~/ 251) % 256),
);

Stream<List<int>> _source(int length) async* {
  for (var offset = 0; offset < length; offset += _block.length) {
    yield Uint8List.sublistView(_block, 0, min(_block.length, length - offset));
  }
}

void main() {
  test(
    'actual coordinator local throughput (not a Wasabi/network benchmark)',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = http.Client();
      var received = 0;
      var puts = 0;
      final networkClock = Stopwatch()..start();
      var scheduledNetworkMicros = 0;
      final serverErrors = <Object>[];
      server.listen((request) async {
        try {
          await for (final chunk in request) {
            if (_uplinkMbps > 0) {
              // One aggregate rate limit across every concurrent request, not a
              // separate allowance per part. No latency/loss is simulated.
              scheduledNetworkMicros =
                  max(
                    scheduledNetworkMicros,
                    networkClock.elapsedMicroseconds,
                  ) +
                  (chunk.length * 8 / _uplinkMbps).ceil();
              final delay =
                  scheduledNetworkMicros - networkClock.elapsedMicroseconds;
              if (delay > 0) {
                await Future<void>.delayed(Duration(microseconds: delay));
              }
            }
            received += chunk.length;
          }
          puts++;
          request.response.headers.set('etag', 'synthetic-$puts');
          request.response.statusCode = 200;
          await request.response.close();
        } catch (error) {
          serverErrors.add(error);
        }
      });
      final key = SecretKey(List.filled(32, 7));
      final algorithm = AesCtr.with256bits(macAlgorithm: Hmac.sha256());
      final api = UploadSessionApi(
        tokenProvider: () async => 'synthetic',
        client: MockClient((request) async {
          final operation = request.url.pathSegments.last;
          return http.Response(
            jsonEncode(switch (operation) {
              'start' => {'sessionId': 'synthetic-session'},
              'status' => {'status': 'uploading', 'parts': []},
              'urls' => {
                'parts': [
                  {'url': 'http://127.0.0.1:${server.port}/part'},
                ],
              },
              _ => {'ok': true},
            }),
            200,
          );
        }),
      );
      Future<Map<String, Object>> measure(int bytes, int repetition) async {
        final coordinator = UploadCoordinator(
          scheduler: UploadScheduler(mobile: false),
        );
        final initialRss = ProcessInfo.currentRss;
        var peakRss = initialRss;
        var peakBuffers = 0;
        var lastTick = 0;
        var maximumTickGap = 0;
        final watch = Stopwatch()..start();
        final sampler = Timer.periodic(const Duration(milliseconds: 10), (_) {
          peakRss = max(peakRss, ProcessInfo.currentRss);
          peakBuffers = max(peakBuffers, coordinator.scheduler.bufferedBytes);
          final tick = watch.elapsedMicroseconds;
          maximumTickGap = max(maximumTickGap, tick - lastTick);
          lastTick = tick;
        });
        final beforeBytes = received;
        final beforePuts = puts;
        var firstPutMicros = 0;
        try {
          final source = await UploadSourceSnapshot.capture(_source(bytes));
          final preparationMicros = watch.elapsedMicroseconds;
          await coordinator.upload(
            objectKey: 'synthetic-object',
            length: bytes + 48,
            ciphertext: encryptUploadStream(
              source.verify(_source(bytes)),
              key,
              algorithm.newNonce(),
            ),
            api: api,
            put: (url, data) async {
              if (firstPutMicros == 0) {
                firstPutMicros = watch.elapsedMicroseconds;
              }
              final response = await client.put(url, body: data);
              if (response.statusCode != 200) {
                throw StateError('Loopback rejected transfer');
              }
            },
          );
          final seconds = watch.elapsedMicroseconds / 1000000;
          final transferSeconds =
              (watch.elapsedMicroseconds - preparationMicros) / 1000000;
          expect(received - beforeBytes, bytes + 48);
          expect(serverErrors, isEmpty);
          return {
            'benchmark': 'actual-coordinator-loopback',
            'runtime': 'flutter-test-JIT',
            'simulatedAggregateUplinkMbps': _uplinkMbps,
            'repetition': repetition,
            'plaintextBytes': bytes,
            'preparationSeconds': preparationMicros / 1000000,
            'transferSeconds': transferSeconds,
            'totalSeconds': seconds,
            'endToEndMiBps': bytes / 1048576 / seconds,
            'transferMiBps': bytes / 1048576 / transferSeconds,
            'equivalentMbps': bytes * 8 / 1000000 / seconds,
            'timeToFirstPutSeconds': firstPutMicros / 1000000,
            'httpPuts': puts - beforePuts,
            'initialProcessRssMiB': initialRss / 1048576,
            'sampledPeakProcessRssMiB': peakRss / 1048576,
            'sampledPeakSchedulerBufferMiB': peakBuffers / 1048576,
            'maximum10msTimerGapMs': maximumTickGap / 1000,
            'journalEnabled': false,
            'realBackend': false,
            'diskSource': false,
          };
        } finally {
          sampler.cancel();
          coordinator.dispose();
        }
      }

      try {
        // Warm the exact path; the one MiB run is not a reported result.
        await measure(1048576, 0);
        for (
          var repetition = 1;
          repetition <= _repetitions && _smallFiles > 0;
          repetition++
        ) {
          final clock = Stopwatch()..start();
          for (var file = 0; file < _smallFiles; file++) {
            await measure(64 * 1024, repetition);
          }
          stdout.writeln(
            'BENCHMARK_RESULT ${jsonEncode({'benchmark': 'small-file-batch-loopback', 'files': _smallFiles, 'bytesPerFile': 64 * 1024, 'repetition': repetition, 'seconds': clock.elapsedMicroseconds / 1000000, 'realBackend': false, 'diskSource': false})}',
          );
        }
        for (final size
            in _sizes
                .split(',')
                .where((value) => value.isNotEmpty)
                .map(int.parse)) {
          for (var repetition = 1; repetition <= _repetitions; repetition++) {
            // At 1024 MiB, leave 48 bytes for the existing encryption envelope.
            final bytes = size * 1048576 - (size == 1024 ? 48 : 0);
            stdout.writeln(
              'BENCHMARK_START ${jsonEncode({'mib': size, 'repetition': repetition})}',
            );
            stdout.writeln(
              'BENCHMARK_RESULT ${jsonEncode(await measure(bytes, repetition))}',
            );
          }
        }
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
