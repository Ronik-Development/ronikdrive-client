import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'local_private_cache.dart';
import 'memory_preview.dart';

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

/// Authenticated, chunked encryption for device-local offline file contents.
///
/// A random master key is kept in the platform keychain. Each offline object
/// receives a distinct derived key bound to its Firebase environment, account,
/// object key, and optional workspace file key. Secure-mode objects therefore
/// still require the user's secure workspace key after the device is unlocked.
class LocalOfflineVault {
  LocalOfflineVault({
    required String uid,
    String scope = '',
    LocalPrivateCacheKeyStore? keyStore,
    AesGcm? algorithm,
    int chunkSize = defaultChunkSize,
  }) : _uid = _validateContext(uid, 'account'),
       _scope = scope.trim(),
       _keyStore = keyStore ?? SecureStorageLocalPrivateCacheKeyStore(),
       _algorithm = algorithm ?? AesGcm.with256bits(),
       _chunkSize = _validateChunkSize(chunkSize);

  static const String storageFormat = 'encrypted-vault-v1';
  static const String fileExtension = '.rdoffline';
  static const int defaultChunkSize = 1024 * 1024;
  static const int maximumChunkSize = 4 * 1024 * 1024;
  static const List<int> _magic = <int>[
    0x52, // R
    0x44, // D
    0x4f, // O
    0x46, // F
    0x46, // F
    0x4c, // L
    0x31, // 1
    0x0a, // newline
  ];
  static const int _finalFrameFlag = 1;

  final String _uid;
  final String _scope;
  final LocalPrivateCacheKeyStore _keyStore;
  final AesGcm _algorithm;
  final int _chunkSize;
  SecretKey? _memoryMasterKey;
  Future<SecretKey?>? _pendingMasterKey;

  String get _accountContext => _scope.isEmpty ? _uid : '$_scope\n$_uid';

  String opaqueFileName(String objectKey) {
    final normalizedObjectKey = _validateContext(objectKey, 'object key');
    final digest = crypto.sha256.convert(
      utf8.encode(
        'ronikdrive-offline-file-v1\n'
        '$_accountContext\n'
        '$normalizedObjectKey',
      ),
    );
    return '$digest$fileExtension';
  }

