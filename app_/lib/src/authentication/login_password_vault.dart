import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RestoredLoginCredentials {
  const RestoredLoginCredentials({required this.email, required this.password});

  final String? email;
  final String? password;
}

/// Keeps the current login password in memory only so the app can derive the
/// default device-encryption key during the active app session. The derived
/// standard encryption key is stored separately so restored Firebase sessions
/// can still open standard encrypted files without storing the login password.
class LoginPasswordVault {
  LoginPasswordVault._();

  static final LoginPasswordVault instance = LoginPasswordVault._();

  static const String _emailKey = 'ronikdrive_login_email_v1';
  static const String _passwordKey = 'ronikdrive_login_password_v1';
  static const String _standardEncryptionKeyKey =
      'ronikdrive_standard_encryption_key_v1';
  static const String _standardEncryptionSaltKey =
      'ronikdrive_standard_encryption_salt_v1';
  static const String _standardEncryptionEmailKey =
      'ronikdrive_standard_encryption_email_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );

  final FlutterSecureStorage _legacyStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  String? _email;
  String? _password;
  String? _standardEncryptionKey;
  String? _standardEncryptionSalt;
  String? _standardEncryptionEmail;
  bool _restoreAttempted = false;
  Future<void>? _restoreOperation;

  String? get email => _email;

  /// Background native providers must observe logout/key removal performed by
  /// another process. Do not satisfy this check from the in-memory key cache.
  Future<bool> matchesPersistedStandardKey({
    required String? expectedEmail,
    required String expectedKey,
  }) async {
    try {
      final storedEmail = await _storage.read(key: _standardEncryptionEmailKey);
      final storedKey = await _storage.read(key: _standardEncryptionKeyKey);
      return storedKey != null &&
          storedKey == expectedKey &&
          _normaliseEmail(storedEmail) == _normaliseEmail(expectedEmail);
    } catch (_) {
      return false;
    }
  }

  String? get password => _password;

  /// Stores the current account identity and caches the login password in memory.
  void store({String? email, required String password}) {
    if (password.isEmpty) {
      clear();
      return;
    }

    final normalisedEmail = _normaliseEmail(email);
    final previousEmail = _email;
    _email = normalisedEmail;
    _password = password;
    _restoreAttempted = true;

    if (previousEmail != null &&
        normalisedEmail != null &&
        previousEmail != normalisedEmail) {
      _standardEncryptionKey = null;
      _standardEncryptionSalt = null;
      _standardEncryptionEmail = null;
    }

    unawaited(_persistEmailAndPurgePassword(normalisedEmail: normalisedEmail));
  }

  /// Restores the in-memory login password for the expected account.
  Future<String?> restore({String? expectedEmail}) async {
    await _ensureRestored();

    if (_password == null || _password!.isEmpty) {
      return null;
    }

    if (expectedEmail == null) {
      return _password;
    }

    final desiredEmail = _normaliseEmail(expectedEmail);
    if (desiredEmail == null) {
      return _password;
    }

    if (_email == null) {
      _email = desiredEmail;
      unawaited(_persistEmailAndPurgePassword(normalisedEmail: desiredEmail));
      return _password;
    }

    return _email == desiredEmail ? _password : null;
  }

  Future<RestoredLoginCredentials> restoreCredentials({
    String? expectedEmail,
  }) async {
    if (expectedEmail == null) {
      await _ensureRestored();
      return RestoredLoginCredentials(email: _email, password: _password);
    }

    final restoredPassword = await restore(expectedEmail: expectedEmail);
    return RestoredLoginCredentials(
      email: _normaliseEmail(expectedEmail),
      password: restoredPassword,
    );
  }

  /// Restores the persisted standard encryption key for the expected account
  /// and salt. This is a file decryption key, not the login password.
  Future<String?> restoreStandardEncryptionKey({
    String? expectedEmail,
    List<int>? expectedSalt,
  }) async {
    await _ensureRestored();

    final restoredKey = _nonEmpty(_standardEncryptionKey);
    if (restoredKey == null) {
      return null;
    }

    final desiredEmail = _normaliseEmail(expectedEmail);
    final restoredEmail = _standardEncryptionEmail ?? _email;
    if (desiredEmail != null && restoredEmail != desiredEmail) {
      return null;
    }

    if (desiredEmail == null &&
        _standardEncryptionEmail != null &&
        _email != null &&
        _standardEncryptionEmail != _email) {
      return null;
    }

    if (expectedSalt != null) {
      final desiredSalt = base64Encode(expectedSalt);
      if (_standardEncryptionSalt != desiredSalt) {
        return null;
      }
    }

    return restoredKey;
  }

