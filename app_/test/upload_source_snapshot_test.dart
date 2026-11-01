import 'dart:typed_data';

import 'package:cloud_storage/src/storage/upload_block_hashes_local.dart'
    as local;
import 'package:cloud_storage/src/storage/upload_block_hashes_native.dart'
    as native;
import 'package:cloud_storage/src/storage/upload_coordinator.dart';
import 'package:cloud_storage/src/storage/upload_source_snapshot.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final implementation in [
    local.hashUploadBlocks,
    native.hashUploadBlocks,
  ]) {
    test(
      'hash worker preserves bytes and honors cancellation backpressure',
      () async {
        var produced = 0;
        var closed = false;
        final bytes = Uint8List.fromList([1, 2, 3]);
        Stream<Uint8List> source() async* {
          try {
            for (var i = 0; i < 100; i++) {
              produced++;
              yield bytes;
            }
          } finally {
            closed = true;
          }
        }

        final results = await implementation(source()).take(1).toList();
        expect(results.single.$1, bytes);
        expect(results.single.$2, sha256.convert(bytes).toString());
        expect(produced, 1);
        expect(closed, isTrue);
      },
    );

    test(
      'hash worker propagates source errors and permits a fresh pass',
      () async {
        await expectLater(
          implementation(Stream<Uint8List>.error(StateError('source failure'))),
          emitsError(isA<StateError>()),
        );
        expect(
          await implementation(const Stream<Uint8List>.empty()).toList(),
          isEmpty,
        );
      },
    );
  }

  test(
    'snapshot fingerprint remains compatible across stream boundaries',
    () async {
      final bytes = Uint8List.fromList(List.generate(300000, (i) => i % 251));
      final hashes = [
        sha256
            .convert(bytes.sublist(0, UploadSourceSnapshot.blockBytes))
            .toString(),
        sha256
            .convert(bytes.sublist(UploadSourceSnapshot.blockBytes))
            .toString(),
      ];
      final expected = sha256.convert([
        ...'upload-source-v1:${bytes.length}:'.codeUnits,
        ...hashes.join(':').codeUnits,
      ]).toString();
      final snapshot = await UploadSourceSnapshot.capture(Stream.value(bytes));
      expect(snapshot.fingerprint, expected);
      final verified = await snapshot
          .verify(
            Stream.fromIterable([bytes.sublist(0, 17), bytes.sublist(17)]),
          )
          .expand((block) => block)
          .toList();
      expect(verified, bytes);
      for (final changed in [
        bytes.sublist(0, bytes.length - 1),
        [...bytes, 0],
        [bytes.first ^ 1, ...bytes.skip(1)],
      ]) {
        await expectLater(
          snapshot.verify(Stream.value(changed)).drain<void>(),
          throwsA(
            isA<UploadFailure>().having(
              (e) => e.code,
              'code',
              'source_changed',
            ),
          ),
        );
      }
    },
  );
}
