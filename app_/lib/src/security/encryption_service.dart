import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

Future<Uint8List> _deriveKeyBytesOnWorker(List<Object> args) async {
  final password = args[0] as String;
  final salt = args[1] as Uint8List;
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: EncryptionService.pbkdf2Iterations,
    bits: EncryptionService.keyBits,
  );
  final key = await kdf.deriveKeyFromPassword(password: password, nonce: salt);
  return Uint8List.fromList(await key.extractBytes());
}

/// specialized service for handling all cryptographic operations in the app.
/// This unifies the previously scattered and inconsistent encryption logic
/// into a single, secure implementation.
class EncryptionService {
  EncryptionService._();

  static final EncryptionService instance = EncryptionService._();

  // OWASP recommends 600,000 iterations for PBKDF2-HMAC-SHA256 as of 2023,
  // but 300,000 is a safe lower bound for mobile performance while remaining secure.
  static const int _pbkdf2Iterations = 300000;
  static const int _keyBits = 256;
  static const String _fileNamePrefix = 'enc--';

  static int get pbkdf2Iterations => _pbkdf2Iterations;
  static int get keyBits => _keyBits;

  final AesGcm _fileNameAlgorithm = AesGcm.with256bits();

  // We use AesCtr with HMAC-SHA256 for file content to support streaming
  // efficiently, as GCM can be tricky with large streams without chunking.
  // This matches the existing (correct) choice in WasabiStorageService.
  final AesCtr _fileContentAlgorithm = AesCtr.with256bits(
    macAlgorithm: Hmac.sha256(),
  );

  late final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _pbkdf2Iterations,
    bits: _keyBits,
  );

  /// Derives a secure cryptographic key from a user's password and salt.
  ///
  /// [salt] must be a unique, random sequence of bytes (at least 16 bytes)
  /// generated for the user.
  Future<SecretKey> deriveKey({
    required String password,
    required List<int> salt,
  }) async {
    if (salt.isEmpty) {
      throw ArgumentError('Salt cannot be empty');
    }

    if (kIsWeb) {
      return _kdf.deriveKeyFromPassword(password: password, nonce: salt);
    }

    final keyBytes = await compute(_deriveKeyBytesOnWorker, <Object>[
      password,
      Uint8List.fromList(salt),
    ]);
    return SecretKey(keyBytes);
  }

  /// Encrypts a file name using AES-GCM.
  ///
  /// Returns a string formatted as `enc--<base64_payload>`.
  Future<String> encryptFileName(String name, SecretKey key) async {
    final bytes = utf8.encode(name);
    final secretBox = await _fileNameAlgorithm.encrypt(bytes, secretKey: key);

    // Combine nonce, auth tag, and ciphertext for storage
    // Structure: [nonce (12 bytes)] + [ciphertext] + [mac (16 bytes)]
    final combined = Uint8List(
      secretBox.nonce.length +
          secretBox.cipherText.length +
          secretBox.mac.bytes.length,
    );

    var offset = 0;
    combined.setAll(offset, secretBox.nonce);
    offset += secretBox.nonce.length;
    combined.setAll(offset, secretBox.cipherText);
    offset += secretBox.cipherText.length;
    combined.setAll(offset, secretBox.mac.bytes);

    // Remove padding '=' to avoid S3 signature issues with special characters in keys
    return '$_fileNamePrefix${base64Url.encode(combined).replaceAll('=', '')}';
  }

  /// Decrypts a file name using AES-GCM.
  ///
  /// Returns null if the format is invalid or decryption fails (wrong key).
  Future<String?> decryptFileName(String encryptedName, SecretKey key) async {
    if (!encryptedName.startsWith(_fileNamePrefix)) {
      return null;
    }

    try {
      var rawPayload = encryptedName.substring(_fileNamePrefix.length);
      // Restore padding
      while (rawPayload.length % 4 != 0) {
        rawPayload += '=';
      }

      final payload = base64Url.decode(rawPayload);

      // nonce (12) + mac (16) = 28 bytes minimum overhead
      if (payload.length < 28) {
        return null;
      }

      final nonceLength = _fileNameAlgorithm.nonceLength; // 12
      final macLength = _fileNameAlgorithm.macAlgorithm.macLength; // 16

      final nonce = payload.sublist(0, nonceLength);
      final ciphertext = payload.sublist(
        nonceLength,
        payload.length - macLength,
      );
      final macBytes = payload.sublist(payload.length - macLength);

      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(macBytes));

      final decrypted = await _fileNameAlgorithm.decrypt(
        secretBox,
        secretKey: key,
      );

      return utf8.decode(decrypted);
    } catch (e) {
      // Decryption failed (likely wrong key or corrupted data)
      return null;
    }
  }

  /// Decrypts a complete data buffer (Nonce + Ciphertext + MAC).
  Future<Uint8List> decryptData(List<int> data, SecretKey key) async {
    final nonceLength = _fileContentAlgorithm.nonceLength;
    final macLength = _fileContentAlgorithm.macAlgorithm.macLength;
    final minLength = nonceLength + macLength;

    if (data.length < minLength) {
      throw const FormatException('Data too short to be encrypted');
    }

    final nonce = data.sublist(0, nonceLength);
    final macBytes = data.sublist(data.length - macLength);
    final ciphertext = data.sublist(nonceLength, data.length - macLength);

    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(macBytes));

    final decrypted = await _fileContentAlgorithm.decrypt(
      secretBox,
      secretKey: key,
    );

    return Uint8List.fromList(decrypted);
  }

  /// Encrypts a complete data buffer as Nonce + Ciphertext + MAC.
  Future<Uint8List> encryptData(List<int> data, SecretKey key) async {
    final secretBox = await _fileContentAlgorithm.encrypt(data, secretKey: key);
    final combined = Uint8List(
      secretBox.nonce.length +
          secretBox.cipherText.length +
          secretBox.mac.bytes.length,
    );
    var offset = 0;
    combined.setAll(offset, secretBox.nonce);
    offset += secretBox.nonce.length;
    combined.setAll(offset, secretBox.cipherText);
    offset += secretBox.cipherText.length;
    combined.setAll(offset, secretBox.mac.bytes);
    return combined;
  }

  /// Returns the algorithm used for file content encryption (streams).
  AesCtr get fileContentAlgorithm => _fileContentAlgorithm;

  /// Derives an opaque, deterministic shard token from the secure key.
  ///
  /// The object key is included so the same shard index never maps to the same
  /// storage object across two different files.
  Future<String> deriveSecureShardToken({
    required SecretKey secretKey,
    required String objectKey,
    required int shardIndex,
  }) async {
    if (objectKey.trim().isEmpty) {
      throw ArgumentError('objectKey cannot be empty');
    }
    if (shardIndex < 0) {
      throw RangeError.range(shardIndex, 0, null, 'shardIndex');
    }
    final message = utf8.encode(
      'ronikdrive-secure-shard-v1\n$objectKey\n$shardIndex',
    );
    final mac = await Hmac.sha256().calculateMac(message, secretKey: secretKey);
    return base64Url.encode(mac.bytes).replaceAll('=', '');
  }
}
