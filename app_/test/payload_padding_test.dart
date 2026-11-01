import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_storage/src/security/payload_padding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PayloadPadding tests', () {
    test('Pads small payload into 64 KiB minimum bucket', () {
      final smallData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final padded = PayloadPadding.padPayload(smallData);

      expect(padded.length, equals(64 * 1024));

      final unpadded = PayloadPadding.unpadPayload(padded);
      expect(unpadded, equals(smallData));
    });

    test('Pads empty payload correctly', () {
      final empty = Uint8List(0);
      final padded = PayloadPadding.padPayload(empty);

      expect(padded.length, equals(64 * 1024));

      final unpadded = PayloadPadding.unpadPayload(padded);
      expect(unpadded.length, equals(0));
    });

    test('Scales up to standard power-of-two bucket tiers', () {
      // 100 KiB payload -> must fit into 256 KiB bucket
      final data100k = Uint8List(100 * 1024);
      for (var i = 0; i < data100k.length; i++) {
        data100k[i] = i % 256;
      }

      final padded256k = PayloadPadding.padPayload(data100k);
      expect(padded256k.length, equals(256 * 1024));

      final recovered = PayloadPadding.unpadPayload(padded256k);
      expect(recovered, equals(data100k));

      // 500 KiB payload -> fits into 1 MiB bucket
      final data500k = Uint8List(500 * 1024);
      final padded1M = PayloadPadding.padPayload(data500k);
      expect(padded1M.length, equals(1024 * 1024));
      expect(PayloadPadding.unpadPayload(padded1M), equals(data500k));
    });

    test('Handles large payloads with 4 MiB alignment', () {
      // 18 MiB payload -> next 4 MiB boundary is 20 MiB
      final length = 18 * 1024 * 1024;
      final targetSize = PayloadPadding.calculatePaddedBucketSize(length);
      expect(targetSize, equals(20 * 1024 * 1024));
    });

    test('Deterministic padding with custom seeded RNG', () {
      final data = Uint8List.fromList([10, 20, 30]);
      final rng1 = Random(42);
      final rng2 = Random(42);

      final padded1 = PayloadPadding.padPayload(data, random: rng1);
      final padded2 = PayloadPadding.padPayload(data, random: rng2);

      expect(padded1, equals(padded2));
    });

    test('Rejects malformed or truncated padded payloads', () {
      // Buffer smaller than 4-byte header
      expect(
        () => PayloadPadding.unpadPayload(Uint8List.fromList([1, 2])),
        throwsA(isA<FormatException>()),
      );

      // Header indicates 100 bytes, but container only has 10 bytes
      final corrupt = Uint8List(10);
      ByteData.sublistView(corrupt).setUint32(0, 100, Endian.big);
      expect(
        () => PayloadPadding.unpadPayload(corrupt),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
