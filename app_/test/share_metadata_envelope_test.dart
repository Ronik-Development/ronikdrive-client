import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_storage/src/security/encryption_service.dart';
import 'package:cloud_storage/src/share/share_metadata_envelope.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = SecretKey(Uint8List.fromList(List<int>.generate(32, (i) => i)));

  test(
    'round trips filename and content type without identity metadata',
    () async {
      final envelope = await ShareMetadataEnvelope.seal(
        fileName: 'Quarterly results.pdf',
        contentType: 'application/pdf',
        key: key,
      );

      expect(envelope, isNot(contains('Quarterly')));
      expect(envelope, isNot(contains('owner')));
      final opened = await ShareMetadataEnvelope.open(
        encodedEnvelope: envelope,
        key: key,
      );
      expect(opened.fileName, 'Quarterly results.pdf');
      expect(opened.contentType, 'application/pdf');
    },
  );

  test('uses randomized authenticated encryption', () async {
    final first = await ShareMetadataEnvelope.seal(
      fileName: 'photo.png',
      contentType: 'image/png',
      key: key,
    );
    final second = await ShareMetadataEnvelope.seal(
      fileName: 'photo.png',
      contentType: 'image/png',
      key: key,
    );

    expect(first, isNot(second));
  });

  test('wrong key and tampering fail authentication', () async {
    final envelope = await ShareMetadataEnvelope.seal(
      fileName: 'private.txt',
      contentType: 'text/plain',
      key: key,
    );
    final wrongKey = SecretKey(Uint8List(32)..fillRange(0, 32, 77));
    await expectLater(
      ShareMetadataEnvelope.open(encodedEnvelope: envelope, key: wrongKey),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );

    final tampered = base64Decode(envelope);
    tampered[tampered.length - 1] ^= 1;
    await expectLater(
      ShareMetadataEnvelope.open(
        encodedEnvelope: base64Encode(tampered),
        key: key,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('rejects traversal filenames and unexpected plaintext fields', () async {
    await expectLater(
      ShareMetadataEnvelope.seal(
        fileName: '../private.txt',
        contentType: 'text/plain',
        key: key,
      ),
      throwsA(isA<ShareMetadataEnvelopeException>()),
    );

    final unexpectedPlaintext = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object>{
          'version': 1,
          'fileName': 'safe.txt',
          'contentType': 'text/plain',
          'ownerUid': 'must-not-be-accepted',
        }),
      ),
    );
    final unexpectedCiphertext = await EncryptionService.instance.encryptData(
      unexpectedPlaintext,
      key,
    );
    await expectLater(
      ShareMetadataEnvelope.open(
        encodedEnvelope: base64Encode(unexpectedCiphertext),
        key: key,
      ),
      throwsA(isA<ShareMetadataEnvelopeException>()),
    );
  });

  test('rejects malformed and oversized envelopes before decryption', () async {
    await expectLater(
      ShareMetadataEnvelope.open(encodedEnvelope: 'not base64', key: key),
      throwsA(isA<ShareMetadataEnvelopeException>()),
    );
    await expectLater(
      ShareMetadataEnvelope.open(
        encodedEnvelope: 'A' * (ShareMetadataEnvelope.maximumEncodedLength + 1),
        key: key,
      ),
      throwsA(isA<ShareMetadataEnvelopeException>()),
    );
  });
}
