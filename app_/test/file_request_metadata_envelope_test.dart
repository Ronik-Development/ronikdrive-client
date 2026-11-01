import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/share/file_request_metadata_envelope.dart';

void main() {
  late SecretKey key;

  setUp(() {
    key = SecretKey(List<int>.generate(32, (index) => index + 1));
  });

  test(
    'request title round-trips only through its encrypted envelope',
    () async {
      const title = 'Upload the signed acquisition agreement';
      final envelope = await FileRequestMetadataEnvelope.sealTitle(
        title: title,
        key: key,
      );

      expect(envelope, isNot(contains('acquisition')));
      expect(
        await FileRequestMetadataEnvelope.openTitle(
          encodedEnvelope: envelope,
          key: key,
        ),
        title,
      );
    },
  );

  test('submitted name and MIME type share one protected envelope', () async {
    final envelope = await FileRequestMetadataEnvelope.sealUpload(
      fileName: 'confidential-report.pdf',
      contentType: 'application/pdf',
      key: key,
    );
    final opened = await FileRequestMetadataEnvelope.openUpload(
      encodedEnvelope: envelope,
      key: key,
    );

    expect(envelope, isNot(contains('confidential')));
    expect(opened.fileName, 'confidential-report.pdf');
    expect(opened.contentType, 'application/pdf');
  });

  test('create payload contains no user-entered title', () async {
    final envelope = await FileRequestMetadataEnvelope.sealTitle(
      title: 'Board documents',
      key: key,
    );
    final payload = FileRequestMetadataEnvelope.protectedCreatePayload(
      encryptedTitleBase64: envelope,
      encryptedKeyBase64: base64Encode(List<int>.filled(80, 4)),
      expiryDays: 7,
      maxFileBytes: 4096,
      maxUploads: 3,
    );

    expect(payload['title'], legacyFileRequestCompatibilityTitle);
    expect(payload['metadataFormat'], fileRequestTitleMetadataFormat);
    expect(
      payload['requestPrivacyVersion'],
      fileRequestLifecyclePrivacyVersion,
    );
    expect(jsonEncode(payload), isNot(contains('Board documents')));
  });

  test('completion payload contains neither name nor MIME type', () async {
    final envelope = await FileRequestMetadataEnvelope.sealUpload(
      fileName: 'private.png',
      contentType: 'image/png',
      key: key,
    );
    final payload = FileRequestMetadataEnvelope.protectedCompletionPayload(
      uploadId: 'upload_123',
      encryptedMetadataBase64: envelope,
    );

    expect(payload.keys, <String>{
      'uploadId',
      'metadataFormat',
      'requestMetadataPrivacyVersion',
      'encryptedMetadataBase64',
    });
    expect(
      payload['requestMetadataPrivacyVersion'],
      fileRequestLifecyclePrivacyVersion,
    );
    expect(jsonEncode(payload), isNot(contains('private.png')));
    expect(jsonEncode(payload), isNot(contains('image/png')));
  });

  test('tampering and wrong keys fail closed', () async {
    final envelope = await FileRequestMetadataEnvelope.sealTitle(
      title: 'Private request',
      key: key,
    );
    final encrypted = base64Decode(envelope)..[20] ^= 1;

    await expectLater(
      FileRequestMetadataEnvelope.openTitle(
        encodedEnvelope: base64Encode(encrypted),
        key: key,
      ),
      throwsA(anything),
    );
    await expectLater(
      FileRequestMetadataEnvelope.openTitle(
        encodedEnvelope: envelope,
        key: SecretKey(List<int>.filled(32, 99)),
      ),
      throwsA(anything),
    );
  });
}