  void storeStandardEncryptionKey({
    String? email,
    required String key,
    required List<int> salt,
  }) {
    final normalizedKey = _nonEmpty(key);
    if (normalizedKey == null || salt.isEmpty) {
      clearStandardEncryptionKey();
      return;
    }

    final normalisedEmail = _normaliseEmail(email) ?? _email;
    final saltString = base64Encode(salt);
    _email = normalisedEmail;
    _standardEncryptionKey = normalizedKey;
    _standardEncryptionSalt = saltString;
    _standardEncryptionEmail = normalisedEmail;
    _restoreAttempted = true;

    unawaited(
      _persistStandardEncryptionKey(
        normalisedEmail: normalisedEmail,
        key: normalizedKey,
        salt: saltString,
      ),
    );
  }

  Future<void> storeStandardEncryptionKeyPersisted({
    String? email,
    required String key,
    required List<int> salt,
  }) async {
    final normalizedKey = _nonEmpty(key);
    if (normalizedKey == null || salt.isEmpty) {
      _standardEncryptionKey = null;
      _standardEncryptionSalt = null;
      _standardEncryptionEmail = null;
      await _clearPersistedStandardEncryptionKey();
      return;
    }

    final previousEmail = _email;
    final previousKey = _standardEncryptionKey;
    final previousSalt = _standardEncryptionSalt;
    final previousKeyEmail = _standardEncryptionEmail;
    final normalisedEmail = _normaliseEmail(email) ?? _email;
    final saltString = base64Encode(salt);
    _email = normalisedEmail;
    _standardEncryptionKey = normalizedKey;
    _standardEncryptionSalt = saltString;
    _standardEncryptionEmail = normalisedEmail;
    _restoreAttempted = true;
    try {
      await _persistStandardEncryptionKey(
        normalisedEmail: normalisedEmail,
        key: normalizedKey,
        salt: saltString,
        throwOnFailure: true,
      );
    } catch (_) {
      _email = previousEmail;
      _standardEncryptionKey = previousKey;
      _standardEncryptionSalt = previousSalt;
      _standardEncryptionEmail = previousKeyEmail;
      rethrow;
    }
  }

  void clearStandardEncryptionKey({bool forgetPersisted = true}) {
    _standardEncryptionKey = null;
    _standardEncryptionSalt = null;
    _standardEncryptionEmail = null;
    if (forgetPersisted) {
      unawaited(_clearPersistedStandardEncryptionKey());
    }
  }

  /// Clears any cached password information from memory and secure storage.
  void clear({bool forgetPersisted = true}) {
    _email = null;
    _password = null;
    _standardEncryptionKey = null;
    _standardEncryptionSalt = null;
    _standardEncryptionEmail = null;
    _restoreOperation = null;
    _restoreAttempted = forgetPersisted;

    if (forgetPersisted) {
      unawaited(_clearPersisted());
    }
  }

  Future<void> _ensureRestored() {
    if (_restoreAttempted) {
      return _restoreOperation ?? Future<void>.value();
    }

    final existing = _restoreOperation;
    if (existing != null) {
      return existing;
    }

    final future = _restoreFromStorage().whenComplete(() {
      _restoreAttempted = true;
      _restoreOperation = null;
    });
    _restoreOperation = future;
    return future;
  }

  Future<void> _persistEmailAndPurgePassword({String? normalisedEmail}) async {
    try {
      if (normalisedEmail != null) {
        await _storage.write(key: _emailKey, value: normalisedEmail);
      } else {
        await _storage.delete(key: _emailKey);
      }
      await Future.wait<void>([
        _storage.delete(key: _passwordKey),
        _legacyStorage.delete(key: _emailKey),
        _legacyStorage.delete(key: _passwordKey),
      ]);
    } catch (_) {
      if (kDebugMode) {
        debugPrint('LoginPasswordVault: Email state persistence failed.');
      }
    }
  }

