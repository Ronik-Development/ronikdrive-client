import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_storage/src/security/encryption_service.dart';
import 'package:cloud_storage/src/share/share_link_crypto.dart';
import 'package:cloud_storage/src/share/share_link_security.dart';
import 'package:cloud_storage/src/share/share_metadata_envelope.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ownerKey = SecretKey(
    Uint8List.fromList(List.generate(32, (i) => i + 1)),
  );
  test(
    'public share transport allows exactly 20 MiB and rejects larger or invalid sizes',
    () {
      expect(maximumPublicSharePlaintextBytes, 20 * 1024 * 1024);
      expect(isSupportedPublicShareSize(0), isTrue);
      expect(
        isSupportedPublicShareSize(maximumPublicSharePlaintextBytes),
        isTrue,
      );
      expect(
        isSupportedPublicShareSize(maximumPublicSharePlaintextBytes + 1),
        isFalse,
      );
      expect(isSupportedPublicShareSize(-1), isFalse);
      expect(publicShareSizeLimitMessage, contains('20 MiB'));
    },
  );
  test(
    'password-free shares keep fresh 256-bit keys only in fragment and owner ciphertext',
    () async {
      final material = await ShareLinkCrypto.create(
        passwordProtected: false,
        ownerProtectionKey: ownerKey,
      );
      final another = await ShareLinkCrypto.create(
        passwordProtected: false,
        ownerProtectionKey: ownerKey,
      );
      final bytes = await material.key.extractBytes();
      expect(bytes, hasLength(32));
      expect(await another.key.extractBytes(), isNot(bytes));
      final fields = material.protectedRecordFields;
      expect(fields.keys.toSet(), {
        'accessMode',
        'kdf',
        'iterations',
        'encryptedKeyBase64',
      });
      expect(fields['accessMode'], 'link');
      expect(fields['kdf'], 'none');
      expect(fields['iterations'], 0);
      expect(material.password, isNull);
      final link = await ShareLinkCrypto.completeLink(
        Uri.parse('https://share.example.test/share/synthetic-token'),
        material.key,
      );
      expect(link.fragment, startsWith('key='));
      expect(link.query, isEmpty);
      expect(
        await ShareLinkCrypto.parseFragment(link.fragment).extractBytes(),
        bytes,
      );
      expect(jsonEncode(fields), isNot(contains(link.fragment.substring(4))));
      final recovered = await ShareLinkCrypto.openOwnerKey(
        encryptedKeyBase64: material.encryptedKeyBase64!,
        ownerProtectionKey: ownerKey,
      );
      expect(await recovered.extractBytes(), bytes);
      final metadata = await ShareMetadataEnvelope.seal(
        fileName: 'synthetic-private.txt',
        contentType: 'text/plain',
        key: material.key,
      );
      expect(
        (await ShareMetadataEnvelope.open(
          encodedEnvelope: metadata,
          key: recovered,
        )).fileName,
        'synthetic-private.txt',
      );
      expect(
        await deriveShareDownloadProof(
          shareKey: recovered,
          token: 'first-token',
        ),
        isNot(
          await deriveShareDownloadProof(
            shareKey: recovered,
            token: 'another-token',
          ),
        ),
      );
    },
  );
  test('owner envelope fails closed with another account key', () async {
    final material = await ShareLinkCrypto.create(
      passwordProtected: false,
      ownerProtectionKey: ownerKey,
    );
    await expectLater(
      ShareLinkCrypto.openOwnerKey(
        encryptedKeyBase64: material.encryptedKeyBase64!,
        ownerProtectionKey: SecretKey(Uint8List(32)),
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
  test(
    'private fragment rejects missing, duplicate, noncanonical and extra fields',
    () {
      for (final fragment in [
        '',
        'key=short',
        'key=${'A' * 43}=',
        'key=${'A' * 43}&key=${'A' * 43}',
        'key=${'A' * 43}&token=extra',
        'key=${'A' * 42}B',
      ]) {
        expect(
          () => ShareLinkCrypto.parseFragment(fragment),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'chosen passwords retain existing KDF and never appear in protected records',
    () async {
      const password = 'synthetic strong password';
      final material = await ShareLinkCrypto.create(
        passwordProtected: true,
        password: password,
      );
      expect(material.password, password);
      expect(material.encryptedKeyBase64, isNull);
      expect(material.protectedRecordFields.keys.toSet(), {
        'accessMode',
        'kdf',
        'iterations',
        'saltBase64',
      });
      expect(
        material.protectedRecordFields['iterations'],
        EncryptionService.pbkdf2Iterations,
      );
      expect(
        jsonEncode(material.protectedRecordFields),
        isNot(contains(password)),
      );
      final recipientKey = await EncryptionService.instance.deriveKey(
        password: password,
        salt: base64Decode(material.saltBase64!),
      );
      expect(
        await recipientKey.extractBytes(),
        await material.key.extractBytes(),
      );
    },
  );
  test(
    'short custom passwords and unprotected owner envelopes are rejected',
    () async {
      await expectLater(
        ShareLinkCrypto.create(passwordProtected: true, password: 'short'),
        throwsFormatException,
      );
      await expectLater(
        ShareLinkCrypto.create(passwordProtected: false),
        throwsFormatException,
      );
    },
  );
}
