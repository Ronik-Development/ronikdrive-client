import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_storage/src/storage/upload_coordinator.dart';
import 'package:cloud_storage/src/storage/upload_cipher.dart';
import 'package:cloud_storage/src/storage/upload_source_snapshot.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'cancel releases a stalled source and its reserved scheduler memory',
    () async {
      final coordinator = UploadCoordinator();
      final listening = Completer<void>();
      final source = StreamController<List<int>>(onListen: listening.complete);
      final calls = <String>[];
      final api = UploadSessionApi(
        tokenProvider: () async => 'token',
        client: MockClient((request) async {
          final op = request.url.pathSegments.last;
          calls.add(op);
          return http.Response(
            jsonEncode(
              op == 'start' ? {'sessionId': 'session'} : {'parts': []},
            ),
            200,
          );
        }),
      );
      final upload = coordinator.upload(
        objectKey: 'opaque',
        length: 1,
        ciphertext: source.stream,
        api: api,
        put: (_, _) async => fail('No bytes should be uploaded'),
      );
      final assertion = expectLater(
        upload,
        throwsA(isA<UploadFailure>().having((e) => e.code, 'code', 'canceled')),
      );
      await listening.future;
      coordinator.cancelAll();
      await assertion.timeout(const Duration(seconds: 2));
      expect(calls, contains('abort'));
      expect(calls, isNot(contains('complete')));
      expect(coordinator.scheduler.bufferedBytes, 0);
      expect(coordinator.scheduler.active, 0);
      await source.close();
    },
  );

  test(
    'account changes cancel old batches and remove their visible queue',
    () async {
      final coordinator = UploadCoordinator()..bindAccount('first');
      await coordinator.inBatch('old-batch', () async {
        coordinator.bindAccount('second');
        await expectLater(
          coordinator.upload(
            objectKey: 'opaque',
            length: 1,
            ciphertext: Stream.value([1]),
            api: UploadSessionApi(
              tokenProvider: () async => 'token',
              client: MockClient(
                (_) async => throw StateError('Must not send'),
              ),
            ),
            put: (_, _) async {},
          ),
          throwsA(
            isA<UploadFailure>().having((e) => e.code, 'code', 'canceled'),
          ),
        );
      });
      expect(coordinator.jobs, isEmpty);
    },
  );
  test(
    'cancel aborts an active part and cleans up without completing',
    () async {
      final calls = <String>[];
      final reachedPut = Completer<void>();
      final coordinator = UploadCoordinator();
      final api = UploadSessionApi(
        tokenProvider: () async => 'session',
        client: MockClient((request) async {
          final op = request.url.pathSegments.last;
          calls.add(op);
          return http.Response(
            jsonEncode(switch (op) {
              'start' => {'sessionId': 'session-id'},
              'status' => {'status': 'uploading', 'parts': []},
              'urls' => {
                'parts': [
                  {'url': 'https://storage.test/object'},
                ],
              },
              _ => {'ok': true},
            }),
            200,
          );
        }),
      );
      final upload = coordinator.upload(
        objectKey: 'opaque',
        length: 3,
        ciphertext: Stream.value([1, 2, 3]),
        api: api,
        put: (_, _) async => fail('Must use cancellable transport'),
        putCancellable: (_, _, abort, _) async {
          reachedPut.complete();
          await abort;
          throw const UploadFailure('canceled');
        },
      );
      final result = expectLater(
        upload,
        throwsA(
          isA<UploadFailure>().having(
            (error) => error.code,
            'code',
            'canceled',
          ),
        ),
      );
      await reachedPut.future;
      coordinator.cancelAll();
      await result.timeout(const Duration(seconds: 2));
      expect(calls, isNot(contains('complete')));
      expect(calls.last, 'abort');
      expect(coordinator.jobs.single.acknowledgedBytes, 0);
      expect(coordinator.scheduler.active, 0);
      expect(coordinator.scheduler.bufferedBytes, 0);
    },
  );

  test(
    'memory backpressure holds even when network concurrency grows',
    () async {
      final scheduler = UploadScheduler(mobile: true)..limit = 3;
      const charge = 16 * 1024 * 1024;
      await scheduler.acquire(bytes: charge);
      await scheduler.acquire(bytes: charge);
      var admitted = false;
      final third = scheduler.acquire(bytes: charge).then((_) {
        admitted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(admitted, false);
      expect(scheduler.bufferedBytes, scheduler.bufferLimit);
      scheduler.release(bytes: charge);
      await third;
      expect(scheduler.bufferedBytes, scheduler.bufferLimit);
      scheduler.release(bytes: charge);
      scheduler.release(bytes: charge);
      expect(scheduler.bufferedBytes, 0);
    },
  );

  test(
    'canceling a batch prevents its not-yet-started files from transferring',
    () async {
      final coordinator = UploadCoordinator();
      final api = UploadSessionApi(
        tokenProvider: () async => 'session',
        client: MockClient(
          (_) async => throw StateError('No authorization expected'),
        ),
      );
      await coordinator.inBatch('cancel-this-batch', () async {
        coordinator.cancelAll();
        await expectLater(
          coordinator.upload(
            objectKey: 'opaque',
            length: 1,
            ciphertext: Stream.value([1]),
            api: api,
            put: (_, _) async {},
          ),
          throwsA(
            isA<UploadFailure>().having(
              (error) => error.code,
              'code',
              'canceled',
            ),
          ),
        );
      });
    },
  );

  test(
    'source fingerprints ignore stream boundaries and reject mutation before yielding',
    () async {
      final snapshot = await UploadSourceSnapshot.capture(
        Stream.fromIterable([
          [1],
          [2, 3],
        ]),
      );
      final output = await snapshot
          .verify(Stream.value([1, 2, 3]))
          .expand((chunk) => chunk)
          .toList();
      expect(output, [1, 2, 3]);
      await expectLater(
        snapshot.verify(Stream.value([1, 9, 3])).first,
        throwsA(
          isA<UploadFailure>().having(
            (error) => error.code,
            'code',
            'source_changed',
          ),
        ),
      );
      await expectLater(
        snapshot.verify(const Stream.empty()).drain<void>(),
        throwsA(isA<UploadFailure>()),
      );
    },
  );

  test(
    'one scheduler bounds overlapping files and reduces slots on failures',
    () async {
      final scheduler = UploadScheduler(mobile: false);
      var active = 0;
      var peak = 0;
      await Future.wait(
        List.generate(20, (index) async {
          await scheduler.acquire();
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active--;
          scheduler.release(success: index % 3 != 0);
        }),
      );
      expect(peak, lessThanOrEqualTo(4));
      expect(scheduler.active, 0);
      scheduler.setRestricted(true);
      expect(scheduler.limit, 1);
    },
  );

  test('quota failures keep only typed numeric details', () async {
    final api = UploadSessionApi(
      tokenProvider: () async => 'session',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'quota_exceeded',
            'capacityBytes': 100,
            'usageBytes': 70,
            'reservedBytes': 20,
            'selectedBytes': 15,
            'shortfallBytes': 5,
            'detail': 'private provider details',
          }),
          409,
        ),
      ),
    );
    await expectLater(
      api.call('prepare', {}),
      throwsA(
        isA<UploadCapacityDecision>()
            .having((value) => value.remainingBytes, 'remaining', 10)
            .having(
              (value) => value.toString(),
              'safe message',
              isNot(contains('provider')),
            ),
      ),
    );
  });

  test(
    'worker encryption preserves existing nonce/ciphertext/HMAC format',
    () async {
      final key = SecretKey(List.generate(32, (index) => index));
      final algorithm = AesCtr.with256bits(macAlgorithm: Hmac.sha256());
      final nonce = algorithm.newNonce();
      final source = List.generate(131073, (index) => index % 251);
      final expected = await algorithm.encrypt(
        source,
        secretKey: key,
        nonce: nonce,
      );
      final builder = BytesBuilder(copy: false);
      await for (final chunk in encryptUploadStream(
        Stream.fromIterable([source.sublist(0, 65000), source.sublist(65000)]),
        key,
        nonce,
      )) {
        builder.add(chunk);
      }
      expect(builder.takeBytes(), [
        ...nonce,
        ...expected.cipherText,
        ...expected.mac.bytes,
      ]);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'network progress is acknowledged only after PUT, then completion',
    () async {
      final calls = <String>[];
      final releasePut = Completer<void>();
      final reachedPut = Completer<void>();
      final coordinator = UploadCoordinator(
        scheduler: UploadScheduler(mobile: true),
      );
      final api = UploadSessionApi(
        tokenProvider: () async => 'session',
        client: MockClient((request) async {
          final operation = request.url.pathSegments.last;
          calls.add(operation);
          return http.Response(
            jsonEncode(switch (operation) {
              'start' => {'sessionId': 'session-id'},
              'status' => {'status': 'uploading', 'parts': []},
              'urls' => {
                'parts': [
                  {'url': 'https://storage.test/object'},
                ],
              },
              _ => {'ok': true},
            }),
            200,
          );
        }),
      );
      final upload = coordinator.upload(
        objectKey: 'opaque',
        length: 3,
        ciphertext: Stream.value([1, 2, 3]),
        api: api,
        put: (_, bytes) async {
          expect(bytes, [1, 2, 3]);
          reachedPut.complete();
          await releasePut.future;
        },
      );
      await reachedPut.future;
      expect(coordinator.jobs.single.acknowledgedBytes, 0);
      expect(calls, isNot(contains('complete')));
      releasePut.complete();
      await upload;
      expect(coordinator.jobs.single.acknowledgedBytes, 3);
      expect(coordinator.jobs.single.state, UploadJobState.completed);
      expect(calls.last, 'complete');
    },
  );

  test('source length mismatch never finalizes the remote object', () async {
    final calls = <String>[];
    final coordinator = UploadCoordinator(
      scheduler: UploadScheduler(mobile: true),
    );
    final api = UploadSessionApi(
      tokenProvider: () async => 'session',
      client: MockClient((request) async {
        final op = request.url.pathSegments.last;
        calls.add(op);
        return http.Response(
          jsonEncode(
            op == 'start'
                ? {'sessionId': 'session-id'}
                : {'status': 'uploading', 'parts': []},
          ),
          200,
        );
      }),
    );
    await expectLater(
      coordinator.upload(
        objectKey: 'opaque',
        length: 4,
        ciphertext: Stream.value([1, 2, 3]),
        api: api,
        put: (_, _) async {},
      ),
      throwsA(isA<UploadFailure>()),
    );
    expect(calls, isNot(contains('complete')));
    expect(coordinator.scheduler.active, 0);
  });
}
