import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_storage/src/privacy/memory_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'partial decrypted bytes are withheld until final authentication',
    () async {
      final source = StreamController<List<int>>();
      var returned = false;
      final result =
          readAuthenticatedBytes(
            source.stream,
            maximumBytes: 8,
            checkAccess: () {},
          ).then((value) {
            returned = true;
            return value;
          });
      source.add([1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      expect(returned, false);
      final assertion = expectLater(result, throwsA(isA<StateError>()));
      source.addError(StateError('final MAC invalid'));
      await source.close();
      await assertion;
      expect(returned, false);
    },
  );

  test(
    'actual length overrides dishonest file metadata and cancels input',
    () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final result = readAuthenticatedBytes(
        source.stream,
        maximumBytes: 3,
        checkAccess: () {},
      );
      final assertion = expectLater(result, throwsA(isA<PreviewUnavailable>()));
      source.add([1, 2]);
      source.add([3, 4]);
      await assertion;
      expect(cancelled, true);
      await source.close();
    },
  );

  test(
    'closing a preview cancels a stalled stream without waiting for data',
    () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final guard = PreviewReadGuard(() => true);
      final result = readAuthenticatedBytes(
        source.stream,
        maximumBytes: 4,
        checkAccess: guard.check,
        guard: guard,
      );
      final assertion = expectLater(result, throwsA(isA<PreviewUnavailable>()));
      await Future<void>.delayed(Duration.zero);
      guard.cancel();
      await assertion.timeout(const Duration(seconds: 2));
      expect(cancelled, true);
      await source.close();
      guard.dispose();
    },
  );

  test('revocation at completion never returns plaintext', () async {
    var authorized = true;
    final guard = PreviewReadGuard(() => authorized);
    Stream<List<int>> source() async* {
      yield [1, 2];
      authorized = false;
    }

    await expectLater(
      readAuthenticatedBytes(source(), checkAccess: guard.check, guard: guard),
      throwsA(isA<PreviewUnavailable>()),
    );
    authorized = true;
    expect(guard.check, throwsA(isA<PreviewUnavailable>()));
    guard.dispose();
  });

  test('broken authorization checks fail closed', () {
    final guard = PreviewReadGuard(() => throw StateError('key unavailable'));
    expect(guard.check, throwsA(isA<PreviewUnavailable>()));
    expect(guard.cancelled, true);
    guard.dispose();
  });

  test('already revoked reads cancel the acquired transport', () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final guard = PreviewReadGuard(() => false);
    await expectLater(
      readAuthenticatedBytes(
        source.stream,
        checkAccess: guard.check,
        guard: guard,
      ),
      throwsA(isA<PreviewUnavailable>()),
    );
    expect(cancelled, true);
    await source.close();
    guard.dispose();
  });

  test('tiny and empty transport chunks preserve bounded assembly', () {
    final buffer = SensitiveByteBuffer(maximumBytes: 100000);
    for (var i = 0; i < 100000; i++) {
      buffer.add([]);
      buffer.add([i % 251]);
    }
    final bytes = buffer.takeBytes();
    expect(bytes.length, 100000);
    expect(bytes[65536], 65536 % 251);
    expect(bytes.last, 99999 % 251);
    expect(buffer.length, 0);
  });

  test('owned buffer copies chunks and does not wipe downloader storage', () {
    final original = Uint8List.fromList([4, 5, 6]);
    final buffer = SensitiveByteBuffer(maximumBytes: 3)..add(original);
    original[0] = 9;
    expect(buffer.takeBytes(), [4, 5, 6]);
    expect(buffer.length, 0);
    expect(original, [9, 5, 6]);
  });

  test('bounded text rows preserve source without interpreting markup', () {
    const malicious = '<script>fetch("https://example.invalid")</script>';
    expect(
      MemoryPreviewPolicy.textRows(Uint8List.fromList(utf8.encode(malicious))),
      [malicious],
    );
    final long = '${'a' * 2047}😀${'z' * 4000}';
    final rows = MemoryPreviewPolicy.textRows(
      Uint8List.fromList(utf8.encode(long)),
    );
    expect(rows.join(), long);
    expect(rows.every((row) => row.length <= 2048), true);
    expect(
      () => MemoryPreviewPolicy.textRows(
        Uint8List(MemoryPreviewPolicy.textBytes + 1),
      ),
      throwsA(isA<PreviewUnavailable>()),
    );
    expect(
      () => MemoryPreviewPolicy.textRows(
        Uint8List.fromList(utf8.encode('\n' * 20000)),
      ),
      throwsA(isA<PreviewUnavailable>()),
    );
  });
}
