import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'encryption_service.dart';

enum EncryptionRecoveryKitFailure {
  invalidInput,
  invalidFormat,
  authenticationFailed,
  accountMismatch,
  environmentMismatch,
  encryptionSaltMismatch,
}

class EncryptionRecoveryKitException implements Exception {
  const EncryptionRecoveryKitException(this.failure, this.message);

  final EncryptionRecoveryKitFailure failure;
  final String message;

  @override
  String toString() => 'EncryptionRecoveryKitException(${failure.name})';
}

class StandardEncryptionRecoveryMaterial {
  StandardEncryptionRecoveryMaterial({
    required this.accountUid,
    required this.environmentId,
    required List<int> encryptionSalt,
    required List<int> standardKey,
    required this.createdAt,
  }) : encryptionSalt = Uint8List.fromList(encryptionSalt),
       standardKey = Uint8List.fromList(standardKey);

  final String accountUid;
  final String environmentId;
  final Uint8List encryptionSalt;
  final Uint8List standardKey;
  final DateTime createdAt;
}

typedef EncryptionRecoveryKeyDeriver =
    Future<SecretKey> Function(String passphrase, List<int> salt);

/// Creates and opens a user-held recovery kit without any server operation.
///
/// Only format and algorithm identifiers are visible outside the encrypted
/// payload. Account identity, environment identity, the standard encryption
/// salt, and the standard key are authenticated AES-256-GCM ciphertext.
class EncryptionRecoveryKitService {
  EncryptionRecoveryKitService({
    EncryptionRecoveryKeyDeriver? keyDeriver,
    Random? random,
  }) : _keyDeriver =
           keyDeriver ??
           ((passphrase, salt) => EncryptionService.instance.deriveKey(
             password: passphrase,
             salt: salt,
           )),
       _random = random ?? Random.secure();

  static const String format = 'ronikcloud-encryption-recovery-kit';
  static const int version = 1;
  static const String kdfAlgorithm = 'pbkdf2-hmac-sha256';
  static final int kdfIterations = EncryptionService.pbkdf2Iterations;
  static const String cipherAlgorithm = 'aes-256-gcm';
  static const String suggestedFileName =
      'ronikcloud-encryption-recovery.ronik-recovery';
  static const int minimumPassphraseLength = 16;
  static const int maximumKitBytes = 64 * 1024;
  static const int _standardKeyBytes = 32;
  static const int _minimumEncryptionSaltBytes = 16;
  static const int _recoverySaltBytes = 16;
  static const int _nonceBytes = 12;
  static const int _macBytes = 16;
  static const String _payloadType = 'standard-encryption-key';

