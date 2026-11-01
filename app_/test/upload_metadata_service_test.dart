import 'package:cloud_storage/src/storage/upload_metadata_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UploadMetadataPayloadEncoder', () {
    test('native recovery retains mandatory conditional-write metadata', () {
      const encoder = UploadMetadataPayloadEncoder(
        encodeLargeIntsAsStrings: false,
      );
      final payload = encoder.buildRecordUploadedFilePayload(
        objectKey: 'user/objects/new.bin',
        size: 5,
        encryptionMode: 'standard',
        storageLayout: 'single',
        contentEncryption: 'standard',
        storageScope: 'personal',
        supersedesFileId: 'previous',
      );
      final version = List.filled(64, 'a').join();
      payload['nativeExpectedVersion'] = version;
      expect(
        encoder.normalizeRecordUploadedFilePayload(
          payload,
        )['nativeExpectedVersion'],
        version,
      );
      for (final invalid in [null, 'create', 'stale', 123]) {
        expect(
          () => encoder.normalizeRecordUploadedFilePayload({
            ...payload,
            'nativeExpectedVersion': invalid,
          }),
          throwsA(isA<UploadMetadataException>()),
        );
      }
    });
    test('encodes large upload metadata as strings for Flutter web', () {
      const encoder = UploadMetadataPayloadEncoder(
        encodeLargeIntsAsStrings: true,
      );
      final modifiedMillis = DateTime.utc(
        2026,
        1,
        1,
        12,
      ).millisecondsSinceEpoch;

      final payload = encoder.buildRecordUploadedFilePayload(
        objectKey: 'user/files/video.mov',
        size: 1 << 40,
        encryptionMode: 'standard',
        contentEncryption: 'standard',
        storageLayout: 'sharded',
        shardCount: 129,
        shardSizeBytes: 8 * 1024 * 1024,
        backupPathHash: ' backup-hash ',
        backupModifiedMillis: modifiedMillis,
        uploadedAt: DateTime.utc(2026, 1, 1),
      );

      expect(payload['size'], '${1 << 40}');
      expect(payload['shardCount'], '129');
      expect(payload['shardSizeBytes'], '${8 * 1024 * 1024}');
      expect(payload['backupModifiedMillis'], '$modifiedMillis');
      expect(payload['backupPathHash'], 'backup-hash');
      expect(payload, isNot(contains('pathSegments')));
      expect(payload, isNot(contains('hasThumbnail')));
      expect(payload['uploadedAt'], '2026-01-01T00:00:00.000Z');
    });

    test('keeps native callable metadata numeric', () {
      const encoder = UploadMetadataPayloadEncoder(
        encodeLargeIntsAsStrings: false,
      );

      final payload = encoder.buildRecordUploadedFilePayload(
        objectKey: 'user/imports/archive.zip',
        size: 1 << 33,
        encryptionMode: 'standard',
        contentEncryption: 'standard',
        shardCount: 2,
        shardSizeBytes: 8 * 1024 * 1024,
        backupModifiedMillis: 2147483648,
      );

      expect(payload['size'], isA<int>());
      expect(payload['size'], 1 << 33);
      expect(payload['shardCount'], 2);
      expect(payload['shardSizeBytes'], 8 * 1024 * 1024);
      expect(payload['backupModifiedMillis'], 2147483648);
    });

    test('includes secure shard and refresh metadata', () {
      const encoder = UploadMetadataPayloadEncoder(
        encodeLargeIntsAsStrings: true,
      );
      final refreshedAt = DateTime.utc(2026, 6, 14, 10);
      final dueAt = DateTime.utc(2026, 9, 12, 10);
      final integrityTag = 'cit--${List<String>.filled(43, 'A').join()}';

      final payload = encoder.buildRecordUploadedFilePayload(
        objectKey: 'user/objects/aa/bb/token',
        size: 4096,
        encryptionMode: 'secured',
        storageLayout: 'sharded',
        shardCount: 3,
        shardSizeBytes: 4 * 1024 * 1024,
        shardScheme: 'passphrase-hmac-sha256-v1',
        contentEncryption: 'secure',
        secureContentEncoding: 'whole-file-aes-ctr-hmac-sha256-v1',
        secureRefreshedAt: refreshedAt,
        secureRefreshDueAt: dueAt,
        contentIntegrityTag: integrityTag,
        contentIntegrityVersion: 'hmac-sha256-v1',
        encryptedName: 'enc--name',
      );

      expect(payload['shardScheme'], 'passphrase-hmac-sha256-v1');
      expect(
        payload['secureContentEncoding'],
        'whole-file-aes-ctr-hmac-sha256-v1',
      );
      expect(payload['secureRefreshedAt'], '2026-06-14T10:00:00.000Z');
      expect(payload['secureRefreshDueAt'], '2026-09-12T10:00:00.000Z');
      expect(payload, isNot(contains('hashBase64')));
      expect(payload, isNot(contains('contentIntegrityTag')));
      expect(payload, isNot(contains('contentIntegrityVersion')));
      expect(payload, isNot(contains('passphrase')));
      expect(payload, isNot(contains('encryptionPasswordHash')));
    });

    test('sends only a versioned keyed integrity tag for standard files', () {
      const encoder = UploadMetadataPayloadEncoder(
        encodeLargeIntsAsStrings: false,
      );
      final integrityTag = 'cit--${List<String>.filled(43, 'B').join()}';
      final payload = encoder.buildRecordUploadedFilePayload(
        objectKey: 'user/backups/opaque-object',
        size: 512,
        encryptionMode: 'standard',
        contentEncryption: 'standard',
        contentIntegrityTag: integrityTag,
        contentIntegrityVersion: 'hmac-sha256-v1',
      );

      expect(payload['contentIntegrityTag'], integrityTag);
      expect(payload['contentIntegrityVersion'], 'hmac-sha256-v1');
      expect(payload, isNot(contains('hashBase64')));
    });

    test('strips legacy readable folder fields from local retry payloads', () {
      const encoder = UploadMetadataPayloadEncoder(
        encodeLargeIntsAsStrings: true,
      );

      final current = encoder.buildRecordUploadedFilePayload(
        objectKey: 'user/imports/cloud.bin',
        size: 2147483649,
        encryptionMode: 'standard',
        contentEncryption: 'standard',
        encryptedName: '',
        backupPathHash: null,
      );
      final payload = encoder.normalizeRecordUploadedFilePayload(
        <String, dynamic>{
          ...current,
          'folderName': 'Private folder',
          'folderColor': '#112233',
          'pathSegments': <String>['Private', 'Nested'],
          'hasThumbnail': true,
        },
      );

      expect(payload['size'], '2147483649');
      expect(payload, isNot(contains('folderName')));
      expect(payload, isNot(contains('encryptedName')));
      expect(payload, isNot(contains('backupPathHash')));
      expect(payload, isNot(contains('pathSegments')));
      expect(payload, isNot(contains('hasThumbnail')));
    });

    test('includes company storage scope metadata', () {
      const encoder = UploadMetadataPayloadEncoder(
        encodeLargeIntsAsStrings: false,
      );

      final payload = encoder.buildRecordUploadedFilePayload(
        objectKey: 'company_root/groups/token/file.bin',
        size: 2048,
        encryptionMode: 'standard',
        contentEncryption: 'standard',
        storageScope: 'group',
        companyId: 'company-1',
        ownerUid: 'user-1',
        groupIds: const [' engineering ', ''],
        allowedUids: const ['user-1'],
        sharedKeyEnvelopes: const <String, Object?>{
          'user-1': <String, Object?>{
            'recipientId': 'user-1',
            'recipientType': 'user',
            'wrappedKey': 'wrapped',
          },
        },
      );

      expect(payload['storageScope'], 'group');
      expect(payload['companyId'], 'company-1');
      expect(payload['ownerUid'], 'user-1');
      expect(payload['groupIds'], const ['engineering']);
      expect(payload['allowedUids'], const ['user-1']);
      expect(payload['sharedKeyEnvelopes'], isA<Map<String, Object?>>());
    });

    test('includes only a normalized explicit predecessor id', () {
      const encoder = UploadMetadataPayloadEncoder(
        encodeLargeIntsAsStrings: false,
      );

      final payload = encoder.buildRecordUploadedFilePayload(
        objectKey: 'user/files/new-object.bin',
        size: 128,
        encryptionMode: 'standard',
        contentEncryption: 'standard',
        supersedesFileId: ' previous-file-id ',
      );
      final noPredecessor = encoder.buildRecordUploadedFilePayload(
        objectKey: 'user/files/standalone.bin',
        size: 64,
        encryptionMode: 'standard',
        contentEncryption: 'standard',
        supersedesFileId: '   ',
      );

      expect(payload['supersedesFileId'], 'previous-file-id');
      expect(noPredecessor, isNot(contains('supersedesFileId')));
    });

    test('saved retry payloads are bounded and reject unknown fields', () {
      const encoder = UploadMetadataPayloadEncoder(
        encodeLargeIntsAsStrings: false,
      );
      final payload = encoder.buildRecordUploadedFilePayload(
        objectKey: 'users/user-1/objects/opaque',
        size: 128,
        encryptionMode: 'standard',
        contentEncryption: 'standard',
        encryptedName: 'enc--opaque-name',
      );

      final normalized = encoder.normalizeRecordUploadedFilePayload(payload);
      expect(normalized, payload);
      expect(
        () => encoder.normalizeRecordUploadedFilePayload(<String, dynamic>{
          ...payload,
          'passphrase': 'must-never-be-persisted',
        }),
        throwsA(isA<UploadMetadataException>()),
      );
      expect(
        () => encoder.normalizeRecordUploadedFilePayload(<String, dynamic>{
          ...payload,
          'size': -1,
        }),
        throwsA(isA<UploadMetadataException>()),
      );
    });
  });
}
