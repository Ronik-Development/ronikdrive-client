import 'package:cloud_storage/src/privacy/local_private_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryKeyStore implements LocalPrivateCacheKeyStore {
  final Map<String, String> values = <String, String>{};
  bool failReads = false;
  bool failWrites = false;

  @override
  Future<void> delete(String key) async {
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

String _tamperCiphertext(String value) {
  final index = LocalPrivateCacheCodec.encryptedPrefix.length + 8;
  final replacement = value[index] == 'A' ? 'B' : 'A';
  return value.replaceRange(index, index + 1, replacement);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalPrivateCacheCodec', () {
    test('registers every sensitive workspace preference for key erasure', () {
      expect(LocalPrivateCacheCodec.protectedPreferenceNamespaces, const {
        LocalPrivateCacheCodec.backupConfigsPreferenceKey:
            LocalPrivateCacheCodec.backupConfigsNamespace,
        LocalPrivateCacheCodec.backupFingerprintsPreferenceKey:
            LocalPrivateCacheCodec.backupFingerprintsNamespace,
        LocalPrivateCacheCodec.transferJournalPreferenceKey:
            LocalPrivateCacheCodec.transferJournalNamespace,
        LocalPrivateCacheCodec.desktopDrivePreferenceKey:
            LocalPrivateCacheCodec.desktopDriveNamespace,
        LocalPrivateCacheCodec.desktopDriveStatusPreferenceKey:
            LocalPrivateCacheCodec.desktopDriveStatusNamespace,
        LocalPrivateCacheCodec.cachedFilesPreferenceKey:
            LocalPrivateCacheCodec.cachedFilesNamespace,
        LocalPrivateCacheCodec.cachedFoldersPreferenceKey:
            LocalPrivateCacheCodec.cachedFoldersNamespace,
        LocalPrivateCacheCodec.offlineFilesPreferenceKey:
            LocalPrivateCacheCodec.offlineFilesNamespace,
        LocalPrivateCacheCodec.offlineFoldersPreferenceKey:
            LocalPrivateCacheCodec.offlineFoldersNamespace,
        LocalPrivateCacheCodec.offlineDirectoryPreferenceKey:
            LocalPrivateCacheCodec.offlineDirectoryNamespace,
        LocalPrivateCacheCodec.businessReconciliationPreferenceKey:
            LocalPrivateCacheCodec.businessReconciliationNamespace,
        LocalPrivateCacheCodec.businessReconciliationQueuePreferenceKey:
            LocalPrivateCacheCodec.businessReconciliationQueueNamespace,
      });
    });

    test('round trips without exposing paths or raw hashes', () async {
      final codec = LocalPrivateCacheCodec(keyStore: _MemoryKeyStore());
      const plaintext =
          '{"path":"C:\\\\Users\\\\alice\\\\Finance",'
          '"hash":"raw-sha256-value"}';

      final first = await codec.seal(
        uid: 'account-alice',
        namespace: LocalPrivateCacheCodec.backupFingerprintsNamespace,
        plaintext: plaintext,
      );
      final second = await codec.seal(
        uid: 'account-alice',
        namespace: LocalPrivateCacheCodec.backupFingerprintsNamespace,
        plaintext: plaintext,
      );

      expect(first, startsWith(LocalPrivateCacheCodec.encryptedPrefix));
      expect(first, isNot(contains('alice')));
      expect(first, isNot(contains('Finance')));
      expect(first, isNot(contains('raw-sha256-value')));
      expect(second, isNot(first), reason: 'AES-GCM must use a fresh nonce.');

      final opened = await codec.open(
        uid: 'account-alice',
        namespace: LocalPrivateCacheCodec.backupFingerprintsNamespace,
        value: first,
      );
      expect(opened.plaintext, plaintext);
      expect(opened.needsMigration, isFalse);
    });

    test('authenticates the account, namespace, and ciphertext', () async {
      final store = _MemoryKeyStore();
      final codec = LocalPrivateCacheCodec(keyStore: store);
      final protected = await codec.seal(
        uid: 'account-alice',
        namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
        plaintext: '[{"path":"/home/alice/private"}]',
      );

      await expectLater(
        codec.open(
          uid: 'account-alice',
          namespace: LocalPrivateCacheCodec.backupFingerprintsNamespace,
          value: protected,
        ),
        throwsA(
          isA<LocalPrivateCacheException>().having(
            (error) => error.failure,
            'failure',
            LocalPrivateCacheFailure.corruptPayload,
          ),
        ),
      );
      await expectLater(
        LocalPrivateCacheCodec(keyStore: store).open(
          uid: 'account-bob',
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
          value: protected,
        ),
        throwsA(
          isA<LocalPrivateCacheException>().having(
            (error) => error.failure,
            'failure',
            LocalPrivateCacheFailure.keyUnavailable,
          ),
        ),
      );

      final tampered = _tamperCiphertext(protected);
      await expectLater(
        codec.open(
          uid: 'account-alice',
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
          value: tampered,
        ),
        throwsA(
          isA<LocalPrivateCacheException>().having(
            (error) => error.failure,
            'failure',
            LocalPrivateCacheFailure.corruptPayload,
          ),
        ),
      );
    });

    test('identifies legacy plaintext for a one-time migration', () async {
      final codec = LocalPrivateCacheCodec(keyStore: _MemoryKeyStore());
      final opened = await codec.open(
        uid: 'account-alice',
        namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
        value: '[{"path":"legacy-local-path"}]',
      );

      expect(opened.needsMigration, isTrue);
      expect(opened.plaintext, contains('legacy-local-path'));
    });

    test(
      'forgetting an account makes its cache cryptographically unavailable',
      () async {
        final codec = LocalPrivateCacheCodec(keyStore: _MemoryKeyStore());
        final protected = await codec.seal(
          uid: 'account-alice',
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
          plaintext: 'private settings',
        );

        await codec.forgetAccount('account-alice');

        await expectLater(
          codec.open(
            uid: 'account-alice',
            namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
            value: protected,
          ),
          throwsA(
            isA<LocalPrivateCacheException>().having(
              (error) => error.failure,
              'failure',
              LocalPrivateCacheFailure.keyUnavailable,
            ),
          ),
        );
      },
    );
  });

  group('LocalPrivateCachePreferences', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
      'migrates legacy unscoped plaintext and removes every old key',
      () async {
        const baseKey = 'workspace_backup_signatures_v1';
        const uid = 'firebase-user/alice';
        const legacy =
            '{"configs":[{"path":"C:\\\\Users\\\\alice\\\\Private",'
            '"files":[{"hash":"raw-public-hash"}]}]}';
        SharedPreferences.setMockInitialValues(<String, Object>{
          baseKey: legacy,
        });
        final prefs = await SharedPreferences.getInstance();
        final codec = LocalPrivateCacheCodec(keyStore: _MemoryKeyStore());
        final cache = LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          codec: codec,
        );

        final read = await cache.read(
          baseKey: baseKey,
          namespace: LocalPrivateCacheCodec.backupFingerprintsNamespace,
        );

        expect(read.value, legacy);
        expect(read.migrated, isTrue);
        final primary = LocalPrivateCachePreferences.scopedPreferenceKey(
          baseKey,
          uid,
        );
        final stored = prefs.getString(primary);
        expect(stored, startsWith(LocalPrivateCacheCodec.encryptedPrefix));
        expect(stored, isNot(contains('alice')));
        expect(stored, isNot(contains('Private')));
        expect(stored, isNot(contains('raw-public-hash')));
        expect(prefs.containsKey(baseKey), isFalse);
        expect(prefs.containsKey('${baseKey}_firebase-user_alice'), isFalse);

        final repeated = await cache.read(
          baseKey: baseKey,
          namespace: LocalPrivateCacheCodec.backupFingerprintsNamespace,
        );
        expect(repeated.value, legacy);
        expect(repeated.migrated, isFalse);
      },
    );

    test('keeps encrypted settings isolated between local accounts', () async {
      final prefs = await SharedPreferences.getInstance();
      final codec = LocalPrivateCacheCodec(keyStore: _MemoryKeyStore());
      final alice = LocalPrivateCachePreferences(
        preferences: prefs,
        uid: 'alice',
        codec: codec,
      );
      final bob = LocalPrivateCachePreferences(
        preferences: prefs,
        uid: 'bob',
        codec: codec,
      );

      await alice.write(
        baseKey: 'workspace_backup_configs_v1',
        namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
        value: '[{"path":"/home/alice"}]',
      );

      final bobRead = await bob.read(
        baseKey: 'workspace_backup_configs_v1',
        namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
      );
      expect(bobRead.value, isNull);
      expect(
        LocalPrivateCachePreferences.scopedPreferenceKey(
          'workspace_backup_configs_v1',
          'alice',
        ),
        isNot(
          LocalPrivateCachePreferences.scopedPreferenceKey(
            'workspace_backup_configs_v1',
            'bob',
          ),
        ),
      );
    });

    test(
      'isolates environments and migrates the earlier UID-only scope',
      () async {
        const baseKey = 'workspace_backup_configs_v1';
        const uid = 'same-firebase-uid';
        final prefs = await SharedPreferences.getInstance();
        final codec = LocalPrivateCacheCodec(keyStore: _MemoryKeyStore());
        final uidOnly = LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          codec: codec,
        );
        await uidOnly.write(
          baseKey: baseKey,
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
          value: '[{"path":"/home/alice"}]',
        );

        final production = LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          scope: 'ronikdrive-production',
          codec: codec,
        );
        final migrated = await production.read(
          baseKey: baseKey,
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
        );
        expect(migrated.value, '[{"path":"/home/alice"}]');
        expect(migrated.migrated, isTrue);
        expect(
          prefs.containsKey(
            LocalPrivateCachePreferences.scopedPreferenceKey(baseKey, uid),
          ),
          isFalse,
        );

        final staging = LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          scope: 'ronikdrive-staging',
          codec: codec,
        );
        final stagingRead = await staging.read(
          baseKey: baseKey,
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
        );
        expect(stagingRead.value, isNull);
      },
    );

    test(
      'stores workspace caches without plaintext paths, labels, or object references',
      () async {
        const uid = 'offline-user';
        const scope = 'production-project';
        final prefs = await SharedPreferences.getInstance();
        final cache = LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          scope: scope,
          codec: LocalPrivateCacheCodec(keyStore: _MemoryKeyStore()),
        );
        const values = <String, (String, String)>{
          LocalPrivateCacheCodec.cachedFilesPreferenceKey: (
            LocalPrivateCacheCodec.cachedFilesNamespace,
            '[{"name":"Q4 acquisition.pdf","objectKey":'
                '"opaque/object-123"}]',
          ),
          LocalPrivateCacheCodec.cachedFoldersPreferenceKey: (
            LocalPrivateCacheCodec.cachedFoldersNamespace,
            '[{"name":"Board and Finance","id":"folder-123"}]',
          ),
          LocalPrivateCacheCodec.offlineFilesPreferenceKey: (
            LocalPrivateCacheCodec.offlineFilesNamespace,
            '[{"objectKey":"opaque/object-123","localPath":'
                '"C:\\\\Private\\\\contract.pdf"}]',
          ),
          LocalPrivateCacheCodec.offlineFoldersPreferenceKey: (
            LocalPrivateCacheCodec.offlineFoldersNamespace,
            '[{"folderKey":"folder-123","localPath":"C:\\\\Private"}]',
          ),
          LocalPrivateCacheCodec.offlineDirectoryPreferenceKey: (
            LocalPrivateCacheCodec.offlineDirectoryNamespace,
            r'C:\Private\RonikDrive Offline',
          ),
        };

        for (final entry in values.entries) {
          await cache.write(
            baseKey: entry.key,
            namespace: entry.value.$1,
            value: entry.value.$2,
          );
          final stored = prefs.getString(
            LocalPrivateCachePreferences.scopedPreferenceKey(
              entry.key,
              uid,
              scope: scope,
            ),
          );
          expect(stored, startsWith(LocalPrivateCacheCodec.encryptedPrefix));
          expect(stored, isNot(contains('Private')));
          expect(stored, isNot(contains('contract.pdf')));
          expect(stored, isNot(contains('object-123')));
          expect(stored, isNot(contains('acquisition.pdf')));
          expect(stored, isNot(contains('Board and Finance')));
          final opened = await cache.read(
            baseKey: entry.key,
            namespace: entry.value.$1,
          );
          expect(opened.value, entry.value.$2);
        }
      },
    );

    test(
      'discards tampered ciphertext without returning any plaintext',
      () async {
        const baseKey = 'workspace_backup_configs_v1';
        const uid = 'alice';
        final prefs = await SharedPreferences.getInstance();
        final codec = LocalPrivateCacheCodec(keyStore: _MemoryKeyStore());
        final cache = LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          codec: codec,
        );
        await cache.write(
          baseKey: baseKey,
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
          value: '[{"path":"/home/alice"}]',
        );
        final primary = LocalPrivateCachePreferences.scopedPreferenceKey(
          baseKey,
          uid,
        );
        final protected = prefs.getString(primary)!;
        await prefs.setString(primary, _tamperCiphertext(protected));

        final read = await cache.read(
          baseKey: baseKey,
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
        );

        expect(read.value, isNull);
        expect(read.discardedCorruptValue, isTrue);
        expect(prefs.containsKey(primary), isFalse);
      },
    );

    test(
      'retains encrypted state when the keychain is temporarily unavailable',
      () async {
        const baseKey = 'workspace_backup_configs_v1';
        const uid = 'alice';
        final prefs = await SharedPreferences.getInstance();
        final store = _MemoryKeyStore();
        final writer = LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          codec: LocalPrivateCacheCodec(keyStore: store),
        );
        await writer.write(
          baseKey: baseKey,
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
          value: '[{"path":"/home/alice"}]',
        );
        store.failReads = true;
        final reader = LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          codec: LocalPrivateCacheCodec(keyStore: store),
        );

        final read = await reader.read(
          baseKey: baseKey,
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
        );

        expect(read.value, isNull);
        expect(read.temporarilyUnavailable, isTrue);
        expect(
          prefs.getString(
            LocalPrivateCachePreferences.scopedPreferenceKey(baseKey, uid),
          ),
          startsWith(LocalPrivateCacheCodec.encryptedPrefix),
        );
      },
    );

    test(
      'removes legacy plaintext if secure protection cannot be created',
      () async {
        const baseKey = 'workspace_backup_configs_v1';
        const uid = 'alice';
        SharedPreferences.setMockInitialValues(<String, Object>{
          baseKey: '[{"path":"/home/alice"}]',
        });
        final prefs = await SharedPreferences.getInstance();
        final store = _MemoryKeyStore()..failWrites = true;
        final cache = LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          codec: LocalPrivateCacheCodec(keyStore: store),
        );

        final read = await cache.read(
          baseKey: baseKey,
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
        );

        expect(read.value, isNull);
        expect(read.discardedCorruptValue, isTrue);
        expect(prefs.containsKey(baseKey), isFalse);
      },
    );

    test(
      'failed cache writes remove legacy plaintext but retain encrypted state',
      () async {
        const uid = 'alice';
        const plaintextKey = LocalPrivateCacheCodec.cachedFilesPreferenceKey;
        const encryptedKey = LocalPrivateCacheCodec.cachedFoldersPreferenceKey;
        const scope = 'production-project';
        final store = _MemoryKeyStore();
        SharedPreferences.setMockInitialValues(<String, Object>{
          '${plaintextKey}_$uid': '[{"name":"Readable secret.pdf"}]',
        });
        final prefs = await SharedPreferences.getInstance();
        final writer = LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          scope: scope,
          codec: LocalPrivateCacheCodec(keyStore: store),
        );
        await writer.write(
          baseKey: encryptedKey,
          namespace: LocalPrivateCacheCodec.cachedFoldersNamespace,
          value: '[{"name":"Protected folder"}]',
        );
        final encryptedPreference =
            LocalPrivateCachePreferences.scopedPreferenceKey(
              encryptedKey,
              uid,
              scope: scope,
            );
        final protectedValue = prefs.getString(encryptedPreference);
        expect(
          protectedValue,
          startsWith(LocalPrivateCacheCodec.encryptedPrefix),
        );

        store.failReads = true;
        final blockedWriter = LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          scope: scope,
          codec: LocalPrivateCacheCodec(keyStore: store),
        );
        await expectLater(
          blockedWriter.write(
            baseKey: plaintextKey,
            namespace: LocalPrivateCacheCodec.cachedFilesNamespace,
            value: '[{"name":"New secret.pdf"}]',
          ),
          throwsA(isA<LocalPrivateCacheException>()),
        );
        await expectLater(
          blockedWriter.write(
            baseKey: encryptedKey,
            namespace: LocalPrivateCacheCodec.cachedFoldersNamespace,
            value: '[{"name":"Replacement folder"}]',
          ),
          throwsA(isA<LocalPrivateCacheException>()),
        );

        expect(prefs.containsKey('${plaintextKey}_$uid'), isFalse);
        expect(prefs.getString(encryptedPreference), protectedValue);
      },
    );

    test('purges encrypted preferences and the account key', () async {
      const uid = 'alice';
      final prefs = await SharedPreferences.getInstance();
      final store = _MemoryKeyStore();
      final codec = LocalPrivateCacheCodec(keyStore: store);
      final cache = LocalPrivateCachePreferences(
        preferences: prefs,
        uid: uid,
        codec: codec,
      );
      for (final entry
          in LocalPrivateCacheCodec.protectedPreferenceNamespaces.entries) {
        await cache.write(
          baseKey: entry.key,
          namespace: entry.value,
          value: '{"private":"${entry.key}"}',
        );
      }

      await cache.purge(
        LocalPrivateCacheCodec.protectedPreferenceNamespaces.keys,
        forgetKey: true,
      );

      for (final baseKey
          in LocalPrivateCacheCodec.protectedPreferenceNamespaces.keys) {
        expect(
          prefs.containsKey(
            LocalPrivateCachePreferences.scopedPreferenceKey(baseKey, uid),
          ),
          isFalse,
        );
      }
      expect(store.values, isEmpty);
    });
  });
}
