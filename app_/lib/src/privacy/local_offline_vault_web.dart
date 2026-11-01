import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../shared/platform_io.dart';
import 'local_private_cache.dart';

enum LocalOfflineVaultFailure {
  invalidInput,
  keyUnavailable,
  unsupportedFormat,
  corruptPayload,
  storageFailure,
}

class LocalOfflineVaultException implements Exception {
  const LocalOfflineVaultException(this.failure, this.message);

  final LocalOfflineVaultFailure failure;
  final String message;

  @override
  String toString() => 'LocalOfflineVaultException: $message';
}

class LocalOfflineVaultWriteResult {
  const LocalOfflineVaultWriteResult({
    required this.plaintextLength,
    required this.encryptedLength,
  });

  final int plaintextLength;
  final int encryptedLength;
}

/// Web builds use browser-managed downloads and do not keep native offline
/// files. This API-compatible implementation prevents accidental plaintext
/// persistence if a native-only flow is invoked on the web.
class LocalOfflineVault {
  LocalOfflineVault({
    required String uid,
    String scope = '',
    LocalPrivateCacheKeyStore? keyStore,
    AesGcm? algorithm,
    int chunkSize = defaultChunkSize,
  });

  static const String storageFormat = 'encrypted-vault-v1';
  static const String fileExtension = '.rdoffline';
  static const int defaultChunkSize = 1024 * 1024;
  static const int maximumChunkSize = 4 * 1024 * 1024;

  String opaqueFileName(String objectKey) {
    throw const LocalOfflineVaultException(
      LocalOfflineVaultFailure.storageFailure,
      'Native offline storage is unavailable in the browser.',
    );
  }

  Future<bool> isEncryptedFile(File file) async => false;

  Future<LocalOfflineVaultWriteResult> encryptFile({
    required File source,
    required File destination,
    required String objectKey,
    SecretKey? bindingKey,
  }) {
    return _unsupportedWrite();
  }

  Future<LocalOfflineVaultWriteResult> encryptStream({
    required Stream<List<int>> plaintext,
    required File destination,
    required String objectKey,
    SecretKey? bindingKey,
  }) {
    return _unsupportedWrite();
  }

  Future<Uint8List> readBytes({
    required File source,
    required String objectKey,
    SecretKey? bindingKey,
    int maximumBytes = 256 * 1024 * 1024,
    void Function()? checkAccess,
  }) {
    return Future<Uint8List>.error(
      const LocalOfflineVaultException(
        LocalOfflineVaultFailure.storageFailure,
        'Native offline storage is unavailable in the browser.',
      ),
    );
  }

  Future<int> decryptToFile({
    required File source,
    required File destination,
    required String objectKey,
    SecretKey? bindingKey,
  }) {
    return Future<int>.error(
      const LocalOfflineVaultException(
        LocalOfflineVaultFailure.storageFailure,
        'Native offline storage is unavailable in the browser.',
      ),
    );
  }

  Future<void> forgetKey() async {}

  Future<void> cleanupTemporaryFiles(
    Directory directory, {
    Duration minimumAge = const Duration(hours: 12),
  }) async {}

  Future<LocalOfflineVaultWriteResult> _unsupportedWrite() {
    return Future<LocalOfflineVaultWriteResult>.error(
      const LocalOfflineVaultException(
        LocalOfflineVaultFailure.storageFailure,
        'Native offline storage is unavailable in the browser.',
      ),
    );
  }
}