  static final List<int> _authenticatedContext = utf8.encode(
    '$format:v$version',
  );
  static final RegExp _canonicalBase64UrlPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  final EncryptionRecoveryKeyDeriver _keyDeriver;
  final Random _random;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<Uint8List> create({
    required StandardEncryptionRecoveryMaterial material,
    required String recoveryPassphrase,
  }) async {
    _validatePassphrase(recoveryPassphrase);
    final accountUid = material.accountUid.trim();
    final environmentId = material.environmentId.trim();
    if (accountUid.isEmpty ||
        environmentId.isEmpty ||
        material.encryptionSalt.length < _minimumEncryptionSaltBytes ||
        material.standardKey.length != _standardKeyBytes) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidInput,
        'The encryption recovery material is incomplete.',
      );
    }

    final recoverySalt = _randomBytes(_recoverySaltBytes);
    final nonce = _randomBytes(_nonceBytes);
    final recoveryKey = await _keyDeriver(recoveryPassphrase, recoverySalt);
    final payload = utf8.encode(
      jsonEncode(<String, Object?>{
        'payloadType': _payloadType,
        'payloadVersion': version,
        'accountUid': accountUid,
        'environmentId': environmentId,
        'encryptionSalt': _encodeCanonical(material.encryptionSalt),
        'standardKey': _encodeCanonical(material.standardKey),
        'createdAt': material.createdAt.toUtc().toIso8601String(),
      }),
    );
    final box = await _cipher.encrypt(
      payload,
      secretKey: recoveryKey,
      nonce: nonce,
      aad: _authenticatedContext,
    );
    final encoded = utf8.encode(
      jsonEncode(<String, Object?>{
        'format': format,
        'version': version,
        'kdf': <String, Object?>{
          'algorithm': kdfAlgorithm,
          'iterations': kdfIterations,
          'salt': _encodeCanonical(recoverySalt),
        },
        'cipher': <String, Object?>{
          'algorithm': cipherAlgorithm,
          'nonce': _encodeCanonical(box.nonce),
          'ciphertext': _encodeCanonical(box.cipherText),
          'mac': _encodeCanonical(box.mac.bytes),
        },
      }),
    );
    if (encoded.length > maximumKitBytes) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The generated recovery kit is unexpectedly large.',
      );
    }
    return Uint8List.fromList(encoded);
  }

  Future<StandardEncryptionRecoveryMaterial> open({
    required List<int> encodedKit,
    required String recoveryPassphrase,
    required String expectedAccountUid,
    required String expectedEnvironmentId,
    required List<int> expectedEncryptionSalt,
  }) async {
    _validatePassphrase(recoveryPassphrase);
    if (encodedKit.isEmpty || encodedKit.length > maximumKitBytes) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit size is invalid.',
      );
    }
    final outer = _decodeObject(encodedKit);
    _requireExactKeys(outer, const <String>{
      'format',
      'version',
      'kdf',
      'cipher',
    });
    if (outer['format'] != format || outer['version'] != version) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'This recovery kit format is not supported.',
      );
    }

    final kdf = _object(outer['kdf']);
    _requireExactKeys(kdf, const <String>{'algorithm', 'iterations', 'salt'});
    if (kdf['algorithm'] != kdfAlgorithm ||
        kdf['iterations'] != kdfIterations) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit key-derivation settings are invalid.',
      );
    }
    final recoverySalt = _decodeCanonical(
      kdf['salt'],
      expectedLength: _recoverySaltBytes,
    );

    final cipher = _object(outer['cipher']);
    _requireExactKeys(cipher, const <String>{
      'algorithm',
      'nonce',
      'ciphertext',
      'mac',
    });
    if (cipher['algorithm'] != cipherAlgorithm) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit encryption algorithm is invalid.',
      );
    }
    final nonce = _decodeCanonical(
      cipher['nonce'],
      expectedLength: _nonceBytes,
    );
    final cipherText = _decodeCanonical(cipher['ciphertext']);
    final mac = _decodeCanonical(cipher['mac'], expectedLength: _macBytes);
    if (cipherText.isEmpty) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit ciphertext is missing.',
      );
    }

    final recoveryKey = await _keyDeriver(recoveryPassphrase, recoverySalt);
    Uint8List plaintext;
    try {
      plaintext = Uint8List.fromList(
        await _cipher.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
          secretKey: recoveryKey,
          aad: _authenticatedContext,
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.authenticationFailed,
        'The recovery passphrase is incorrect or the kit is damaged.',
      );
    } catch (_) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.authenticationFailed,
        'The recovery passphrase is incorrect or the kit is damaged.',
      );
    }

    final payload = _decodeObject(plaintext);
    _requireExactKeys(payload, const <String>{
      'payloadType',
      'payloadVersion',
      'accountUid',
      'environmentId',
      'encryptionSalt',
      'standardKey',
      'createdAt',
    });
    if (payload['payloadType'] != _payloadType ||
        payload['payloadVersion'] != version) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit payload is invalid.',
      );
    }

    final accountUid = _requiredString(payload['accountUid']);
    final environmentId = _requiredString(payload['environmentId']);
    if (accountUid != expectedAccountUid.trim()) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.accountMismatch,
        'This recovery kit belongs to a different account.',
      );
    }
    if (environmentId != expectedEnvironmentId.trim()) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.environmentMismatch,
        'This recovery kit belongs to a different RonikCloud environment.',
      );
    }

    final encryptionSalt = _decodeCanonical(payload['encryptionSalt']);
    if (encryptionSalt.length < _minimumEncryptionSaltBytes ||
        !_constantTimeEquals(encryptionSalt, expectedEncryptionSalt)) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.encryptionSaltMismatch,
        'This recovery kit does not match the account encryption setup.',
      );
    }
    final standardKey = _decodeCanonical(
      payload['standardKey'],
      expectedLength: _standardKeyBytes,
    );
    final createdAtText = _requiredString(payload['createdAt']);
    final createdAt = DateTime.tryParse(createdAtText)?.toUtc();
    if (createdAt == null) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit creation time is invalid.',
      );
    }
    return StandardEncryptionRecoveryMaterial(
      accountUid: accountUid,
      environmentId: environmentId,
      encryptionSalt: encryptionSalt,
      standardKey: standardKey,
      createdAt: createdAt,
    );
  }

  void _validatePassphrase(String value) {
    if (value.length < minimumPassphraseLength || value.length > 1024) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidInput,
        'Use a recovery passphrase of at least 16 characters.',
      );
    }
    if (value.trim().isEmpty || value.runes.toSet().length < 6) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidInput,
        'Use a less predictable recovery passphrase.',
      );
    }
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  Map<String, Object?> _decodeObject(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return _object(decoded);
    } catch (_) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit is not valid JSON.',
      );
    }
  }

  Map<String, Object?> _object(Object? value) {
    if (value is! Map) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit structure is invalid.',
      );
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const EncryptionRecoveryKitException(
          EncryptionRecoveryKitFailure.invalidFormat,
          'The recovery kit contains an invalid field.',
        );
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  void _requireExactKeys(Map<String, Object?> value, Set<String> keys) {
    if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit contains unexpected or missing fields.',
      );
    }
  }

  String _requiredString(Object? value) {
    if (value is! String || value.trim().isEmpty || value != value.trim()) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit contains an invalid text field.',
      );
    }
    return value;
  }

  String _encodeCanonical(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Uint8List _decodeCanonical(Object? value, {int? expectedLength}) {
    if (value is! String ||
        value.isEmpty ||
        value.contains('=') ||
        !_canonicalBase64UrlPattern.hasMatch(value)) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit contains invalid binary data.',
      );
    }
    try {
      var padded = value;
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      final decoded = Uint8List.fromList(base64Url.decode(padded));
      if (_encodeCanonical(decoded) != value ||
          (expectedLength != null && decoded.length != expectedLength)) {
        throw const EncryptionRecoveryKitException(
          EncryptionRecoveryKitFailure.invalidFormat,
          'The recovery kit contains invalid binary data.',
        );
      }
      return decoded;
    } on EncryptionRecoveryKitException {
      rethrow;
    } catch (_) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidFormat,
        'The recovery kit contains invalid binary data.',
      );
    }
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = max(left.length, right.length);
    for (var index = 0; index < length; index += 1) {
      final leftByte = index < left.length ? left[index] : 0;
      final rightByte = index < right.length ? right[index] : 0;
      difference |= leftByte ^ rightByte;
    }
    return difference == 0;
  }
}
