import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/security/workspace_metadata_encryption_service.dart';

void main() {
  group('WorkspaceMetadataEncryptionService', () {
    final service = WorkspaceMetadataEncryptionService();
    final key = SecretKey(List<int>.generate(32, (index) => index + 1));
    final otherKey = SecretKey(List<int>.generate(32, (index) => 255 - index));

    test('encrypts and authenticates folder labels', () async {
      final encrypted = await service.encryptLabel(
        label: 'Quarterly acquisitions',
        key: key,
      );

      expect(encrypted, startsWith('enc--'));
      expect(encrypted, isNot(contains('Quarterly')));
      expect(
        await service.decryptLabel(encryptedLabel: encrypted, key: key),
        'Quarterly acquisitions',
      );
      expect(
        await service.decryptLabel(encryptedLabel: encrypted, key: otherKey),
        isNull,
      );
    });

    test(
      'derives stable keyed backup path tags without path fragments',
      () async {
        final first = await service.backupPathTag(
          normalizedRelativePath: 'tax/2026/return.pdf',
          key: key,
        );
        final repeated = await service.backupPathTag(
          normalizedRelativePath: 'tax/2026/return.pdf',
          key: key,
        );
        final withOtherKey = await service.backupPathTag(
          normalizedRelativePath: 'tax/2026/return.pdf',
          key: otherKey,
        );

        expect(
          first,
          startsWith(WorkspaceMetadataEncryptionService.backupPathTagPrefix),
        );
        expect(first, repeated);
        expect(first, isNot(withOtherKey));
        expect(first, isNot(contains('tax')));
        expect(first, isNot(contains('return')));
      },
    );

    test('separates local path tags from remote backup path tags', () async {
      final backupTag = await service.backupPathTag(
        normalizedRelativePath: 'documents/report.pdf',
        key: key,
      );
      final localTag = await service.localPathTag(
        normalizedLocalPath: r'c:\users\person\documents\report.pdf',
        key: key,
      );

      expect(
        localTag,
        startsWith(WorkspaceMetadataEncryptionService.localPathTagPrefix),
      );
      expect(localTag, isNot(backupTag));
      expect(localTag.toLowerCase(), isNot(contains('users')));
      expect(localTag.toLowerCase(), isNot(contains('report')));
    });

    test(
      'keys content integrity tags without exposing the raw digest',
      () async {
        final digest = base64Encode(List<int>.generate(32, (index) => index));
        final firstKey = SecretKey(List<int>.filled(32, 41));
        final secondKey = SecretKey(List<int>.filled(32, 42));

        final firstTag = await service.contentIntegrityTag(
          sha256Base64: digest,
          key: firstKey,
        );
        final repeatedTag = await service.contentIntegrityTag(
          sha256Base64: digest,
          key: firstKey,
        );
        final otherAccountTag = await service.contentIntegrityTag(
          sha256Base64: digest,
          key: secondKey,
        );

        expect(
          firstTag,
          startsWith(
            WorkspaceMetadataEncryptionService.contentIntegrityTagPrefix,
          ),
        );
        expect(firstTag, repeatedTag);
        expect(firstTag, isNot(otherAccountTag));
        expect(firstTag, isNot(contains(digest)));
      },
    );

    test('rejects malformed content digests before tagging', () {
      expect(
        () => service.contentIntegrityTag(
          sha256Base64: 'not-a-sha256-digest',
          key: SecretKey(List<int>.filled(32, 7)),
        ),
        throwsA(isA<WorkspaceMetadataEncryptionException>()),
      );
    });

    test('derives opaque folder ids scoped to parent and workspace', () async {
      final first = await service.deterministicFolderId(
        namespace: 'backup',
        storageSpaceId: 'personal',
        parentId: null,
        normalizedName: 'Payroll',
        key: key,
      );
      final repeated = await service.deterministicFolderId(
        namespace: 'backup',
        storageSpaceId: 'personal',
        parentId: null,
        normalizedName: 'Payroll',
        key: key,
      );
      final child = await service.deterministicFolderId(
        namespace: 'backup',
        storageSpaceId: 'personal',
        parentId: 'parent-folder',
        normalizedName: 'Payroll',
        key: key,
      );

      expect(
        first,
        startsWith(WorkspaceMetadataEncryptionService.folderIdPrefix),
      );
      expect(first, repeated);
      expect(first, isNot(child));
      expect(first.toLowerCase(), isNot(contains('payroll')));
    });

    test('uses an opaque folder id as authenticated envelope context', () {
      expect(
        service.folderEncryptionContext('fld--opaque'),
        '${WorkspaceMetadataEncryptionService.folderContextPrefix}fld--opaque',
      );
      expect(
        () => service.folderEncryptionContext('  '),
        throwsA(isA<WorkspaceMetadataEncryptionException>()),
      );
    });
  });
}
