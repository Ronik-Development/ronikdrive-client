import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/business/company_admin_service.dart';

void main() {
  test('CompanyDashboard parses company admin payloads', () {
    final dashboard = CompanyDashboard.fromMap(<String, Object?>{
      'company': <String, Object?>{
        'id': 'company-1',
        'name': 'Acme Secure Storage',
        'domain': 'example.test',
        'reconciliation': <String, Object?>{
          'requiredRevision': 7,
          'completedRevision': 5,
          'pending': true,
        },
        'storagePolicy': <String, Object?>{
          'privateStorageEnabledByDefault': false,
          'sharedStorageEnabled': true,
          'defaultPrivateQuotaBytes': 1073741824,
        },
        'storageInventory': <String, Object?>{
          'version': 1,
          'status': 'diverged',
          'complete': true,
          'observedBytes': 4096,
          'metadataUsageBytes': 3072,
          'objectCount': 8,
          'orphanObjectCount': 1,
          'missingObjectCount': 2,
          'checkedAt': '2026-08-02T12:00:00.000Z',
        },
      },
      'currentMember': <String, Object?>{
        'id': 'owner-uid',
        'uid': 'owner-uid',
        'email': 'owner@example.test',
        'role': 'owner',
        'status': 'active',
      },
      'canCreate': false,
      'canManage': true,
      'accessPatternsScope': 'business_v1',
      'accessPatternsComplete': true,
      'members': <Object?>[
        <String, Object?>{
          'id': 'owner-uid',
          'email': 'owner@example.test',
          'role': 'owner',
          'permissions': <String, Object?>{
            'manageMembers': true,
            'viewAuditLogs': true,
          },
          'accessScopes': <Object?>['company_workspace', 'audit_logs'],
          'groupIds': <Object?>['engineering'],
          'encryptionReady': true,
          'encryptionKeyId': 'opaque-key-id',
          'storageOverride': <String, Object?>{
            'privateStorageEnabled': true,
            'privateQuotaBytes': 2147483648,
          },
        },
      ],
      'groups': <Object?>[
        <String, Object?>{
          'id': 'engineering',
          'name': 'Engineering',
          'memberUids': <Object?>['owner-uid'],
          'sharedStorageEnabled': true,
          'storageOverride': <String, Object?>{'privateStorageEnabled': false},
          'reconciliation': <String, Object?>{
            'requiredRevision': 3,
            'completedRevision': 3,
            'pending': false,
          },
        },
      ],
      'accessPatterns': <Object?>[
        <String, Object?>{
          'memberIndex': 0,
          'fileCount': 4,
          'folderCount': 2,
          'sharedFileCount': 1,
          'usageBytes': 2048,
        },
      ],
      'auditLogsScope': 'business_privacy_v2',
      'auditLogsComplete': true,
      'auditLogs': <Object?>[
        <String, Object?>{
          'id': 'log-1',
          'action': 'company.member_permissions_updated',
          'title': 'Company user permissions updated',
          'actorMemberId': 'owner-uid',
          'actorPresent': true,
        },
      ],
    });

    expect(dashboard.company?.name, 'Acme Secure Storage');
    expect(dashboard.company?.domain, 'example.test');
    expect(
      dashboard.company?.storagePolicy.privateStorageEnabledByDefault,
      isFalse,
    );
    expect(
      dashboard.company?.storagePolicy.defaultPrivateQuotaBytes,
      1073741824,
    );
    expect(dashboard.company?.storageInventory.available, isTrue);
    expect(dashboard.company?.storageInventory.metadataUsageBytes, 3072);
    expect(dashboard.company?.storageInventory.orphanObjectCount, 1);
    expect(dashboard.company?.storageInventory.missingObjectCount, 2);
    expect(dashboard.company?.storageInventory.needsAttention, isTrue);
    expect(dashboard.canManage, isTrue);
    expect(dashboard.company?.reconciliation.requiredRevision, 7);
    expect(dashboard.company?.reconciliation.completedRevision, 5);
    expect(dashboard.company?.reconciliation.pending, isTrue);
    expect(dashboard.members.single.role, 'owner');
    expect(dashboard.members.single.permissions['manageMembers'], isTrue);
    expect(dashboard.members.single.accessScopes, contains('audit_logs'));
    expect(dashboard.members.single.groupIds, contains('engineering'));
    expect(dashboard.members.single.encryptionReady, isTrue);
    expect(dashboard.members.single.encryptionKeyId, 'opaque-key-id');
    expect(
      dashboard.members.single.storageOverride.privateStorageEnabled,
      isTrue,
    );
    expect(dashboard.groups.single.name, 'Engineering');
    expect(dashboard.groups.single.reconciliation.pending, isFalse);
    expect(dashboard.groups.single.memberUids, contains('owner-uid'));
    expect(
      dashboard.groups.single.storageOverride.privateStorageEnabled,
      isFalse,
    );
    expect(dashboard.accessPatterns.single.usageBytes, 2048);
    expect(dashboard.accessPatternsAvailable, isTrue);
    expect(dashboard.accessPatternsComplete, isTrue);
    expect(dashboard.auditLogsAvailable, isTrue);
    expect(dashboard.auditLogsComplete, isTrue);
    expect(dashboard.auditLogs.single.actorMemberId, 'owner-uid');
    expect(dashboard.auditLogs.single.actorPresent, isTrue);
  });

  test('legacy audit emails are not retained in the client model', () {
    final entry = CompanyAuditLogEntry.fromMap(<String, Object?>{
      'id': 'legacy-log',
      'action': 'company.member_invited',
      'title': 'Company user invited',
      'actorEmail': 'private-actor@example.test',
      'targetEmail': 'private-target@example.test',
    });

    expect(entry.actorMemberId, isNull);
    expect(entry.targetMemberId, isNull);
    expect(entry.actorPresent, isTrue);
    expect(entry.targetPresent, isTrue);
    expect(entry.toString(), isNot(contains('private-actor@example.test')));
    expect(entry.toString(), isNot(contains('private-target@example.test')));
  });

  test('audit titles use a closed client vocabulary and discard details', () {
    final entry = CompanyAuditLogEntry.fromMap(<String, Object?>{
      'id': 'hostile-log',
      'action': 'company.member_invited',
      'title': 'Bearer private-token person@example.test C:\\private\\file',
      'details': <String, Object?>{
        'privateNote': 'Highly private customer content',
      },
    });
    final unknown = CompanyAuditLogEntry.fromMap(<String, Object?>{
      'action': 'private.custom.action',
      'title': 'Private custom title',
    });
    final revoked = CompanyAuditLogEntry.fromMap(<String, Object?>{
      'action': 'company.member_invitation_revoked',
      'title': 'Hostile custom revocation title',
    });

    expect(entry.action, 'company.member_invited');
    expect(entry.title, 'Company user invited');
    expect(entry.toString(), isNot(contains('private-token')));
    expect(entry.toString(), isNot(contains('person@example.test')));
    expect(entry.toString(), isNot(contains('Highly private')));
    expect(unknown.action, 'company.event');
    expect(unknown.title, 'Company event');
    expect(revoked.action, 'company.member_invitation_revoked');
    expect(revoked.title, 'Company invitation revoked');
  });

  test('audit payloads without the privacy scope fail closed', () {
    final dashboard = CompanyDashboard.fromMap(<String, Object?>{
      'auditLogs': <Object?>[
        <String, Object?>{
          'action': 'company.member_added',
          'title': 'Private legacy title',
        },
      ],
    });

    expect(dashboard.auditLogsAvailable, isFalse);
    expect(dashboard.auditLogsComplete, isFalse);
    expect(dashboard.auditLogs, isEmpty);
  });

  test('legacy mixed-account access patterns fail closed', () {
    final dashboard = CompanyDashboard.fromMap(<String, Object?>{
      'accessPatterns': <Object?>[
        <String, Object?>{
          'memberIndex': 0,
          'email': 'private@example.test',
          'fileCount': 99,
          'usageBytes': 999999,
          'lastAccountActivityTitle': 'Opened personal tax return',
        },
      ],
      'accountActivity': <Object?>[
        <String, Object?>{
          'id': 'personal-event',
          'title': 'Opened personal tax return',
        },
      ],
    });

    expect(dashboard.accessPatternsAvailable, isFalse);
    expect(dashboard.accessPatterns, isEmpty);
    expect(dashboard.toString(), isNot(contains('private@example.test')));
    expect(dashboard.toString(), isNot(contains('Opened personal tax return')));
  });

  test(
    'one-time Business invitations parse without stored identity labels',
    () {
      const code = 'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc';
      final dashboard = CompanyDashboard.fromMap(<String, Object?>{
        'members': <Object?>[
          <String, Object?>{
            'id': 'invite_opaque_record',
            'status': 'invited',
            'invitationFingerprint': 'A1B2C3D4E5',
            'invitationExpiresAt': '2026-08-09T12:00:00.000Z',
          },
        ],
        'pendingInvitation': <String, Object?>{
          'version': 1,
          'code': code,
          'fingerprint': 'A1B2C3D4E5',
          'expiresAt': '2026-08-09T12:00:00.000Z',
        },
      });

      expect(dashboard.members.single.label, 'Pending invitation • A1B2C3D4E5');
      expect(dashboard.members.single.label, isNot(contains('invite_opaque')));
      expect(dashboard.pendingInvitation?.code, code);
      expect(dashboard.pendingInvitation?.fingerprint, 'A1B2C3D4E5');
      expect(
        dashboard.copyWith(clearPendingInvitation: true).pendingInvitation,
        isNull,
      );
    },
  );

  test('member fallback labels never render provider identifiers', () {
    const member = CompanyMember(
      id: 'private-member-document-id',
      uid: 'private-firebase-uid',
    );

    expect(member.label, 'Company member');
    expect(member.label, isNot(contains('private-member-document-id')));
    expect(member.label, isNot(contains('private-firebase-uid')));
    expect(
      const CompanyMember(id: 'legacy', status: 'invited').isLegacyInvitation,
      isTrue,
    );
  });

  test('reconciliation counters fail closed when completion is ahead', () {
    final state = BusinessReconciliationState.fromMap(<String, Object?>{
      'requiredRevision': 4,
      'completedRevision': 99,
      'pending': false,
    });

    expect(state.requiredRevision, 4);
    expect(state.completedRevision, 0);
    expect(state.pending, isTrue);
  });

  test('CompanySession distinguishes business access from company setup', () {
    final active = CompanySession.fromMap(<String, Object?>{
      'company': <String, Object?>{
        'id': 'company-1',
        'name': 'Acme Secure Storage',
      },
      'currentMember': <String, Object?>{
        'id': 'admin-1',
        'uid': 'admin-1',
        'role': 'admin',
        'status': 'active',
      },
      'canManage': true,
      'canCreate': false,
    });
    final setup = CompanySession.fromMap(<String, Object?>{
      'canCreate': true,
      'canManage': false,
    });

    expect(active.hasActiveMembership, isTrue);
    expect(active.canManage, isTrue);
    expect(setup.company, isNull);
    expect(setup.canCreate, isTrue);
    expect(setup.hasActiveMembership, isFalse);
  });

  test('protected metadata fails closed when its envelope is malformed', () {
    final company = CompanyProfile.fromMap(<String, Object?>{
      'id': 'company-1',
      'name': 'Encrypted company',
      'metadataProtected': true,
      'metadataReadable': true,
      'encryptedMetadata': <String, Object?>{'format': 'unsupported'},
    });
    final group = CompanyGroup.fromMap(<String, Object?>{
      'id': 'group-1',
      'name': 'Encrypted group',
      'metadataProtected': true,
      'metadataReadable': true,
      'encryptedMetadata': <String, Object?>{'format': 'unsupported'},
    });

    expect(company.metadataProtected, isTrue);
    expect(company.metadataReadable, isFalse);
    expect(company.encryptedMetadata, isNull);
    expect(group.metadataProtected, isTrue);
    expect(group.metadataReadable, isFalse);
    expect(group.encryptedMetadata, isNull);
  });

  test('invalid Business inventory fails closed without negative totals', () {
    final invalid = CompanyStorageInventory.fromMap(<String, Object?>{
      'version': 99,
      'status': 'healthy',
      'metadataUsageBytes': -1,
    });
    final bounded = CompanyStorageInventory.fromMap(<String, Object?>{
      'version': 1,
      'status': 'partial',
      'complete': false,
      'metadataUsageBytes': -1,
      'objectCount': -5,
    });

    expect(invalid.available, isFalse);
    expect(invalid.healthy, isFalse);
    expect(bounded.available, isTrue);
    expect(bounded.metadataUsageBytes, 0);
    expect(bounded.objectCount, 0);
    expect(bounded.needsAttention, isFalse);
  });

  test('company and group writes send no plaintext labels', () async {
    final calls = <String, Map<String, Object?>>{};
    final service = CompanyAdminService(
      callable: (functionName, payload) async {
        calls[functionName] = Map<String, Object?>.from(payload);
        return <String, Object?>{'canCreate': false, 'canManage': true};
      },
      metadataProtection: const _FakeMetadataProtection(),
    );

    await service.createCompany(
      name: 'Private Company',
      domain: 'private.example',
    );
    await service.createGroup(
      name: 'Secret Group',
      description: 'Confidential roadmap',
      memberUids: const <String>['member-1'],
    );

    expect(calls['createCompanyProfile'], <String, Object?>{
      'identity': <String, Object?>{'protected': true},
      'encryptedMetadata': <String, Object?>{'ciphertext': 'company'},
    });
    expect(calls['createCompanyProfile'], isNot(contains('name')));
    expect(calls['createCompanyProfile'], isNot(contains('domain')));
    expect(calls['createCompanyGroup'], isNot(contains('name')));
    expect(calls['createCompanyGroup'], isNot(contains('description')));
    expect(calls['createCompanyGroup']?['encryptedMetadata'], <String, Object?>{
      'ciphertext': 'group',
    });
  });

  test('invitation service sends no identity and claims by code', () async {
    const code = 'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc';
    final calls = <String, Map<String, Object?>>{};
    final service = CompanyAdminService(
      callable: (functionName, payload) async {
        calls[functionName] = Map<String, Object?>.from(payload);
        if (functionName == 'addCompanyMember') {
          return <String, Object?>{
            'pendingInvitation': <String, Object?>{
              'version': 1,
              'code': code,
              'fingerprint': 'A1B2C3D4E5',
              'expiresAt': '2026-08-09T12:00:00.000Z',
            },
          };
        }
        return <String, Object?>{'canCreate': false, 'canManage': false};
      },
    );

    final created = await service.addMember(role: 'member');
    await service.claimInvitation(code);
    await service.revokeInvitation(memberId: ' invite_opaque ');

    expect(calls['addCompanyMember'], <String, Object?>{
      'invitationMode': 'token_v2',
      'role': 'member',
      'permissions': const <String, bool>{},
      'accessScopes': const <String>['personal_workspace'],
    });
    expect(calls['addCompanyMember'], isNot(contains('email')));
    expect(calls['addCompanyMember'], isNot(contains('displayName')));
    expect(created.pendingInvitation?.code, code);
    expect(calls['claimCompanyInvitation'], <String, Object?>{'code': code});
    expect(calls['revokeCompanyInvitation'], <String, Object?>{
      'memberId': 'invite_opaque',
    });
  });

  test('invitation revocation rejects an empty local reference', () async {
    var called = false;
    final service = CompanyAdminService(
      callable: (_, _) async {
        called = true;
        return <String, Object?>{};
      },
    );

    await expectLater(
      service.revokeInvitation(memberId: ' '),
      throwsA(isA<CompanyAdminException>()),
    );
    expect(called, isFalse);
  });

  test(
    'reconciliation acknowledgement sends only scope and revision',
    () async {
      String? calledFunction;
      Map<String, Object?>? calledPayload;
      final service = CompanyAdminService(
        callable: (functionName, payload) async {
          calledFunction = functionName;
          calledPayload = Map<String, Object?>.from(payload);
          return <String, Object?>{
            'ok': true,
            'reconciliation': <String, Object?>{
              'requiredRevision': 9,
              'completedRevision': 9,
              'pending': false,
            },
          };
        },
      );

      final result = await service.acknowledgeReconciliation(
        storageScope: 'group',
        groupId: 'group-opaque-id',
        expectedRevision: 9,
      );

      expect(calledFunction, 'acknowledgeBusinessReconciliation');
      expect(calledPayload, <String, Object?>{
        'storageScope': 'group',
        'groupId': 'group-opaque-id',
        'expectedRevision': 9,
      });
      expect(calledPayload, isNot(contains('fileId')));
      expect(calledPayload, isNot(contains('memberId')));
      expect(calledPayload, isNot(contains('reason')));
      expect(result.pending, isFalse);
    },
  );

  test('reconciliation acknowledgement rejects a stale response', () async {
    final service = CompanyAdminService(
      callable: (_, _) async => <String, Object?>{
        'reconciliation': <String, Object?>{
          'requiredRevision': 10,
          'completedRevision': 9,
          'pending': true,
        },
      },
    );

    await expectLater(
      service.acknowledgeReconciliation(
        storageScope: 'company_shared',
        expectedRevision: 9,
      ),
      throwsA(isA<CompanyAdminException>()),
    );
  });

  test('unexpected callable details never reach Business users', () async {
    final service = CompanyAdminService(
      callable: (_, _) async {
        throw StateError(
          'host=private.example member=private@example.test file=payroll.xlsx',
        );
      },
    );

    await expectLater(
      service.fetchDashboard(),
      throwsA(
        isA<CompanyAdminException>()
            .having(
              (error) => error.message,
              'message',
              'The Business request could not be completed. Refresh and try again.',
            )
            .having(
              (error) => error.message,
              'private details',
              isNot(contains('private.example')),
            )
            .having(
              (error) => error.message,
              'filename',
              isNot(contains('payroll.xlsx')),
            ),
      ),
    );
  });

  test(
    'protected metadata failures cannot expose member or object details',
    () async {
      const secret =
          'member=private-user-id object=companies/private/payroll.xlsx';
      final service = CompanyAdminService(
        callable: (_, _) async => <String, Object?>{
          'canCreate': false,
          'canManage': true,
        },
        metadataProtection: const _FailingMetadataProtection(secret),
      );

      try {
        await service.fetchDashboard();
        fail('Expected protected metadata preparation to fail.');
      } on CompanyAdminException catch (error) {
        expect(error.kind, CompanyAdminFailureKind.protectedMetadata);
        expect(
          error.message,
          'Protected Business labels could not be prepared on this device. Refresh access and try again.',
        );
        expect(error.message, isNot(contains('private-user-id')));
        expect(error.message, isNot(contains('payroll.xlsx')));
        expect(error.toString(), 'CompanyAdminException(protectedMetadata)');
        expect(error.toString(), isNot(contains(secret)));
      }
    },
  );
}

