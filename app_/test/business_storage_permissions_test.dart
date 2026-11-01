import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cloud_storage/src/business/business_storage_permissions.dart';

void main() {
  group('BusinessStoragePermissions', () {
    test('missing and malformed permission fields fail closed', () {
      final permissions = BusinessStoragePermissions.fromMap(
        const <String, Object?>{
          'uploadFiles': 'true',
          'downloadFiles': 1,
          'shareFiles': null,
        },
      );

      expect(permissions.canUpload, isFalse);
      expect(permissions.canDownload, isFalse);
      expect(permissions.canShare, isFalse);
      expect(permissions.canUseStorage, isFalse);
    });

    test('accepts only explicit server-mirrored true values', () {
      final permissions =
          BusinessStoragePermissions.fromMap(const <String, Object?>{
            'uploadFiles': true,
            'downloadFiles': true,
            'shareFiles': false,
            'unrecognizedPermission': true,
          });

      expect(permissions.canUpload, isTrue);
      expect(permissions.canDownload, isTrue);
      expect(permissions.canShare, isFalse);
      expect(permissions.canUseStorage, isTrue);
    });

    test('value equality detects every storage capability change', () {
      const original = BusinessStoragePermissions(
        canUpload: true,
        canDownload: true,
        canShare: true,
      );

      expect(
        original,
        const BusinessStoragePermissions(
          canUpload: true,
          canDownload: true,
          canShare: true,
        ),
      );
      expect(
        original,
        isNot(
          const BusinessStoragePermissions(
            canUpload: true,
            canDownload: false,
            canShare: true,
          ),
        ),
      );
    });
  });

  test(
    'workspace permission mirror evicts stale Business state and gates IO',
    () {
      final source = File(
        'lib/src/home/workspace_home_page.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(
        source,
        contains(
          '_companyStoragePermissions != parsedCompanyStoragePermissions',
        ),
      );
      expect(source, contains("data?['companyPermissions']"));
      expect(source, contains('if (companyStreamAccessChanged)'));
      expect(source, contains('_businessFileKeyCache.clear();'));
      expect(source, contains('_resolvedFileNameCache.clear();'));
      expect(source, contains('_resolvedFolderNameCache.clear();'));
      expect(source, contains('_thumbnailCache.clear();'));
      expect(source, contains('(_canReadCompanyStorage &&'));
      expect(
        source,
        contains('_hasAppliedUserProfileState && !_canReadCompanyStorage'),
      );
      expect(
        source,
        contains(
          '!file.supportsThumbnailPreview ||\n'
          '        !_canReadStorageScope(file.storageScope)',
        ),
      );
      expect(source, contains('ensureStillAuthorized();'));
      expect(source, contains('Upload-only Business access'));
      expect(source, contains('Read-only Business access'));
      expect(
        source,
        isNot(
          contains(
            '_hasAppliedUserProfileState && !_hasActiveCompanyMembership',
          ),
        ),
      );
    },
  );
}
