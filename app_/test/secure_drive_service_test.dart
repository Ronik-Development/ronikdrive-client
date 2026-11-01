import 'dart:convert';

import 'package:cloud_storage/src/storage/secure_drive_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecureFeatureValidation', () {
    test('accepts opaque ids and rejects paths or blank values', () {
      expect(SecureFeatureValidation.documentId(' file-123 '), 'file-123');
      expect(
        () => SecureFeatureValidation.documentId('folder/file'),
        throwsA(isA<SecureDriveException>()),
      );
      expect(
        () => SecureFeatureValidation.documentId('   '),
        throwsA(isA<SecureDriveException>()),
      );
    });

    test('accepts only URL-safe high-entropy link tokens', () {
      expect(SecureFeatureValidation.token('Abc_123-xyz'), 'Abc_123-xyz');
      expect(
        () => SecureFeatureValidation.token('../request'),
        throwsA(isA<SecureDriveException>()),
      );
      expect(
        () => SecureFeatureValidation.token('token with spaces'),
        throwsA(isA<SecureDriveException>()),
      );
    });

    test('extracts, normalizes, and deduplicates email mentions', () {
      expect(
        SecureFeatureValidation.mentionsFromComment(
          'Please ask @Alice.Example+review@Example.COM and '
          '@alice.example+review@example.com. Do not match x@not-a-mention.',
        ),
        const ['alice.example+review@example.com'],
      );
    });

    test('bounds user-controlled text fields', () {
      expect(
        SecureFeatureValidation.requestTitle('  Upload invoices  '),
        'Upload invoices',
      );
      expect(SecureFeatureValidation.comment('  Looks good  '), 'Looks good');
      expect(
        () =>
            SecureFeatureValidation.requestTitle(List.filled(161, 'x').join()),
        throwsA(isA<SecureDriveException>()),
      );
      expect(
        () => SecureFeatureValidation.comment(List.filled(4001, 'x').join()),
        throwsA(isA<SecureDriveException>()),
      );
    });

    test('encodes request keys without changing key material', () {
      final bytes = List<int>.generate(32, (index) => index);
      final encoded = SecureFeatureValidation.encodeRequestKey(bytes);
      expect(base64Url.decode(encoded), bytes);
    });
  });
}
