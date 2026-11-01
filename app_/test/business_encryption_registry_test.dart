import 'dart:math';

import 'package:cloud_storage/src/security/business_encryption_registry.dart';
import 'package:cloud_storage/src/security/business_encryption_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BusinessEncryptionRegistry', () {
    test('creates and registers a protected identity only once', () async {
      Map<String, Object?>? storedIdentity;
      var registerCalls = 0;
      final registry = BusinessEncryptionRegistry(
        encryptionService: BusinessEncryptionService(random: Random(51)),
        callable: (functionName, payload) async {
          switch (functionName) {
            case 'getBusinessEncryptionIdentity':
              return <String, Object?>{'identity': storedIdentity};
            case 'registerBusinessEncryptionIdentity':
              registerCalls += 1;
              storedIdentity = Map<String, Object?>.from(
                payload!['identity']! as Map,
              );
              return <String, Object?>{'identity': storedIdentity};
          }
          throw StateError('Unexpected callable: $functionName');
        },
      );
      final protection = SecretKey(List<int>.filled(32, 6));

      final first = await registry.ensureIdentity(
        accountProtectionKey: protection,
      );
      final second = await registry.ensureIdentity(
        accountProtectionKey: protection,
      );

      expect(first.keyId, second.keyId);
      expect(registerCalls, 1);
      expect(storedIdentity, contains('wrappedPrivateKeyBase64'));
    });

    test('parses a complete recipient readiness response', () async {
      final identityService = BusinessEncryptionService(random: Random(61));
      final identity = await identityService.createIdentity(
        accountProtectionKey: SecretKey(List<int>.filled(32, 7)),
      );
      final registry = BusinessEncryptionRegistry(
        callable: (functionName, payload) async {
          expect(functionName, 'listBusinessEncryptionRecipients');
          expect(payload, <String, Object?>{'storageScope': 'company_shared'});
          return <String, Object?>{
            'storageScope': 'company_shared',
            'recipients': <Object?>[
              <String, Object?>{
                'uid': 'member-1',
                'keyId': identity.keyId,
                'publicKeyBase64': identity.publicKeyBase64,
              },
            ],
            'missingUids': const <String>[],
            'eligibleCount': 1,
            'readyCount': 1,
          };
        },
      );

      final result = await registry.listRecipients(
        storageScope: 'company_shared',
      );

      expect(result.isComplete, isTrue);
      expect(result.recipients.single.uid, 'member-1');
    });

    test('rejects inconsistent readiness counts', () async {
      final registry = BusinessEncryptionRegistry(
        callable: (functionName, payload) async => <String, Object?>{
          'recipients': const <Object?>[],
          'missingUids': const <String>['member-1'],
          'eligibleCount': 2,
          'readyCount': 0,
        },
      );

      await expectLater(
        registry.listRecipients(storageScope: 'company_shared'),
        throwsA(isA<BusinessEncryptionRegistryException>()),
      );
    });

    test('redacts asynchronous callable provider details', () async {
      final registry = BusinessEncryptionRegistry(
        callable: (functionName, payload) async {
          await Future<void>.delayed(Duration.zero);
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message:
                'host=private.example object=company/payroll.xlsx token=secret',
          );
        },
      );

      await expectLater(
        registry.getIdentity(),
        throwsA(
          isA<BusinessEncryptionRegistryException>()
              .having(
                (error) => error.message,
                'message',
                contains('Business encryption access changed'),
              )
              .having(
                (error) => error.message,
                'private provider detail',
                isNot(contains('private.example')),
              )
              .having(
                (error) => error.message,
                'private object name',
                isNot(contains('payroll.xlsx')),
              ),
        ),
      );
    });

    test(
      'parses protected metadata recipients without label plaintext',
      () async {
        final identityService = BusinessEncryptionService(random: Random(71));
        final identity = await identityService.createIdentity(
          accountProtectionKey: SecretKey(List<int>.filled(32, 8)),
        );
        final registry = BusinessEncryptionRegistry(
          callable: (functionName, payload) async {
            expect(functionName, 'listBusinessMetadataRecipients');
            expect(payload, <String, Object?>{
              'entityType': 'group',
              'memberUids': <String>['member-1'],
            });
            expect(payload, isNot(contains('name')));
            expect(payload, isNot(contains('description')));
            return <String, Object?>{
              'entityType': 'group',
              'recipients': <Object?>[
                <String, Object?>{
                  'uid': 'member-1',
                  'keyId': identity.keyId,
                  'publicKeyBase64': identity.publicKeyBase64,
                },
              ],
              'missingUids': const <String>[],
              'metadataMissingUids': const <String>['member-1'],
              'eligibleCount': 1,
              'readyCount': 1,
            };
          },
        );

        final result = await registry.listMetadataRecipients(
          entityType: 'group',
          memberUids: const <String>['member-1'],
        );

        expect(result.entityType, 'group');
        expect(result.metadataMissingUids, <String>['member-1']);
        expect(result.recipients.single.uid, 'member-1');
      },
    );

    test('submits only protected metadata envelope additions', () async {
      final identityService = BusinessEncryptionService(random: Random(76));
      final identity = await identityService.createIdentity(
        accountProtectionKey: SecretKey(List<int>.filled(32, 9)),
      );
      final material = await identityService.createFileEncryptionMaterial(
        objectKey:
            'ronikdrive-business-metadata-v1:group:'
            'bmd_AAAAAAAAAAAAAAAAAAAAAA',
        recipients: <BusinessEncryptionRecipient>[
          BusinessEncryptionRecipient(
            uid: 'member-1',
            keyId: identity.keyId,
            publicKeyBase64: identity.publicKeyBase64,
          ),
        ],
      );
      final registry = BusinessEncryptionRegistry(
        callable: (functionName, payload) async {
          expect(functionName, 'appendBusinessMetadataKeyEnvelopes');
          expect(payload?['entityType'], 'group');
          expect(payload?['groupId'], 'group-1');
          expect(payload, isNot(contains('name')));
          expect(payload, isNot(contains('description')));
          final additions = Map<String, Object?>.from(
            payload?['additions']! as Map,
          );
          expect(additions.keys, <String>['member-1']);
          expect(
            Map<String, Object?>.from(additions['member-1']! as Map),
            contains('encryptedFileKeyBase64'),
          );
          return <String, Object?>{
            'entityType': 'group',
            'groupId': 'group-1',
            'addedCount': 1,
            'recipientCount': 2,
          };
        },
      );

      final result = await registry.appendMetadataEnvelopes(
        entityType: 'group',
        groupId: 'group-1',
        additions: material.envelopes,
      );

      expect(result.addedCount, 1);
      expect(result.groupId, 'group-1');
    });

    test('submits only encrypted envelope additions for one file', () async {
      final identityService = BusinessEncryptionService(random: Random(81));
      final identity = await identityService.createIdentity(
        accountProtectionKey: SecretKey(List<int>.filled(32, 10)),
      );
      final material = await identityService.createFileEncryptionMaterial(
        objectKey: 'company_opaque/shared/objects/aa/bb/file',
        recipients: <BusinessEncryptionRecipient>[
          BusinessEncryptionRecipient(
            uid: 'member-2',
            keyId: identity.keyId,
            publicKeyBase64: identity.publicKeyBase64,
          ),
        ],
      );
      final registry = BusinessEncryptionRegistry(
        callable: (functionName, payload) async {
          expect(functionName, 'appendBusinessFileKeyEnvelopes');
          expect(payload?['fileId'], 'file-id');
          final additions = Map<String, Object?>.from(
            payload?['additions']! as Map,
          );
          expect(additions.keys, <String>['member-2']);
          final envelope = Map<String, Object?>.from(
            additions['member-2']! as Map,
          );
          expect(envelope, isNot(contains('fileKey')));
          expect(envelope, contains('encryptedFileKeyBase64'));
          return <String, Object?>{
            'fileId': 'file-id',
            'addedCount': 1,
            'recipientCount': 2,
          };
        },
      );

      final result = await registry.appendFileEnvelopes(
        fileId: 'file-id',
        additions: material.envelopes,
      );

      expect(result.addedCount, 1);
      expect(result.recipientCount, 2);
    });

    test('rejects an inconsistent envelope append response', () async {
      final identityService = BusinessEncryptionService(random: Random(91));
      final identity = await identityService.createIdentity(
        accountProtectionKey: SecretKey(List<int>.filled(32, 11)),
      );
      final material = await identityService.createFileEncryptionMaterial(
        objectKey: 'company_opaque/shared/objects/aa/bb/file',
        recipients: <BusinessEncryptionRecipient>[
          BusinessEncryptionRecipient(
            uid: 'member-2',
            keyId: identity.keyId,
            publicKeyBase64: identity.publicKeyBase64,
          ),
        ],
      );
      final registry = BusinessEncryptionRegistry(
        callable: (functionName, payload) async => <String, Object?>{
          'fileId': 'different-file',
          'addedCount': 0,
          'recipientCount': 1,
        },
      );

      await expectLater(
        registry.appendFileEnvelopes(
          fileId: 'file-id',
          additions: material.envelopes,
        ),
        throwsA(isA<BusinessEncryptionRegistryException>()),
      );
    });

    test(
      'rotates a file using only opaque encrypted replacement data',
      () async {
        final identityService = BusinessEncryptionService(random: Random(96));
        final identity = await identityService.createIdentity(
          accountProtectionKey: SecretKey(List<int>.filled(32, 13)),
        );
        final material = await identityService.createFileEncryptionMaterial(
          objectKey: 'company_opaque/shared/objects/cc/dd/replacement',
          recipients: <BusinessEncryptionRecipient>[
            BusinessEncryptionRecipient(
              uid: 'member-1',
              keyId: identity.keyId,
              publicKeyBase64: identity.publicKeyBase64,
            ),
          ],
        );
        final registry = BusinessEncryptionRegistry(
          callable: (functionName, payload) async {
            expect(functionName, 'rotateBusinessFileEncryption');
            expect(payload?['fileId'], 'file-id');
            expect(
              payload?['expectedObjectKey'],
              'company_opaque/shared/objects/aa/bb/current',
            );
            expect(
              payload?['replacementObjectKey'],
              'company_opaque/shared/objects/cc/dd/replacement',
            );
            expect(payload?['encryptedName'], startsWith('enc--'));
            expect(payload, isNot(contains('name')));
            expect(payload, isNot(contains('fileKey')));
            final envelopes = Map<String, Object?>.from(
              payload?['sharedKeyEnvelopes']! as Map,
            );
            expect(envelopes.keys, <String>['member-1']);
            expect(
              Map<String, Object?>.from(envelopes['member-1']! as Map),
              contains('encryptedFileKeyBase64'),
            );
            return <String, Object?>{
              'fileId': 'file-id',
              'recipientCount': 1,
              'rotationGeneration': 2,
              'cleanupPending': false,
            };
          },
        );

        final result = await registry.rotateFileEncryption(
          fileId: 'file-id',
          expectedObjectKey: 'company_opaque/shared/objects/aa/bb/current',
          replacementObjectKey:
              'company_opaque/shared/objects/cc/dd/replacement',
          encryptedName: 'enc--replacement-name',
          envelopes: material.envelopes,
        );

        expect(result.rotationGeneration, 2);
        expect(result.cleanupPending, isFalse);
      },
    );

    test('saves only encrypted Business folder metadata', () async {
      final identityService = BusinessEncryptionService(random: Random(101));
      final identity = await identityService.createIdentity(
        accountProtectionKey: SecretKey(List<int>.filled(32, 12)),
      );
      final material = await identityService.createFileEncryptionMaterial(
        objectKey: 'ronikdrive-folder-v1:fld--opaque',
        recipients: <BusinessEncryptionRecipient>[
          BusinessEncryptionRecipient(
            uid: 'member-1',
            keyId: identity.keyId,
            publicKeyBase64: identity.publicKeyBase64,
          ),
        ],
      );
      final registry = BusinessEncryptionRegistry(
        callable: (functionName, payload) async {
          expect(functionName, 'saveBusinessEncryptedFolder');
          expect(payload?['folderId'], 'fld--opaque');
          expect(payload?['encryptedName'], startsWith('enc--'));
          expect(payload, isNot(contains('name')));
          expect(payload, isNot(contains('path')));
          expect(payload, isNot(contains('pathSegments')));
          expect(
            payload?['metadataEncryption'],
            'business-envelope-aes-gcm-v1',
          );
          return <String, Object?>{
            'folderId': 'fld--opaque',
            'recipientCount': 1,
            'created': true,
          };
        },
      );

      final result = await registry.saveEncryptedFolder(
        folderId: 'fld--opaque',
        encryptedName: 'enc--opaque-label',
        storageScope: 'company_shared',
        color: '#E8F0FE',
        envelopes: material.envelopes,
      );

      expect(result.created, isTrue);
      expect(result.recipientCount, 1);
    });

    test('protects Business file metadata in bounded opaque batches', () async {
      final registry = BusinessEncryptionRegistry(
        callable: (functionName, payload) async {
          expect(functionName, 'protectBusinessFileMetadata');
          expect(payload?['fileIds'], <String>['file-a', 'file-b']);
          expect(payload?['storageScope'], 'group');
          expect(payload?['groupId'], 'group-1');
          expect(payload, isNot(contains('folderName')));
          expect(payload, isNot(contains('pathSegments')));
          return <String, Object?>{'requestedCount': 2, 'protectedCount': 1};
        },
      );

      final protectedCount = await registry.protectFileMetadata(
        fileIds: const <String>['file-a', 'file-b'],
        storageScope: 'group',
        groupId: 'group-1',
      );

      expect(protectedCount, 1);
    });
  });
}