class _FakeMetadataProtection implements CompanyMetadataProtection {
  const _FakeMetadataProtection();

  @override
  Future<CompanyDashboard> decryptDashboard(CompanyDashboard dashboard) async {
    return dashboard;
  }

  @override
  Future<CompanySession> decryptSession(CompanySession session) async {
    return session;
  }

  @override
  Future<Map<String, Object?>> prepareCompanyCreate({
    required String name,
    String? domain,
  }) async {
    return <String, Object?>{
      'identity': <String, Object?>{'protected': true},
      'encryptedMetadata': <String, Object?>{'ciphertext': 'company'},
    };
  }

  @override
  Future<Map<String, Object?>> prepareCompanyUpdate({
    required CompanyProfile company,
    required String name,
    String? domain,
  }) async {
    return <String, Object?>{
      'encryptedMetadata': <String, Object?>{'ciphertext': 'company'},
    };
  }

  @override
  Future<Map<String, Object?>> prepareGroupWrite({
    required String name,
    String? description,
    required List<String> memberUids,
    CompanyGroup? existing,
  }) async {
    return <String, Object?>{
      'encryptedMetadata': <String, Object?>{'ciphertext': 'group'},
    };
  }

  @override
  Future<int> refreshMetadataAccess({
    required CompanyProfile company,
    CompanyGroup? group,
  }) async {
    return 0;
  }
}

class _FailingMetadataProtection extends _FakeMetadataProtection {
  const _FailingMetadataProtection(this.detail);

  final String detail;

  @override
  Future<CompanyDashboard> decryptDashboard(CompanyDashboard dashboard) async {
    throw _TestMetadataProtectionFailure(detail);
  }
}

class _TestMetadataProtectionFailure
    implements CompanyMetadataProtectionFailure {
  const _TestMetadataProtectionFailure(this.message);

  @override
  final String message;
}
