import 'dart:typed_data';

import 'package:cloud_storage/src/security/memory_protection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryProtection tests', () {
    test('secureZero overwrites Uint8List buffer in-place', () {
      final buffer = Uint8List.fromList([1, 2, 3, 4, 5, 255]);
      expect(buffer.any((byte) => byte != 0), isTrue);

      MemoryProtection.secureZero(buffer);
      expect(buffer.every((byte) => byte == 0), isTrue);
      expect(buffer.length, equals(6));
    });

    test('secureZero handles null and empty buffers gracefully', () {
      expect(() => MemoryProtection.secureZero(null), returnsNormally);
      expect(() => MemoryProtection.secureZero(Uint8List(0)), returnsNormally);
    });

    test('secureZeroList overwrites integer list in-place', () {
      final list = <int>[10, 20, 30, 40];
      MemoryProtection.secureZeroList(list);
      expect(list, equals([0, 0, 0, 0]));
    });

    test('withTemporaryKeyBuffer wipes buffer on successful completion', () async {
      final keyBytes = Uint8List.fromList([42, 43, 44, 45]);
      var observedValue = 0;

      final result = await MemoryProtection.withTemporaryKeyBuffer(keyBytes, (buf) async {
        observedValue = buf[0];
        return 'processed';
      });

      expect(result, equals('processed'));
      expect(observedValue, equals(42));
      // After execution, the original buffer must be wiped
      expect(keyBytes.every((b) => b == 0), isTrue);
    });

    test('withTemporaryKeyBuffer wipes buffer even on exception', () async {
      final keyBytes = Uint8List.fromList([99, 100, 101]);

      await expectLater(
        MemoryProtection.withTemporaryKeyBuffer(keyBytes, (buf) async {
          throw Exception('Simulated crypto failure');
        }),
        throwsA(isA<Exception>()),
      );

      // Must still be zeroed despite failure
      expect(keyBytes.every((b) => b == 0), isTrue);
    });

    test('withTemporaryKeyBufferSync wipes buffer on sync execution', () {
      final keyBytes = Uint8List.fromList([1, 2, 3]);
      final output = MemoryProtection.withTemporaryKeyBufferSync(keyBytes, (buf) => buf.length);
      expect(output, equals(3));
      expect(keyBytes.every((b) => b == 0), isTrue);
    });

    test('constantTimeCompare detects equality and differences securely', () {
      final a = [1, 2, 3, 4, 5];
      final b = [1, 2, 3, 4, 5];
      final c = [1, 2, 3, 4, 6];
      final d = [1, 2, 3];

      expect(MemoryProtection.constantTimeCompare(a, b), isTrue);
      expect(MemoryProtection.constantTimeCompare(a, c), isFalse);
      expect(MemoryProtection.constantTimeCompare(a, d), isFalse);
    });
  });
}
