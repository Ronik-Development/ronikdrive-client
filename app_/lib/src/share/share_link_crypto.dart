import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/encryption_service.dart';

const maximumPublicSharePlaintextBytes = 20 * 1024 * 1024;
const publicShareSizeLimitMessage =
    'Encrypted share links support files up to 20 MiB. Choose a smaller file; your original stays private.';
bool isSupportedPublicShareSize(int length) =>
    length >= 0 && length <= maximumPublicSharePlaintextBytes;

/// A private client value. Never serialize this object into a callable or log.
class ShareLinkKeyMaterial {
  const ShareLinkKeyMaterial({
    required this.key,
    this.password,
    this.saltBase64,
    this.encryptedKeyBase64,
  });

  final SecretKey key;
  final String? password;
  final String? saltBase64;
  final String? encryptedKeyBase64;
  bool get passwordProtected => password != null;

  Map<String, Object> get protectedRecordFields => passwordProtected
      ? {
          'accessMode': 'password',
          'kdf': 'pbkdf2-hmac-sha256',
          'iterations': EncryptionService.pbkdf2Iterations,
          'saltBase64': saltBase64!,
        }
      : {
          'accessMode': 'link',
          'kdf': 'none',
          'iterations': 0,
          'encryptedKeyBase64': encryptedKeyBase64!,
        };
}

abstract final class ShareLinkCrypto {
  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Future<ShareLinkKeyMaterial> create({
    required bool passwordProtected,
    String? password,
    SecretKey? ownerProtectionKey,
  }) async {
    if (passwordProtected) {
      final supplied = password?.trim() ?? '';
      if (supplied.isNotEmpty &&
          (supplied.length < 12 || supplied.length > 128)) {
        throw const FormatException('Invalid share password length.');
      }
      final secret = supplied.isEmpty
          ? base64Url.encode(_randomBytes(18)).replaceAll('=', '')
          : supplied;
      final salt = _randomBytes(16);
      return ShareLinkKeyMaterial(
        key: await EncryptionService.instance.deriveKey(
          password: secret,
          salt: salt,
        ),
        password: secret,
        saltBase64: base64Encode(salt),
      );
    }
    if (ownerProtectionKey == null) {
      throw const FormatException('Owner protection is required.');
    }
    final bytes = _randomBytes(32);
    final key = SecretKey(Uint8List.fromList(bytes));
    final envelope = await EncryptionService.instance.encryptData(
      bytes,
      ownerProtectionKey,
    );
    bytes.fillRange(0, bytes.length, 0);
    return ShareLinkKeyMaterial(
      key: key,
      encryptedKeyBase64: base64Encode(envelope),
    );
  }

  static Future<Uri> completeLink(Uri base, SecretKey key) async {
    final bytes = await key.extractBytes();
    if (bytes.length != 32 || base.hasQuery || base.hasFragment) {
      throw const FormatException('Invalid private share link.');
    }
    return base.replace(
      fragment: 'key=${base64Url.encode(bytes).replaceAll('=', '')}',
    );
  }

  static SecretKey parseFragment(String fragment) {
    final match = RegExp(r'^key=([A-Za-z0-9_-]{43})$').firstMatch(fragment);
    if (match == null) {
      throw const FormatException('Invalid private share link.');
    }
    final encoded = match.group(1)!;
    final bytes = base64Url.decode('$encoded=');
    if (bytes.length != 32 ||
        base64Url.encode(bytes).replaceAll('=', '') != encoded) {
      throw const FormatException('Invalid private share link.');
    }
    return SecretKey(bytes);
  }

  static Future<SecretKey> openOwnerKey({
    required String encryptedKeyBase64,
    required SecretKey ownerProtectionKey,
  }) async {
    if (encryptedKeyBase64.length > 512) {
      throw const FormatException('Invalid protected share key.');
    }
    final bytes = await EncryptionService.instance.decryptData(
      base64Decode(encryptedKeyBase64),
      ownerProtectionKey,
    );
    if (bytes.length != 32) {
      throw const FormatException('Invalid protected share key.');
    }
    return SecretKey(bytes);
  }
}
