import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LocalPrivateCacheFailure {
  invalidInput,
  keyUnavailable,
  corruptPayload,
  storageFailure,
}

class LocalPrivateCacheException implements Exception {
  const LocalPrivateCacheException(this.failure, this.message);

  final LocalPrivateCacheFailure failure;
  final String message;

  @override
  String toString() => 'LocalPrivateCacheException: $message';
}

class LocalPrivateCacheValue {
  const LocalPrivateCacheValue({
    required this.plaintext,
    required this.needsMigration,
  });

  final String plaintext;
  final bool needsMigration;
}

class LocalPrivateCachePreferenceRead {
  const LocalPrivateCachePreferenceRead({
    this.value,
    this.decodedRows,
    this.migrated = false,
    this.discardedCorruptValue = false,
    this.temporarilyUnavailable = false,
  });

  final String? value;
  final List<Map<String, dynamic>>? decodedRows;
  final bool migrated;
  final bool discardedCorruptValue;
  final bool temporarilyUnavailable;
}

abstract class LocalPrivateCacheKeyStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureStorageLocalPrivateCacheKeyStore
    implements LocalPrivateCacheKeyStore {
  SecureStorageLocalPrivateCacheKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Authenticated, account-scoped encryption for sensitive device-local state.
///
/// The random AES-256 key is held by the platform keychain/credential store.
/// The account UID and cache namespace are authenticated as additional data,
/// so ciphertext cannot be copied between accounts or cache purposes.
class LocalPrivateCacheCodec {
  LocalPrivateCacheCodec({
    LocalPrivateCacheKeyStore? keyStore,
    AesGcm? algorithm,
  }) : _keyStore = keyStore ?? SecureStorageLocalPrivateCacheKeyStore(),
       _algorithm = algorithm ?? AesGcm.with256bits();

  static final LocalPrivateCacheCodec instance = LocalPrivateCacheCodec();

  static const String encryptedPrefix = 'lpc1--';
  static const String backupConfigsPreferenceKey =
      'workspace_backup_configs_v1';
  static const String backupFingerprintsPreferenceKey =
      'workspace_backup_signatures_v1';
  static const String transferJournalPreferenceKey = 'transfer_journal_v1';
  static const String desktopDrivePreferenceKey = 'desktop_drive_settings_v1';
  static const String desktopDriveStatusPreferenceKey =
      'desktop_drive_status_v1';
  static const String desktopDriveNamespace = 'desktop-drive-settings-v1';
  static const String desktopDriveStatusNamespace = 'desktop-drive-status-v1';
  static const String cachedFilesPreferenceKey = 'workspace_cached_files_v1';
  static const String cachedFoldersPreferenceKey =
      'workspace_cached_folders_v1';
  static const String offlineFilesPreferenceKey = 'workspace_offline_files_v1';
  static const String offlineFoldersPreferenceKey =
      'workspace_offline_folder_configs_v1';
  static const String offlineDirectoryPreferenceKey =
      'workspace_offline_directory_path_v1';
  static const String businessReconciliationPreferenceKey =
      'business_reconciliation_checkpoints_v1';
  static const String businessReconciliationQueuePreferenceKey =
      'business_reconciliation_queue_v1';
  static const String backupConfigsNamespace = 'backup-configs-v1';
  static const String backupFingerprintsNamespace = 'backup-fingerprints-v1';
  static const String transferJournalNamespace = 'transfer-journal-v1';
  static const String cachedFilesNamespace = 'cached-files-v1';
  static const String cachedFoldersNamespace = 'cached-folders-v1';
  static const String offlineFilesNamespace = 'offline-files-v1';
  static const String offlineFoldersNamespace = 'offline-folders-v1';
  static const String offlineDirectoryNamespace = 'offline-directory-v1';
  static const String businessReconciliationNamespace =
      'business-reconciliation-v1';
  static const String businessReconciliationQueueNamespace =
      'business-reconciliation-queue-v1';
  static const Map<String, String> protectedPreferenceNamespaces =
      <String, String>{
        backupConfigsPreferenceKey: backupConfigsNamespace,
        backupFingerprintsPreferenceKey: backupFingerprintsNamespace,
        transferJournalPreferenceKey: transferJournalNamespace,
        desktopDrivePreferenceKey: desktopDriveNamespace,
        desktopDriveStatusPreferenceKey: desktopDriveStatusNamespace,
        cachedFilesPreferenceKey: cachedFilesNamespace,
        cachedFoldersPreferenceKey: cachedFoldersNamespace,
        offlineFilesPreferenceKey: offlineFilesNamespace,
        offlineFoldersPreferenceKey: offlineFoldersNamespace,
        offlineDirectoryPreferenceKey: offlineDirectoryNamespace,
        businessReconciliationPreferenceKey: businessReconciliationNamespace,
        businessReconciliationQueuePreferenceKey:
            businessReconciliationQueueNamespace,
      };
  static const int maxPlaintextBytes = 16 * 1024 * 1024;

  final LocalPrivateCacheKeyStore _keyStore;
  final AesGcm _algorithm;
  final Map<String, SecretKey> _memoryKeys = <String, SecretKey>{};
  final Map<String, Future<SecretKey?>> _pendingKeyLoads =
      <String, Future<SecretKey?>>{};

  bool isEncrypted(String value) => value.startsWith(encryptedPrefix);

  Future<String> seal({
    required String uid,
    required String namespace,
    required String plaintext,
  }) async {
    final normalizedUid = _validateContext(uid, 'account');
    final normalizedNamespace = _validateContext(namespace, 'namespace');
    final plaintextBytes = utf8.encode(plaintext);
    if (plaintextBytes.length > maxPlaintextBytes) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.invalidInput,
        'The private cache value is too large.',
      );
    }

    final key = await _keyFor(normalizedUid, createIfMissing: true);
    if (key == null) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.keyUnavailable,
        'The private cache key is unavailable.',
      );
    }

    try {
      final box = await _algorithm.encrypt(
        plaintextBytes,
        secretKey: key,
        aad: _additionalData(normalizedUid, normalizedNamespace),
      );
      final payload = Uint8List(
        box.nonce.length + box.cipherText.length + box.mac.bytes.length,
      );
      var offset = 0;
      payload.setAll(offset, box.nonce);
      offset += box.nonce.length;
      payload.setAll(offset, box.cipherText);
      offset += box.cipherText.length;
      payload.setAll(offset, box.mac.bytes);
      return '$encryptedPrefix'
          '${base64Url.encode(payload).replaceAll('=', '')}';
    } on LocalPrivateCacheException {
      rethrow;
    } catch (_) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.storageFailure,
        'The private cache value could not be protected.',
      );
    }
  }

  Future<LocalPrivateCacheValue> open({
    required String uid,
    required String namespace,
    required String value,
  }) async {
    final normalizedUid = _validateContext(uid, 'account');
    final normalizedNamespace = _validateContext(namespace, 'namespace');
    if (!value.startsWith(encryptedPrefix)) {
      if (value.startsWith('lpc')) {
        throw const LocalPrivateCacheException(
          LocalPrivateCacheFailure.corruptPayload,
          'The private cache format is unsupported.',
        );
      }
      return LocalPrivateCacheValue(plaintext: value, needsMigration: true);
    }

    final key = await _keyFor(normalizedUid, createIfMissing: false);
    if (key == null) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.keyUnavailable,
        'The private cache key is unavailable.',
      );
    }

    try {
      var encoded = value.substring(encryptedPrefix.length);
      final maximumEncodedLength =
          ((maxPlaintextBytes +
                      _algorithm.nonceLength +
                      _algorithm.macAlgorithm.macLength) *
                  4 /
                  3)
              .ceil() +
          4;
      if (encoded.length > maximumEncodedLength) {
        throw const FormatException('Private cache payload is too large.');
      }
      while (encoded.length % 4 != 0) {
        encoded += '=';
      }
      final payload = base64Url.decode(encoded);
      final nonceLength = _algorithm.nonceLength;
      final macLength = _algorithm.macAlgorithm.macLength;
      if (payload.length < nonceLength + macLength) {
        throw const FormatException('Private cache payload is too short.');
      }
      if (payload.length > maxPlaintextBytes + nonceLength + macLength) {
        throw const FormatException('Private cache payload is too large.');
      }

      final box = SecretBox(
        payload.sublist(nonceLength, payload.length - macLength),
        nonce: payload.sublist(0, nonceLength),
        mac: Mac(payload.sublist(payload.length - macLength)),
      );
      final plaintext = await _algorithm.decrypt(
        box,
        secretKey: key,
        aad: _additionalData(normalizedUid, normalizedNamespace),
      );
      return LocalPrivateCacheValue(
        plaintext: utf8.decode(plaintext),
        needsMigration: false,
      );
    } on LocalPrivateCacheException {
      rethrow;
    } catch (_) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.corruptPayload,
        'The private cache value could not be authenticated.',
      );
    }
  }

  Future<void> forgetAccount(String uid) async {
    final normalizedUid = _validateContext(uid, 'account');
    final keyName = _keyName(normalizedUid);
    _memoryKeys.remove(keyName);
    _pendingKeyLoads.remove(keyName);
    try {
      await _keyStore.delete(keyName);
    } catch (_) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.storageFailure,
        'The private cache key could not be removed.',
      );
    }
  }

  Future<SecretKey?> _keyFor(
    String uid, {
    required bool createIfMissing,
  }) async {
    final keyName = _keyName(uid);
    final cached = _memoryKeys[keyName];
    if (cached != null) {
      return cached;
    }
    final pending = _pendingKeyLoads[keyName];
    if (pending != null) {
      final pendingKey = await pending;
      if (pendingKey != null || !createIfMissing) {
        return pendingKey;
      }
      if (identical(_pendingKeyLoads[keyName], pending)) {
        _pendingKeyLoads.remove(keyName);
      }
      return _keyFor(uid, createIfMissing: true);
    }

    late final Future<SecretKey?> operation;
    operation = _loadKey(keyName, createIfMissing: createIfMissing)
        .whenComplete(() {
          if (identical(_pendingKeyLoads[keyName], operation)) {
            _pendingKeyLoads.remove(keyName);
          }
        });
    _pendingKeyLoads[keyName] = operation;
    return operation;
  }

  Future<SecretKey?> _loadKey(
    String keyName, {
    required bool createIfMissing,
  }) async {
    try {
      final stored = await _keyStore.read(keyName);
      if (stored != null && stored.trim().isNotEmpty) {
        final key = _decodeKey(stored);
        _memoryKeys[keyName] = key;
        return key;
      }
      if (!createIfMissing) {
        return null;
      }

      final generated = await _algorithm.newSecretKey();
      final generatedBytes = await generated.extractBytes();
      final encoded = base64Url.encode(generatedBytes).replaceAll('=', '');
      await _keyStore.write(keyName, encoded);

      // Re-read after writing so this isolate follows any concurrently
      // persisted winner rather than assuming its generated value won.
      final persisted = await _keyStore.read(keyName);
      final key = _decodeKey(persisted ?? encoded);
      _memoryKeys[keyName] = key;
      return key;
    } on LocalPrivateCacheException {
      rethrow;
    } catch (_) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.keyUnavailable,
        'The private cache key is unavailable.',
      );
    }
  }

  SecretKey _decodeKey(String encodedKey) {
    try {
      var normalized = encodedKey.trim();
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final bytes = base64Url.decode(normalized);
      if (bytes.length != 32) {
        throw const FormatException('AES-256 keys use 32 bytes.');
      }
      return SecretKey(bytes);
    } catch (_) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.keyUnavailable,
        'The private cache key is invalid.',
      );
    }
  }

  String _validateContext(String value, String label) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 256) {
      throw LocalPrivateCacheException(
        LocalPrivateCacheFailure.invalidInput,
        'A valid private cache $label is required.',
      );
    }
    return normalized;
  }

  String _keyName(String uid) {
    final accountHash = crypto.sha256.convert(utf8.encode(uid)).toString();
    return 'ronikdrive_local_private_cache_key_v1_$accountHash';
  }

  List<int> _additionalData(String uid, String namespace) {
    return utf8.encode('ronikdrive-local-private-cache-v1\n$uid\n$namespace');
  }
}

