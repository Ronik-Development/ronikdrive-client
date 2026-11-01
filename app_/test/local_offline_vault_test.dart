import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_storage/src/privacy/local_offline_vault.dart';
import 'package:cloud_storage/src/privacy/local_private_cache.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryKeyStore implements LocalPrivateCacheKeyStore {
  final Map<String, String> values = <String, String>{};
  bool failReads = false;
  bool failWrites = false;
  bool failDeletes = false;

  @override
  Future<void> delete(String key) async {
    if (failDeletes) {
      throw StateError('key store unavailable');
    }
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    if (failReads) {
      throw StateError('key store unavailable');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) {
      throw StateError('key store unavailable');
    }
    values[key] = value;
  }
}

Matcher _vaultFailure(LocalOfflineVaultFailure failure) {
  return isA<LocalOfflineVaultException>().having(
    (error) => error.failure,
    'failure',
    failure,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ronikdrive-offline-vault-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('preview revocation stops authenticated offline frame reads', () async {
    final vault = LocalOfflineVault(
      uid: 'alice',
      scope: 'test',
      keyStore: _MemoryKeyStore(),
      chunkSize: 4,
    );
    final file = File('${temporaryDirectory.path}/revocation.rdoffline');
    await vault.encryptStream(
      plaintext: Stream.value(utf8.encode('private content')),
      destination: file,
      objectKey: 'opaque-object',
    );
    var checks = 0;
    await expectLater(
      vault.readBytes(
        source: file,
        objectKey: 'opaque-object',
        checkAccess: () {
          checks++;
          if (checks > 1) throw StateError('revoked');
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(checks, 2);
    expect(temporaryDirectory.listSync().length, 1);
    expect(await vault.isEncryptedFile(file), true);
  });

  test(
    'round trips chunked content without exposing names or plaintext',
    () async {
      final store = _MemoryKeyStore();
      final vault = LocalOfflineVault(
        uid: 'alice-account',
        scope: 'production-project',
        keyStore: store,
        chunkSize: 7,
      );
      const objectKey = 'users/alice/Finance/2026-tax-return.txt';
      final plaintext = Uint8List.fromList(
        utf8.encode('private tax data that crosses several vault frames'),
      );
      final destination = File(
        '${temporaryDirectory.path}/${vault.opaqueFileName(objectKey)}',
      );

      final written = await vault.encryptStream(
        plaintext: Stream<List<int>>.fromIterable(<List<int>>[
          plaintext.sublist(0, 3),
          plaintext.sublist(3, 19),
          plaintext.sublist(19),
        ]),
        destination: destination,
        objectKey: objectKey,
      );

      expect(written.plaintextLength, plaintext.length);
      expect(written.encryptedLength, greaterThan(plaintext.length));
      expect(destination.path, isNot(contains('Finance')));
      expect(destination.path, isNot(contains('tax-return')));
      expect(
        LocalOfflineVault(
          uid: 'alice-account',
          scope: 'staging-project',
          keyStore: store,
        ).opaqueFileName(objectKey),
        isNot(vault.opaqueFileName(objectKey)),
      );
      expect(
        LocalOfflineVault(
          uid: 'bob-account',
          scope: 'production-project',
          keyStore: store,
        ).opaqueFileName(objectKey),
        isNot(vault.opaqueFileName(objectKey)),
      );
      expect(
        utf8.decode(await destination.readAsBytes(), allowMalformed: true),
        isNot(contains('private tax')),
      );
      expect(await vault.isEncryptedFile(destination), isTrue);
      expect(
        await vault.readBytes(source: destination, objectKey: objectKey),
        plaintext,
      );
    },
  );

  test('supports empty files and exact chunk boundaries', () async {
    final vault = LocalOfflineVault(
      uid: 'alice-account',
      keyStore: _MemoryKeyStore(),
      chunkSize: 8,
    );
    for (final entry in <String, Uint8List>{
      'empty': Uint8List(0),
      'exact': Uint8List.fromList(List<int>.generate(16, (index) => index)),
    }.entries) {
      final destination = File(
        '${temporaryDirectory.path}/${entry.key}.rdoffline',
      );
      await vault.encryptStream(
        plaintext: Stream<List<int>>.value(entry.value),
        destination: destination,
        objectKey: entry.key,
      );
      expect(
        await vault.readBytes(source: destination, objectKey: entry.key),
        entry.value,
      );
    }
  });

  test('authenticates object identity and the workspace file key', () async {
    final vault = LocalOfflineVault(
      uid: 'alice-account',
      scope: 'production-project',
      keyStore: _MemoryKeyStore(),
      chunkSize: 8,
    );
    final destination = File('${temporaryDirectory.path}/bound.rdoffline');
    final correctBinding = SecretKey(List<int>.filled(32, 7));
    final wrongBinding = SecretKey(List<int>.filled(32, 9));
    await vault.encryptStream(
      plaintext: Stream<List<int>>.value(utf8.encode('secured offline data')),
      destination: destination,
      objectKey: 'users/alice/secured-object',
      bindingKey: correctBinding,
    );

    await expectLater(
      vault.readBytes(
        source: destination,
        objectKey: 'users/alice/different-object',
        bindingKey: correctBinding,
      ),
      throwsA(_vaultFailure(LocalOfflineVaultFailure.corruptPayload)),
    );
    await expectLater(
      vault.readBytes(
        source: destination,
        objectKey: 'users/alice/secured-object',
        bindingKey: wrongBinding,
      ),
      throwsA(_vaultFailure(LocalOfflineVaultFailure.corruptPayload)),
    );
    expect(
      await vault.readBytes(
        source: destination,
        objectKey: 'users/alice/secured-object',
        bindingKey: correctBinding,
      ),
      utf8.encode('secured offline data'),
    );
  });

  test('rejects tampering, truncation, and trailing frames', () async {
    final store = _MemoryKeyStore();
    final vault = LocalOfflineVault(
      uid: 'alice-account',
      keyStore: store,
      chunkSize: 8,
    );
    final original = File('${temporaryDirectory.path}/original.rdoffline');
    await vault.encryptStream(
      plaintext: Stream<List<int>>.value(
        utf8.encode('authenticated offline content'),
      ),
      destination: original,
      objectKey: 'object-a',
    );
    final originalBytes = await original.readAsBytes();

    final tampered = File('${temporaryDirectory.path}/tampered.rdoffline');
    final tamperedBytes = Uint8List.fromList(originalBytes);
    tamperedBytes[tamperedBytes.length ~/ 2] ^= 0x40;
    await tampered.writeAsBytes(tamperedBytes, flush: true);

    final truncated = File('${temporaryDirectory.path}/truncated.rdoffline');
    await truncated.writeAsBytes(
      originalBytes.sublist(0, originalBytes.length - 3),
      flush: true,
    );

    final trailing = File('${temporaryDirectory.path}/trailing.rdoffline');
    await trailing.writeAsBytes(<int>[...originalBytes, 0], flush: true);

    for (final file in <File>[tampered, truncated, trailing]) {
      await expectLater(
        vault.readBytes(source: file, objectKey: 'object-a'),
        throwsA(_vaultFailure(LocalOfflineVaultFailure.corruptPayload)),
      );
    }
  });

  test(
    'does not replace a valid vault object after a failed source stream',
    () async {
      final vault = LocalOfflineVault(
        uid: 'alice-account',
        keyStore: _MemoryKeyStore(),
        chunkSize: 8,
      );
      final destination = File('${temporaryDirectory.path}/atomic.rdoffline');
      await vault.encryptStream(
        plaintext: Stream<List<int>>.value(utf8.encode('known good value')),
        destination: destination,
        objectKey: 'atomic-object',
      );
      final before = await destination.readAsBytes();

      final failingStream = Stream<List<int>>.multi((controller) {
        controller.add(utf8.encode('replacement'));
        controller.addError(StateError('source disappeared'));
        controller.close();
      });
      await expectLater(
        vault.encryptStream(
          plaintext: failingStream,
          destination: destination,
          objectKey: 'atomic-object',
        ),
        throwsA(_vaultFailure(LocalOfflineVaultFailure.storageFailure)),
      );

      expect(await destination.readAsBytes(), before);
      expect(
        await vault.readBytes(source: destination, objectKey: 'atomic-object'),
        utf8.encode('known good value'),
      );
      expect(
        temporaryDirectory.listSync().where(
          (entry) => entry.path.contains('.part-'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'fails closed when the keychain is unavailable or key is forgotten',
    () async {
      final store = _MemoryKeyStore();
      final vault = LocalOfflineVault(
        uid: 'alice-account',
        scope: 'production-project',
        keyStore: store,
      );
      final destination = File('${temporaryDirectory.path}/locked.rdoffline');
      await vault.encryptStream(
        plaintext: Stream<List<int>>.value(utf8.encode('offline secret')),
        destination: destination,
        objectKey: 'locked-object',
      );

      store.failReads = true;
      final lockedVault = LocalOfflineVault(
        uid: 'alice-account',
        scope: 'production-project',
        keyStore: store,
      );
      await expectLater(
        lockedVault.readBytes(source: destination, objectKey: 'locked-object'),
        throwsA(_vaultFailure(LocalOfflineVaultFailure.keyUnavailable)),
      );

      store.failReads = false;
      await vault.forgetKey();
      final forgottenVault = LocalOfflineVault(
        uid: 'alice-account',
        scope: 'production-project',
        keyStore: store,
      );
      await expectLater(
        forgottenVault.readBytes(
          source: destination,
          objectKey: 'locked-object',
        ),
        throwsA(_vaultFailure(LocalOfflineVaultFailure.keyUnavailable)),
      );
      expect(await destination.exists(), isTrue);
    },
  );

  test('cleans only stale vault-owned temporary files', () async {
    final vault = LocalOfflineVault(
      uid: 'alice-account',
      keyStore: _MemoryKeyStore(),
    );
    final baseName = vault.opaqueFileName('cleanup-object');
    final stale = File('${temporaryDirectory.path}/$baseName.part-1-2');
    final recent = File('${temporaryDirectory.path}/$baseName.previous-3-4');
    final unrelated = File('${temporaryDirectory.path}/notes.part-1-2');
    await stale.writeAsBytes(const <int>[1]);
    await recent.writeAsBytes(const <int>[2]);
    await unrelated.writeAsBytes(const <int>[3]);
    await stale.setLastModified(
      DateTime.now().subtract(const Duration(days: 1)),
    );

    await vault.cleanupTemporaryFiles(
      temporaryDirectory,
      minimumAge: const Duration(hours: 1),
    );

    expect(await stale.exists(), isFalse);
    expect(await recent.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
  });

  test(
    'recognizes legacy plaintext without reading it as a vault object',
    () async {
      final vault = LocalOfflineVault(
        uid: 'alice-account',
        keyStore: _MemoryKeyStore(),
      );
      final legacy = File('${temporaryDirectory.path}/legacy.txt');
      await legacy.writeAsString('old plaintext offline copy', flush: true);
      await vault.encryptStream(
        plaintext: Stream<List<int>>.value(const <int>[]),
        destination: File('${temporaryDirectory.path}/seed.rdoffline'),
        objectKey: 'seed-object',
      );

      expect(await vault.isEncryptedFile(legacy), isFalse);
      await expectLater(
        vault.readBytes(source: legacy, objectKey: 'legacy-object'),
        throwsA(_vaultFailure(LocalOfflineVaultFailure.unsupportedFormat)),
      );
    },
  );
}