  Future<bool> isEncryptedFile(File file) async {
    try {
      if (!await file.exists()) {
        return false;
      }
      final handle = await file.open(mode: FileMode.read);
      try {
        final prefix = await handle.read(_magic.length);
        return _constantTimeEquals(prefix, _magic);
      } finally {
        await handle.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<LocalOfflineVaultWriteResult> encryptFile({
    required File source,
    required File destination,
    required String objectKey,
    SecretKey? bindingKey,
  }) {
    return encryptStream(
      plaintext: source.openRead(),
      destination: destination,
      objectKey: objectKey,
      bindingKey: bindingKey,
    );
  }

  Future<LocalOfflineVaultWriteResult> encryptStream({
    required Stream<List<int>> plaintext,
    required File destination,
    required String objectKey,
    SecretKey? bindingKey,
  }) async {
    final normalizedObjectKey = _validateContext(objectKey, 'object key');
    final masterKey = await _masterKey(createIfMissing: true);
    if (masterKey == null) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.keyUnavailable,
        'The offline vault key is unavailable.',
      );
    }
    final objectSecret = await _deriveObjectSecret(
      masterKey: masterKey,
      objectKey: normalizedObjectKey,
      bindingKey: bindingKey,
    );

    final parent = destination.parent;
    final temporary = File(
      '${destination.path}.part-'
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${Random.secure().nextInt(1 << 32)}',
    );
    IOSink? sink;
    var plaintextLength = 0;
    var frameIndex = 0;
    try {
      await parent.create(recursive: true);
      sink = temporary.openWrite(mode: FileMode.writeOnly);
      sink.add(_magic);

      var pending = BytesBuilder(copy: false);
      await for (final incoming in plaintext) {
        if (incoming.isEmpty) {
          continue;
        }
        pending.add(incoming);
        if (pending.length <= _chunkSize) {
          continue;
        }

        final available = pending.takeBytes();
        var offset = 0;
        while (available.length - offset > _chunkSize) {
          final chunk = Uint8List.sublistView(
            available,
            offset,
            offset + _chunkSize,
          );
          await _writeFrame(
            sink: sink,
            plaintext: chunk,
            objectSecret: objectSecret,
            objectKey: normalizedObjectKey,
            frameIndex: frameIndex,
            isFinal: false,
          );
          plaintextLength += chunk.length;
          frameIndex += 1;
          offset += _chunkSize;
        }
        pending.add(Uint8List.sublistView(available, offset));
      }

      final finalChunk = pending.takeBytes();
      await _writeFrame(
        sink: sink,
        plaintext: finalChunk,
        objectSecret: objectSecret,
        objectKey: normalizedObjectKey,
        frameIndex: frameIndex,
        isFinal: true,
      );
      plaintextLength += finalChunk.length;
      await sink.flush();
      await sink.close();
      sink = null;

      await _replaceEncryptedFile(
        temporary: temporary,
        destination: destination,
      );
      final encryptedLength = await destination.length();
      return LocalOfflineVaultWriteResult(
        plaintextLength: plaintextLength,
        encryptedLength: encryptedLength,
      );
    } on LocalOfflineVaultException {
      rethrow;
    } catch (_) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.storageFailure,
        'The encrypted offline copy could not be saved.',
      );
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          // Best effort after an earlier write failure.
        }
      }
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {
          // A later cleanup pass can remove an abandoned temporary file.
        }
      }
    }
  }

  Future<Uint8List> readBytes({
    required File source,
    required String objectKey,
    SecretKey? bindingKey,
    int maximumBytes = 256 * 1024 * 1024,
    void Function()? checkAccess,
  }) async {
    if (maximumBytes < 0) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.invalidInput,
        'The offline read limit must not be negative.',
      );
    }
    final builder = SensitiveByteBuffer(maximumBytes: maximumBytes);
    try {
      checkAccess?.call();
      await _decrypt(
        source: source,
        objectKey: objectKey,
        bindingKey: bindingKey,
        onChunk: (chunk) {
          checkAccess?.call();
          if (builder.length + chunk.length > maximumBytes) {
            throw const LocalOfflineVaultException(
              LocalOfflineVaultFailure.invalidInput,
              'The offline file is too large to preview in memory.',
            );
          }
          builder.add(chunk);
        },
      );
      checkAccess?.call();
      return builder.takeBytes();
    } finally {
      builder.clear();
    }
  }

  Future<int> decryptToFile({
    required File source,
    required File destination,
    required String objectKey,
    SecretKey? bindingKey,
  }) async {
    final temporary = File(
      '${destination.path}.part-'
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${Random.secure().nextInt(1 << 32)}',
    );
    IOSink? sink;
    var plaintextLength = 0;
    try {
      await destination.parent.create(recursive: true);
      sink = temporary.openWrite(mode: FileMode.writeOnly);
      await _decrypt(
        source: source,
        objectKey: objectKey,
        bindingKey: bindingKey,
        onChunk: (chunk) {
          sink!.add(chunk);
          plaintextLength += chunk.length;
        },
      );
      await sink.flush();
      await sink.close();
      sink = null;
      if (await destination.exists()) {
        await destination.delete();
      }
      await temporary.rename(destination.path);
      return plaintextLength;
    } on LocalOfflineVaultException {
      rethrow;
    } catch (_) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.storageFailure,
        'The offline copy could not be opened.',
      );
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          // Best effort after an earlier write failure.
        }
      }
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {
          // A later cleanup pass can remove an abandoned temporary file.
        }
      }
    }
  }

  Future<void> forgetKey() async {
    _memoryMasterKey = null;
    _pendingMasterKey = null;
    try {
      await _keyStore.delete(_masterKeyName);
    } catch (_) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.storageFailure,
        'The offline vault key could not be removed.',
      );
    }
  }

  Future<void> cleanupTemporaryFiles(
    Directory directory, {
    Duration minimumAge = const Duration(hours: 12),
  }) async {
    if (minimumAge.isNegative) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.invalidInput,
        'The offline cleanup age is invalid.',
      );
    }
    final cutoff = DateTime.now().subtract(minimumAge);
    final temporaryName = RegExp(
      r'^[a-f0-9]{64}\.rdoffline\.(?:part|previous)-\d+-\d+$',
    );
    try {
      if (!await directory.exists()) {
        return;
      }
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final fileName = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        if (!temporaryName.hasMatch(fileName)) {
          continue;
        }
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        } catch (_) {
          // One inaccessible temporary file must not block offline startup.
        }
      }
    } catch (_) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.storageFailure,
        'The offline vault directory could not be cleaned.',
      );
    }
  }

  Future<void> _writeFrame({
    required IOSink sink,
    required Uint8List plaintext,
    required SecretKey objectSecret,
    required String objectKey,
    required int frameIndex,
    required bool isFinal,
  }) async {
    final flags = isFinal ? _finalFrameFlag : 0;
    final lengthBytes = _encodeUint32(plaintext.length);
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: objectSecret,
      aad: _frameAdditionalData(
        objectKey: objectKey,
        frameIndex: frameIndex,
        flags: flags,
        plaintextLength: plaintext.length,
      ),
    );
    sink
      ..add(<int>[flags])
      ..add(lengthBytes)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
  }

  Future<void> _replaceEncryptedFile({
    required File temporary,
    required File destination,
  }) async {
    if (!await destination.exists()) {
      await temporary.rename(destination.path);
      return;
    }

    final backup = File(
      '${destination.path}.previous-'
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${Random.secure().nextInt(1 << 32)}',
    );
    await destination.rename(backup.path);
    try {
      await temporary.rename(destination.path);
      try {
        await backup.delete();
      } catch (_) {
        // The encrypted backup is safe and the age-based cleanup can retry.
      }
    } catch (_) {
      if (!await destination.exists() && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
  }

  Future<void> _decrypt({
    required File source,
    required String objectKey,
    required SecretKey? bindingKey,
    required void Function(Uint8List chunk) onChunk,
  }) async {
    final normalizedObjectKey = _validateContext(objectKey, 'object key');
    final masterKey = await _masterKey(createIfMissing: false);
    if (masterKey == null) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.keyUnavailable,
        'The offline vault key is unavailable.',
      );
    }
    final objectSecret = await _deriveObjectSecret(
      masterKey: masterKey,
      objectKey: normalizedObjectKey,
      bindingKey: bindingKey,
    );

    RandomAccessFile? handle;
    try {
      handle = await source.open(mode: FileMode.read);
      final magic = await _readExact(handle, _magic.length);
      if (!_constantTimeEquals(magic, _magic)) {
        throw const LocalOfflineVaultException(
          LocalOfflineVaultFailure.unsupportedFormat,
          'The offline file uses a legacy or unsupported format.',
        );
      }

      var frameIndex = 0;
      var finalFrameSeen = false;
      while (!finalFrameSeen) {
        final flagBytes = await _readExact(handle, 1);
        final flags = flagBytes.single;
        if (flags != 0 && flags != _finalFrameFlag) {
          throw const FormatException('Unknown offline frame flags.');
        }
        final plaintextLength = _decodeUint32(await _readExact(handle, 4));
        if (plaintextLength > maximumChunkSize) {
          throw const FormatException('Offline frame exceeds the size limit.');
        }
        if (flags == 0 && plaintextLength == 0) {
          throw const FormatException('Only the final frame may be empty.');
        }

        final nonce = await _readExact(handle, _algorithm.nonceLength);
        final ciphertext = await _readExact(handle, plaintextLength);
        final mac = await _readExact(handle, _algorithm.macAlgorithm.macLength);
        final plaintext = await _algorithm.decrypt(
          SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
          secretKey: objectSecret,
          aad: _frameAdditionalData(
            objectKey: normalizedObjectKey,
            frameIndex: frameIndex,
            flags: flags,
            plaintextLength: plaintextLength,
          ),
        );
        if (plaintext.length != plaintextLength) {
          throw const FormatException('Offline frame length mismatch.');
        }
        onChunk(Uint8List.fromList(plaintext));
        finalFrameSeen = flags == _finalFrameFlag;
        frameIndex += 1;
      }

      if ((await handle.read(1)).isNotEmpty) {
        throw const FormatException('Data follows the final offline frame.');
      }
    } on LocalOfflineVaultException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.corruptPayload,
        'The offline copy could not be authenticated.',
      );
    } on FormatException {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.corruptPayload,
        'The offline copy is incomplete or corrupt.',
      );
    } on FileSystemException {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.storageFailure,
        'The offline copy could not be read.',
      );
    } finally {
      await handle?.close();
    }
  }

  Future<SecretKey> _deriveObjectSecret({
    required SecretKey masterKey,
    required String objectKey,
    required SecretKey? bindingKey,
  }) async {
    var binding = 'unbound';
    if (bindingKey != null) {
      final bindingMac = await Hmac.sha256().calculateMac(
        utf8.encode(
          'ronikdrive-offline-binding-v1\n'
          '$_accountContext\n'
          '$objectKey',
        ),
        secretKey: bindingKey,
      );
      binding = base64Url.encode(bindingMac.bytes).replaceAll('=', '');
    }
    final objectMac = await Hmac.sha256().calculateMac(
      utf8.encode(
        'ronikdrive-offline-object-v1\n'
        '$_accountContext\n'
        '$objectKey\n'
        '$binding',
      ),
      secretKey: masterKey,
    );
    return SecretKey(objectMac.bytes);
  }

  Future<SecretKey?> _masterKey({required bool createIfMissing}) async {
    final cached = _memoryMasterKey;
    if (cached != null) {
      return cached;
    }
    final pending = _pendingMasterKey;
    if (pending != null) {
      final result = await pending;
      if (result != null || !createIfMissing) {
        return result;
      }
    }

    late final Future<SecretKey?> operation;
    operation = _loadMasterKey(createIfMissing: createIfMissing).whenComplete(
      () {
        if (identical(_pendingMasterKey, operation)) {
          _pendingMasterKey = null;
        }
      },
    );
    _pendingMasterKey = operation;
    return operation;
  }

  Future<SecretKey?> _loadMasterKey({required bool createIfMissing}) async {
    try {
      final stored = await _keyStore.read(_masterKeyName);
      if (stored != null && stored.trim().isNotEmpty) {
        final decoded = _decodeMasterKey(stored);
        _memoryMasterKey = decoded;
        return decoded;
      }
      if (!createIfMissing) {
        return null;
      }

      final generated = await _algorithm.newSecretKey();
      final encoded = base64Url
          .encode(await generated.extractBytes())
          .replaceAll('=', '');
      await _keyStore.write(_masterKeyName, encoded);
      final persisted = await _keyStore.read(_masterKeyName);
      final decoded = _decodeMasterKey(persisted ?? encoded);
      _memoryMasterKey = decoded;
      return decoded;
    } on LocalOfflineVaultException {
      rethrow;
    } catch (_) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.keyUnavailable,
        'The offline vault key is unavailable.',
      );
    }
  }

  SecretKey _decodeMasterKey(String encoded) {
    try {
      var normalized = encoded.trim();
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final bytes = base64Url.decode(normalized);
      if (bytes.length != 32) {
        throw const FormatException('Offline vault keys use 32 bytes.');
      }
      return SecretKey(bytes);
    } catch (_) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.keyUnavailable,
        'The offline vault key is invalid.',
      );
    }
  }

  String get _masterKeyName {
    final accountHash = crypto.sha256
        .convert(utf8.encode(_accountContext))
        .toString();
    return 'ronikdrive_local_offline_vault_key_v1_$accountHash';
  }

  List<int> _frameAdditionalData({
    required String objectKey,
    required int frameIndex,
    required int flags,
    required int plaintextLength,
  }) {
    return utf8.encode(
      'ronikdrive-offline-frame-v1\n'
      '$_accountContext\n'
      '$objectKey\n'
      '$frameIndex\n'
      '$flags\n'
      '$plaintextLength',
    );
  }

  static Uint8List _encodeUint32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.invalidInput,
        'The offline frame length is invalid.',
      );
    }
    return Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);
  }

  static int _decodeUint32(List<int> bytes) {
    if (bytes.length != 4) {
      throw const FormatException('Invalid offline frame length.');
    }
    return Uint8List.fromList(
      bytes,
    ).buffer.asByteData().getUint32(0, Endian.big);
  }

  static Future<Uint8List> _readExact(RandomAccessFile file, int length) async {
    final bytes = await file.read(length);
    if (bytes.length != length) {
      throw const FormatException('Unexpected end of offline file.');
    }
    return bytes;
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static int _validateChunkSize(int value) {
    if (value <= 0 || value > maximumChunkSize) {
      throw const LocalOfflineVaultException(
        LocalOfflineVaultFailure.invalidInput,
        'The offline vault chunk size is invalid.',
      );
    }
    return value;
  }

  static String _validateContext(String value, String label) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 2048) {
      throw LocalOfflineVaultException(
        LocalOfflineVaultFailure.invalidInput,
        'A valid offline vault $label is required.',
      );
    }
    return normalized;
  }
}