/// Stores encrypted private-cache values without putting account identifiers
/// or plaintext paths into preference keys or values.
class LocalPrivateCachePreferences {
  LocalPrivateCachePreferences({
    required SharedPreferences preferences,
    required String uid,
    String scope = '',
    LocalPrivateCacheCodec? codec,
  }) : _preferences = preferences,
       _uid = uid.trim(),
       _scope = scope.trim(),
       _codec = codec ?? LocalPrivateCacheCodec.instance {
    if (_uid.isEmpty) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.invalidInput,
        'A valid private cache account is required.',
      );
    }
  }

  final SharedPreferences _preferences;
  final String _uid;
  final String _scope;
  final LocalPrivateCacheCodec _codec;

  String get _accountContext => _scope.isEmpty ? _uid : '$_scope\n$_uid';

  Future<LocalPrivateCachePreferenceRead> read({
    required String baseKey,
    required String namespace,
  }) async {
    final keys = _candidateKeys(baseKey);
    String? sourceKey;
    String? storedValue;
    var invalidStoredType = false;
    for (final key in keys) {
      final value = _preferences.get(key);
      if (value == null) {
        continue;
      }
      sourceKey = key;
      if (value is String) {
        storedValue = value;
      } else {
        invalidStoredType = true;
      }
      break;
    }
    if (sourceKey == null) {
      return const LocalPrivateCachePreferenceRead();
    }
    if (invalidStoredType || storedValue == null) {
      await _removeKeys(keys);
      return const LocalPrivateCachePreferenceRead(discardedCorruptValue: true);
    }

    final legacyHashedKey = scopedPreferenceKey(baseKey, _uid);
    final sourceAccountContext =
        _scope.isNotEmpty && sourceKey == legacyHashedKey
        ? _uid
        : _accountContext;
    LocalPrivateCacheValue opened;
    try {
      opened = await _codec.open(
        uid: sourceAccountContext,
        namespace: namespace,
        value: storedValue,
      );
    } on LocalPrivateCacheException catch (error) {
      if (error.failure == LocalPrivateCacheFailure.corruptPayload ||
          error.failure == LocalPrivateCacheFailure.invalidInput) {
        await _removeKeys(keys);
        return const LocalPrivateCachePreferenceRead(
          discardedCorruptValue: true,
        );
      }
      if (!_codec.isEncrypted(storedValue)) {
        // Never retain a legacy plaintext path/hash after a protection failure.
        await _removeKeys(keys);
        return const LocalPrivateCachePreferenceRead(
          discardedCorruptValue: true,
        );
      }
      return const LocalPrivateCachePreferenceRead(
        temporarilyUnavailable: true,
      );
    }

    final primaryKey = scopedPreferenceKey(baseKey, _uid, scope: _scope);
    if (opened.needsMigration || sourceAccountContext != _accountContext) {
      try {
        final protected = await _codec.seal(
          uid: _accountContext,
          namespace: namespace,
          plaintext: opened.plaintext,
        );
        await _replace(primaryKey, protected, keys);
        if (sourceAccountContext != _accountContext) {
          try {
            await _codec.forgetAccount(sourceAccountContext);
          } catch (_) {
            // The migrated preference no longer references the legacy key.
            // Account cleanup retries removal of both key generations.
          }
        }
        return LocalPrivateCachePreferenceRead(
          value: opened.plaintext,
          migrated: true,
        );
      } catch (_) {
        await _removeKeys(keys);
        return const LocalPrivateCachePreferenceRead(
          discardedCorruptValue: true,
        );
      }
    }

    if (sourceKey != primaryKey) {
      try {
        await _replace(primaryKey, storedValue, keys);
      } catch (_) {
        // The value is already encrypted. It remains safe and readable from
        // the older key location, so a later read can retry the move.
      }
    }
    return LocalPrivateCachePreferenceRead(value: opened.plaintext);
  }

  Future<void> write({
    required String baseKey,
    required String namespace,
    required String? value,
  }) async {
    final keys = _candidateKeys(baseKey);
    if (value == null) {
      await _removeKeys(keys);
      return;
    }
    late final String protected;
    try {
      protected = await _codec.seal(
        uid: _accountContext,
        namespace: namespace,
        plaintext: value,
      );
    } catch (error, stackTrace) {
      try {
        await _removeUnprotectedKeys(keys);
      } catch (_) {
        // Preserve the protection failure. A later read repeats the same
        // fail-closed plaintext cleanup before returning any cached value.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _replace(
      scopedPreferenceKey(baseKey, _uid, scope: _scope),
      protected,
      keys,
    );
  }

  Future<void> purge(
    Iterable<String> baseKeys, {
    bool forgetKey = false,
  }) async {
    Object? removalError;
    StackTrace? removalStackTrace;
    try {
      for (final baseKey in baseKeys) {
        await _removeKeys(_candidateKeys(baseKey));
      }
    } catch (error, stackTrace) {
      removalError = error;
      removalStackTrace = stackTrace;
    } finally {
      if (forgetKey) {
        Object? keyRemovalError;
        StackTrace? keyRemovalStackTrace;
        try {
          await _codec.forgetAccount(_accountContext);
        } catch (error, stackTrace) {
          keyRemovalError = error;
          keyRemovalStackTrace = stackTrace;
        }
        if (_scope.isNotEmpty) {
          try {
            await _codec.forgetAccount(_uid);
          } catch (error, stackTrace) {
            keyRemovalError ??= error;
            keyRemovalStackTrace ??= stackTrace;
          }
        }
        if (keyRemovalError != null) {
          Error.throwWithStackTrace(keyRemovalError, keyRemovalStackTrace!);
        }
      }
    }
    if (removalError != null) {
      Error.throwWithStackTrace(removalError, removalStackTrace!);
    }
  }

  static String scopedPreferenceKey(
    String baseKey,
    String uid, {
    String scope = '',
  }) {
    final normalizedBase = baseKey.trim();
    final normalizedUid = uid.trim();
    if (normalizedBase.isEmpty || normalizedUid.isEmpty) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.invalidInput,
        'Private cache preference identifiers must be non-empty.',
      );
    }
    final normalizedScope = scope.trim();
    final accountContext = normalizedScope.isEmpty
        ? normalizedUid
        : '$normalizedScope\n$normalizedUid';
    final accountHash = crypto.sha256
        .convert(utf8.encode(accountContext))
        .toString()
        .substring(0, 32);
    return '${normalizedBase}_account_$accountHash';
  }

  List<String> _candidateKeys(String baseKey) {
    final normalizedBase = baseKey.trim();
    if (normalizedBase.isEmpty) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.invalidInput,
        'A private cache preference key is required.',
      );
    }
    final legacySafeUid = _uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final primaryKey = scopedPreferenceKey(normalizedBase, _uid, scope: _scope);
    final uidOnlyHashedKey = scopedPreferenceKey(normalizedBase, _uid);
    return <String>[
      primaryKey,
      if (uidOnlyHashedKey != primaryKey) uidOnlyHashedKey,
      if (_uid != legacySafeUid) '${normalizedBase}_$_uid',
      '${normalizedBase}_$legacySafeUid',
      normalizedBase,
    ];
  }

  Future<void> _replace(
    String primaryKey,
    String value,
    Iterable<String> keys,
  ) async {
    final saved = await _preferences.setString(primaryKey, value);
    if (!saved) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.storageFailure,
        'The private cache preference could not be saved.',
      );
    }
    for (final key in keys) {
      if (key != primaryKey) {
        await _preferences.remove(key);
      }
    }
  }

  Future<void> _removeKeys(Iterable<String> keys) async {
    for (final key in keys) {
      await _preferences.remove(key);
    }
  }

  Future<void> _removeUnprotectedKeys(Iterable<String> keys) async {
    for (final key in keys) {
      final stored = _preferences.get(key);
      if (stored == null || (stored is String && _codec.isEncrypted(stored))) {
        continue;
      }
      await _preferences.remove(key);
    }
  }
}