  Future<void> _persistStandardEncryptionKey({
    required String? normalisedEmail,
    required String key,
    required String salt,
    bool throwOnFailure = false,
  }) async {
    try {
      if (normalisedEmail != null) {
        await _storage.write(key: _emailKey, value: normalisedEmail);
        await _storage.write(
          key: _standardEncryptionEmailKey,
          value: normalisedEmail,
        );
      } else {
        await _storage.delete(key: _standardEncryptionEmailKey);
      }
      await Future.wait<void>([
        _storage.write(key: _standardEncryptionKeyKey, value: key),
        _storage.write(key: _standardEncryptionSaltKey, value: salt),
        _storage.delete(key: _passwordKey),
        _legacyStorage.delete(key: _passwordKey),
      ]);
    } catch (_) {
      if (kDebugMode) {
        debugPrint(
          'LoginPasswordVault: Standard encryption key persistence failed.',
        );
      }
      if (throwOnFailure) {
        rethrow;
      }
    }
  }

  Future<void> _clearPersisted() async {
    try {
      await Future.wait<void>([
        _storage.delete(key: _passwordKey),
        _storage.delete(key: _emailKey),
        _storage.delete(key: _standardEncryptionKeyKey),
        _storage.delete(key: _standardEncryptionSaltKey),
        _storage.delete(key: _standardEncryptionEmailKey),
        _legacyStorage.delete(key: _passwordKey),
        _legacyStorage.delete(key: _emailKey),
      ]);
    } catch (_) {
      if (kDebugMode) {
        debugPrint('LoginPasswordVault: Credential cleanup failed.');
      }
    }
  }

  Future<void> _clearPersistedStandardEncryptionKey() async {
    try {
      await Future.wait<void>([
        _storage.delete(key: _standardEncryptionKeyKey),
        _storage.delete(key: _standardEncryptionSaltKey),
        _storage.delete(key: _standardEncryptionEmailKey),
      ]);
    } catch (_) {
      if (kDebugMode) {
        debugPrint(
          'LoginPasswordVault: Standard encryption key cleanup failed.',
        );
      }
    }
  }

  Future<void> _restoreFromStorage() async {
    try {
      final storedEmail = await _storage.read(key: _emailKey);
      final legacyEmail = await _legacyStorage.read(key: _emailKey);
      final normalisedEmail =
          _normaliseEmail(storedEmail) ?? _normaliseEmail(legacyEmail);

      if (normalisedEmail != null) {
        await _persistEmailAndPurgePassword(normalisedEmail: normalisedEmail);
      } else {
        await _persistEmailAndPurgePassword();
      }

      _email = normalisedEmail;
      _password = null;
      final storedStandardKey = _nonEmpty(
        await _storage.read(key: _standardEncryptionKeyKey),
      );
      final storedStandardSalt = _nonEmpty(
        await _storage.read(key: _standardEncryptionSaltKey),
      );
      final storedStandardEmail = _normaliseEmail(
        await _storage.read(key: _standardEncryptionEmailKey),
      );
      if (normalisedEmail != null &&
          storedStandardEmail == normalisedEmail &&
          storedStandardKey != null &&
          storedStandardSalt != null) {
        _standardEncryptionKey = storedStandardKey;
        _standardEncryptionSalt = storedStandardSalt;
        _standardEncryptionEmail = storedStandardEmail;
      } else {
        _standardEncryptionKey = null;
        _standardEncryptionSalt = null;
        _standardEncryptionEmail = null;
        if (storedStandardKey != null ||
            storedStandardSalt != null ||
            storedStandardEmail != null) {
          unawaited(_clearPersistedStandardEncryptionKey());
        }
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('LoginPasswordVault: Credential restoration failed.');
      }
      _email = null;
      _password = null;
      _standardEncryptionKey = null;
      _standardEncryptionSalt = null;
      _standardEncryptionEmail = null;
    }
  }

  String? _nonEmpty(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _normaliseEmail(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.toLowerCase();
  }
}
