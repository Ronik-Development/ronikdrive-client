import 'dart:async';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/privacy/native_download_pipeline.dart';
import 'package:cloud_storage/src/privacy/temporary_plaintext_lease.dart';

void main() {
  late Directory root;
  late TemporaryPlaintextLeaseManager manager;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ronik-synthetic-download-');
    manager = TemporaryPlaintextLeaseManager(
      rootDirectoryProvider: () async => Directory('${root.path}/leases'),
    );
  });
  tearDown(() async {
    await manager.cleanupActive(minimumAge: Duration.zero);
    if (await root.exists()) await root.delete(recursive: true);
  });
  final algorithm = AesCtr.with256bits(macAlgorithm: Hmac.sha256());
  final key = SecretKey(List.generate(32, (i) => i));
  Future<List<int>> framed(List<int> bytes) async {
    final box = await algorithm.encrypt(
      bytes,
      secretKey: key,
      nonce: List.filled(16, 3),
    );
    return [...box.nonce, ...box.cipherText, ...box.mac.bytes];
  }

  Stream<List<int>> chunks(List<int> bytes) async* {
    for (var i = 0; i < bytes.length; i += 31) {
      yield bytes.sublist(i, i + 31 < bytes.length ? i + 31 : bytes.length);
    }
  }

  for (final length in [0, 1, 15, 16, 17, 65539]) {
    test('framed streaming restores exact $length bytes', () async {
      final bytes = List.generate(length, (i) => i % 251),
          lease = await manager.create();
      expect(
        await lease.writeStream(
          decryptFramedDownload(
            chunks(await framed(bytes)),
            key: key,
            manager: manager,
            checkAccess: () {},
          ),
        ),
        length,
      );
      expect(await lease.file.readAsBytes(), bytes);
      await lease.release();
      expect(await Directory('${root.path}/leases').list().length, 0);
    });
  }
  test(
    'late MAC failure deletes partial plaintext and staged ciphertext',
    () async {
      final bytes = await framed(List.filled(65539, 4));
      bytes[bytes.length - 1] ^= 1;
      final lease = await manager.create();
      await expectLater(
        lease.writeStream(
          decryptFramedDownload(
            chunks(bytes),
            key: key,
            manager: manager,
            checkAccess: () {},
          ),
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      expect(lease.isActive, false);
      expect(await Directory('${root.path}/leases').list().length, 0);
    },
  );
  test('access change and source error delete partial sink', () async {
    final lease = await manager.create();
    var checks = 0;
    await expectLater(
      lease.writeStream(
        Stream.fromIterable([List.filled(4096, 1), List.filled(4096, 2)]),
        checkAccess: () {
          if (++checks == 3) throw StateError('Synthetic revoked access');
        },
      ),
      throwsStateError,
    );
    expect(lease.isActive, false);
    final other = await manager.create();
    Stream<List<int>> failed() async* {
      yield [1];
      throw const FileSystemException('Synthetic full disk');
    }

    await expectLater(
      other.writeStream(failed()),
      throwsA(isA<FileSystemException>()),
    );
    expect(other.isActive, false);
  });
  test('ZIP preserves names, ordering and bytes outside UI isolate', () async {
    final output = await manager.create(extension: '.zip'),
        zip = await NativeStreamingZip.create(output);
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    final expected = <String, List<int>>{
      'folder/first.txt': [1, 2, 3],
      'second.bin': List.generate(1024 * 1024, (i) => i % 251),
    };
    try {
      for (final entry in expected.entries) {
        final input = await manager.create();
        await input.writeBytes(entry.value);
        await zip.add(input, entry.key);
        await input.release();
      }
      await zip.close();
      await output.seal();
      final archive = ZipDecoder().decodeBytes(
        await output.file.readAsBytes(),
        verify: true,
      );
      expect(archive.files.map((f) => f.name), expected.keys);
      for (final file in archive.files) {
        expect(file.content, expected[file.name]);
      }
      expect(ticks, greaterThan(0));
    } finally {
      timer.cancel();
      zip.cancel();
      await output.release();
    }
  });
  test('ZIP rejects traversal and missing sources', () async {
    final output = await manager.create(extension: '.zip'),
        input = await manager.create(),
        zip = await NativeStreamingZip.create(output);
    try {
      for (final name in ['../file', '/file', r'folder\file']) {
        await expectLater(zip.add(input, name), throwsFormatException);
      }
      await input.file.delete();
      await expectLater(zip.add(input, 'file'), throwsStateError);
    } finally {
      zip.cancel();
      await input.release();
      await output.release();
    }
  });
}
