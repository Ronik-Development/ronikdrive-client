import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_storage/src/privacy/local_private_cache.dart';
import 'package:cloud_storage/src/security/business_reconciliation_checkpoint.dart';

class _MemoryKeyStore implements LocalPrivateCacheKeyStore {
  final Map<String, String> values = <String, String>{};
  bool failReads = false;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    if (failReads) {
      throw StateError('credential store unavailable');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

String _fingerprint(String character) =>
    List<String>.filled(64, character).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores resumable Business progress only as encrypted state', () async {
    const uid = 'member-a';
    const scope = 'ronikdrive-production';
    final preferences = await SharedPreferences.getInstance();
    final keyStore = _MemoryKeyStore();
    final codec = LocalPrivateCacheCodec(keyStore: keyStore);
    final cache = LocalPrivateCachePreferences(
      preferences: preferences,
      uid: uid,
      scope: scope,
      codec: codec,
    );
    final store = BusinessReconciliationCheckpointStore(privateCache: cache);
    final checkpoint =
        BusinessReconciliationCheckpoint.start(
            companyId: 'company-secret',
            storageScope: 'group',
            groupId: 'legal-team',
            recipientFingerprint: _fingerprint('a'),
            startedAt: DateTime.utc(2026, 7, 24),
          )
          ..markFileComplete('opaque-file-id', rotated: 1, cleanupPending: 1)
          ..markFolderComplete('opaque-folder-id', refreshed: 1)
          ..markMetadataComplete(const <String>[
            'opaque-file-id',
          ], protectedCount: 1);

    await store.save(checkpoint);

    final preferenceKey = LocalPrivateCachePreferences.scopedPreferenceKey(
      LocalPrivateCacheCodec.businessReconciliationPreferenceKey,
      uid,
      scope: scope,
    );
    final stored = preferences.getString(preferenceKey);
    expect(stored, startsWith(LocalPrivateCacheCodec.encryptedPrefix));
    expect(stored, isNot(contains('company-secret')));
    expect(stored, isNot(contains('legal-team')));
    expect(stored, isNot(contains('opaque-file-id')));
    expect(stored, isNot(contains('opaque-folder-id')));

    final reopened = BusinessReconciliationCheckpointStore(
      privateCache: LocalPrivateCachePreferences(
        preferences: preferences,
        uid: uid,
        scope: scope,
        codec: LocalPrivateCacheCodec(keyStore: keyStore),
      ),
    );
    final loaded = await reopened.load();
    expect(loaded.temporarilyUnavailable, isFalse);
    expect(loaded.discardedCorruptValue, isFalse);
    expect(loaded.checkpoints, hasLength(1));
    final restored = loaded.checkpoints.single;
    expect(restored.isFileComplete('opaque-file-id'), isTrue);
    expect(restored.isFileComplete('pending-file-id'), isFalse);
    expect(restored.isFolderComplete('opaque-folder-id'), isTrue);
    expect(restored.isMetadataFileComplete('opaque-file-id'), isTrue);
    expect(restored.rotatedFiles, 1);
    expect(restored.cleanupPendingFiles, 1);
    expect(restored.refreshedFolders, 1);
    expect(restored.protectedFileMetadata, 1);

    restored.markFileComplete('opaque-file-id', rotated: 1);
    expect(restored.rotatedFiles, 1);
    restored.markFileComplete('pending-file-id', refreshed: 1);
    await reopened.save(restored);
    final resumedAgain = (await reopened.load()).checkpoints.single;
    expect(resumedAgain.isFileComplete('pending-file-id'), isTrue);
    expect(resumedAgain.refreshedFiles, 1);
  });

  test(
    'keeps independent checkpoints and removes only one workspace',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final store = BusinessReconciliationCheckpointStore(
        privateCache: LocalPrivateCachePreferences(
          preferences: preferences,
          uid: 'member-a',
          codec: LocalPrivateCacheCodec(keyStore: _MemoryKeyStore()),
        ),
      );
      final shared = BusinessReconciliationCheckpoint.start(
        companyId: 'company-a',
        storageScope: 'company_shared',
        groupId: null,
        recipientFingerprint: _fingerprint('b'),
      );
      final group = BusinessReconciliationCheckpoint.start(
        companyId: 'company-a',
        storageScope: 'group',
        groupId: 'group-a',
        recipientFingerprint: _fingerprint('c'),
      );
      await store.save(shared);
      await store.save(group);

      await store.remove(shared.workspaceKey);
      final loaded = await store.load();

      expect(loaded.checkpoints, hasLength(1));
      expect(loaded.checkpoints.single.workspaceKey, group.workspaceKey);
    },
  );

  test('recipient changes invalidate an old resume checkpoint', () {
    final checkpoint = BusinessReconciliationCheckpoint.start(
      companyId: 'company-a',
      storageScope: 'group',
      groupId: 'group-a',
      recipientFingerprint: _fingerprint('d'),
    );

    expect(
      checkpoint.matches(
        companyId: 'company-a',
        storageScope: 'group',
        groupId: 'group-a',
        recipientFingerprint: _fingerprint('d'),
      ),
      isTrue,
    );
    expect(
      checkpoint.matches(
        companyId: 'company-a',
        storageScope: 'group',
        groupId: 'group-a',
        recipientFingerprint: _fingerprint('e'),
      ),
      isFalse,
    );
  });

  test(
    'logical corruption is discarded without returning identifiers',
    () async {
      const uid = 'member-a';
      final preferences = await SharedPreferences.getInstance();
      final keyStore = _MemoryKeyStore();
      final codec = LocalPrivateCacheCodec(keyStore: keyStore);
      final cache = LocalPrivateCachePreferences(
        preferences: preferences,
        uid: uid,
        codec: codec,
      );
      await cache.write(
        baseKey: LocalPrivateCacheCodec.businessReconciliationPreferenceKey,
        namespace: LocalPrivateCacheCodec.businessReconciliationNamespace,
        value:
            '{"version":1,"checkpoints":[{"companyId":"should-not-return"}]}',
      );

      final loaded = await BusinessReconciliationCheckpointStore(
        privateCache: cache,
      ).load();

      expect(loaded.checkpoints, isEmpty);
      expect(loaded.discardedCorruptValue, isTrue);
      expect(
        preferences.containsKey(
          LocalPrivateCachePreferences.scopedPreferenceKey(
            LocalPrivateCacheCodec.businessReconciliationPreferenceKey,
            uid,
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'retains encrypted checkpoint when the credential store is locked',
    () async {
      const uid = 'member-a';
      final preferences = await SharedPreferences.getInstance();
      final keyStore = _MemoryKeyStore();
      final writer = BusinessReconciliationCheckpointStore(
        privateCache: LocalPrivateCachePreferences(
          preferences: preferences,
          uid: uid,
          codec: LocalPrivateCacheCodec(keyStore: keyStore),
        ),
      );
      await writer.save(
        BusinessReconciliationCheckpoint.start(
          companyId: 'company-a',
          storageScope: 'company_shared',
          groupId: null,
          recipientFingerprint: _fingerprint('f'),
        ),
      );
      keyStore.failReads = true;

      final loaded = await BusinessReconciliationCheckpointStore(
        privateCache: LocalPrivateCachePreferences(
          preferences: preferences,
          uid: uid,
          codec: LocalPrivateCacheCodec(keyStore: keyStore),
        ),
      ).load();

      expect(loaded.temporarilyUnavailable, isTrue);
      expect(loaded.checkpoints, isEmpty);
      expect(
        preferences.getString(
          LocalPrivateCachePreferences.scopedPreferenceKey(
            LocalPrivateCacheCodec.businessReconciliationPreferenceKey,
            uid,
          ),
        ),
        startsWith(LocalPrivateCacheCodec.encryptedPrefix),
      );
    },
  );
}
