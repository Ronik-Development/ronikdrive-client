import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_storage/src/business/business_reconciliation_queue.dart';
import 'package:cloud_storage/src/business/company_admin_service.dart';
import 'package:cloud_storage/src/privacy/local_private_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BusinessReconciliationPlanner', () {
    test('queues company shared access when a member is added', () {
      final targets = BusinessReconciliationPlanner.forAddedMember(
        companyId: 'company-one',
        status: 'active',
        accessScopes: const <String>['company_workspace'],
        permissions: const <String, bool>{'downloadFiles': true},
      );

      expect(targets, hasLength(1));
      expect(targets.single.location.storageScope, 'company_shared');
      expect(
        targets.single.reasons,
        contains(BusinessReconciliationReason.memberAdded),
      );
    });

    test('status changes identify shared and exact group spaces', () {
      const member = CompanyMember(
        id: 'member-one',
        uid: 'uid-one',
        status: 'active',
        accessScopes: <String>['company_workspace'],
        permissions: <String, bool>{'downloadFiles': true},
      );
      const groups = <CompanyGroup>[
        CompanyGroup(
          id: 'group-one',
          name: 'One',
          memberUids: <String>['uid-one'],
        ),
        CompanyGroup(
          id: 'group-two',
          name: 'Two',
          memberUids: <String>['uid-two'],
        ),
      ];

      final targets = BusinessReconciliationPlanner.forMemberChange(
        companyId: 'company-one',
        before: member,
        status: 'suspended',
        accessScopes: member.accessScopes,
        permissions: const <String, bool>{'downloadFiles': true},
        groups: groups,
      );

      expect(targets, hasLength(2));
      expect(
        targets.map((target) => target.location.storageScope),
        containsAll(<String>['company_shared', 'group']),
      );
      expect(
        targets
            .where((target) => target.location.storageScope == 'group')
            .single
            .location
            .groupId,
        'group-one',
      );
    });

    test('group membership edits queue only the edited group', () {
      const group = CompanyGroup(
        id: 'group-one',
        name: 'One',
        memberUids: <String>['uid-one', 'uid-two'],
      );

      final targets = BusinessReconciliationPlanner.forGroupChange(
        companyId: 'company-one',
        before: group,
        memberUids: const <String>['uid-one'],
        sharedStorageEnabled: true,
      );

      expect(targets, hasLength(1));
      expect(targets.single.location.groupId, 'group-one');
      expect(
        targets.single.reasons,
        contains(BusinessReconciliationReason.groupMembershipChanged),
      );
    });

    test('storage-only group changes do not create a stuck reminder', () {
      const group = CompanyGroup(
        id: 'group-one',
        name: 'One',
        memberUids: <String>['uid-one'],
        sharedStorageEnabled: true,
      );

      final targets = BusinessReconciliationPlanner.forGroupChange(
        companyId: 'company-one',
        before: group,
        memberUids: group.memberUids,
        sharedStorageEnabled: false,
      );

      expect(targets, isEmpty);
    });

    test(
      'discovers pending remote revisions without member or file details',
      () {
        const company = CompanyProfile(
          id: 'company-one',
          name: 'Private company label',
          reconciliation: BusinessReconciliationState(
            requiredRevision: 12,
            completedRevision: 10,
          ),
        );
        const groups = <CompanyGroup>[
          CompanyGroup(
            id: 'group-one',
            name: 'Private group label',
            reconciliation: BusinessReconciliationState(
              requiredRevision: 4,
              completedRevision: 2,
            ),
          ),
          CompanyGroup(
            id: 'group-complete',
            name: 'Complete',
            reconciliation: BusinessReconciliationState(
              requiredRevision: 3,
              completedRevision: 3,
            ),
          ),
        ];

        final targets = BusinessReconciliationPlanner.forRemoteState(
          company: company,
          groups: groups,
        );

        expect(targets, hasLength(2));
        expect(
          targets.map((target) => target.requiredRevision),
          containsAll(<int>[12, 4]),
        );
        final encoded = jsonEncode(
          targets.map((target) => target.toJson()).toList(growable: false),
        );
        expect(encoded, isNot(contains('Private company label')));
        expect(encoded, isNot(contains('Private group label')));
        expect(encoded, isNot(contains('memberId')));
        expect(encoded, isNot(contains('fileId')));
      },
    );

    test(
      'remote synchronization clears completed counters and preserves local work',
      () {
        final remoteBacked = BusinessReconciliationTarget(
          location: BusinessReconciliationLocation.companyShared(
            companyId: 'company-one',
          ),
          reasons: const <BusinessReconciliationReason>{
            BusinessReconciliationReason.remoteAccessChanged,
          },
          requiredRevision: 4,
        );
        final localOnly = BusinessReconciliationTarget(
          location: BusinessReconciliationLocation.group(
            companyId: 'company-one',
            groupId: 'group-local',
          ),
          reasons: const <BusinessReconciliationReason>{
            BusinessReconciliationReason.groupMembershipChanged,
          },
        );
        const company = CompanyProfile(
          id: 'company-one',
          name: 'Private',
          reconciliation: BusinessReconciliationState(
            requiredRevision: 4,
            completedRevision: 4,
          ),
        );

        final synchronized =
            BusinessReconciliationPlanner.synchronizeRemoteState(
              existingTargets: <BusinessReconciliationTarget>[
                remoteBacked,
                localOnly,
              ],
              company: company,
              groups: const <CompanyGroup>[],
            );

        expect(synchronized, hasLength(1));
        expect(synchronized.single.location.groupId, 'group-local');
        expect(synchronized.single.requiredRevision, 0);
      },
    );

    test('remote synchronization merges a newer revision', () {
      final existing = BusinessReconciliationTarget(
        location: BusinessReconciliationLocation.companyShared(
          companyId: 'company-one',
        ),
        reasons: const <BusinessReconciliationReason>{
          BusinessReconciliationReason.memberAdded,
        },
        requiredRevision: 3,
      );
      const company = CompanyProfile(
        id: 'company-one',
        name: 'Private',
        reconciliation: BusinessReconciliationState(
          requiredRevision: 5,
          completedRevision: 2,
        ),
      );

      final synchronized = BusinessReconciliationPlanner.synchronizeRemoteState(
        existingTargets: <BusinessReconciliationTarget>[existing],
        company: company,
        groups: const <CompanyGroup>[],
      );

      expect(synchronized, hasLength(1));
      expect(synchronized.single.requiredRevision, 5);
      expect(
        synchronized.single.reasons,
        containsAll(<BusinessReconciliationReason>[
          BusinessReconciliationReason.memberAdded,
          BusinessReconciliationReason.remoteAccessChanged,
        ]),
      );
    });

    test(
      'download revocation identifies every space that held member keys',
      () {
        const member = CompanyMember(
          id: 'member-one',
          uid: 'uid-one',
          email: 'private-member@example.test',
          displayName: 'Private Member',
          status: 'active',
          accessScopes: <String>['company_workspace'],
          permissions: <String, bool>{
            'downloadFiles': true,
            'uploadFiles': true,
          },
        );
        const groups = <CompanyGroup>[
          CompanyGroup(
            id: 'group-one',
            name: 'One',
            memberUids: <String>['uid-one'],
          ),
        ];

        final targets = BusinessReconciliationPlanner.forMemberChange(
          companyId: 'company-one',
          before: member,
          status: 'active',
          accessScopes: member.accessScopes,
          permissions: const <String, bool>{
            'downloadFiles': false,
            'uploadFiles': true,
          },
          groups: groups,
        );

        expect(targets, hasLength(2));
        expect(
          targets.map((target) => target.location.storageScope),
          containsAll(<String>['company_shared', 'group']),
        );
        final serialized = jsonEncode(
          targets.map((target) => target.toJson()).toList(growable: false),
        );
        expect(serialized, isNot(contains('uid-one')));
        expect(serialized, isNot(contains('member-one')));
        expect(serialized, isNot(contains('private-member@example.test')));
        expect(serialized, isNot(contains('Private Member')));
      },
    );
  });

  group('BusinessReconciliationQueueStore', () {
    const uid = 'queue-user';
    const scope = 'queue-project';

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
      'persists only encrypted queue state and restores merged targets',
      () async {
        final preferences = await SharedPreferences.getInstance();
        final keyStore = _MemoryKeyStore();
        final codec = LocalPrivateCacheCodec(keyStore: keyStore);
        final store = _store(
          preferences: preferences,
          codec: codec,
          uid: uid,
          scope: scope,
        );
        final first = BusinessReconciliationTarget(
          location: BusinessReconciliationLocation.group(
            companyId: 'private-company-id',
            groupId: 'private-group-id',
          ),
          reasons: const <BusinessReconciliationReason>{
            BusinessReconciliationReason.groupMembershipChanged,
          },
          requiredRevision: 6,
        );
        final second = BusinessReconciliationTarget(
          location: first.location,
          reasons: const <BusinessReconciliationReason>{
            BusinessReconciliationReason.groupStorageChanged,
          },
          requiredRevision: 9,
        );

        await store.save(<BusinessReconciliationTarget>[first, second]);

        final preferenceKey = LocalPrivateCachePreferences.scopedPreferenceKey(
          LocalPrivateCacheCodec.businessReconciliationQueuePreferenceKey,
          uid,
          scope: scope,
        );
        final stored = preferences.getString(preferenceKey);
        expect(stored, startsWith(LocalPrivateCacheCodec.encryptedPrefix));
        expect(stored, isNot(contains('private-company-id')));
        expect(stored, isNot(contains('private-group-id')));
        expect(stored, isNot(contains('groupMembershipChanged')));

        final load = await store.load();
        expect(load.targets, hasLength(1));
        expect(
          load.targets.single.reasons,
          containsAll(<BusinessReconciliationReason>[
            BusinessReconciliationReason.groupMembershipChanged,
            BusinessReconciliationReason.groupStorageChanged,
          ]),
        );
        expect(load.targets.single.requiredRevision, 9);
      },
    );

    test('discards structurally invalid authenticated queue data', () async {
      final preferences = await SharedPreferences.getInstance();
      final codec = LocalPrivateCacheCodec(keyStore: _MemoryKeyStore());
      final cache = LocalPrivateCachePreferences(
        preferences: preferences,
        uid: uid,
        scope: scope,
        codec: codec,
      );
      await cache.write(
        baseKey:
            LocalPrivateCacheCodec.businessReconciliationQueuePreferenceKey,
        namespace: LocalPrivateCacheCodec.businessReconciliationQueueNamespace,
        value: '{"version":99,"targets":[]}',
      );

      final load = await BusinessReconciliationQueueStore(
        privateCache: cache,
      ).load();

      expect(load.targets, isEmpty);
      expect(load.discardedCorruptValue, isTrue);
      expect(
        preferences.containsKey(
          LocalPrivateCachePreferences.scopedPreferenceKey(
            LocalPrivateCacheCodec.businessReconciliationQueuePreferenceKey,
            uid,
            scope: scope,
          ),
        ),
        isFalse,
      );
    });

    test('retains ciphertext while the credential store is locked', () async {
      final preferences = await SharedPreferences.getInstance();
      final writableCodec = LocalPrivateCacheCodec(keyStore: _MemoryKeyStore());
      final writableStore = _store(
        preferences: preferences,
        codec: writableCodec,
        uid: uid,
        scope: scope,
      );
      await writableStore.save(<BusinessReconciliationTarget>[
        BusinessReconciliationTarget(
          location: BusinessReconciliationLocation.companyShared(
            companyId: 'company-one',
          ),
          reasons: const <BusinessReconciliationReason>{
            BusinessReconciliationReason.memberAccessChanged,
          },
        ),
      ]);
      final preferenceKey = LocalPrivateCachePreferences.scopedPreferenceKey(
        LocalPrivateCacheCodec.businessReconciliationQueuePreferenceKey,
        uid,
        scope: scope,
      );
      final ciphertext = preferences.getString(preferenceKey);

      final lockedStore = _store(
        preferences: preferences,
        codec: LocalPrivateCacheCodec(keyStore: _LockedKeyStore()),
        uid: uid,
        scope: scope,
      );
      final load = await lockedStore.load();

      expect(load.temporarilyUnavailable, isTrue);
      expect(load.targets, isEmpty);
      expect(preferences.getString(preferenceKey), ciphertext);
    });
  });
}

BusinessReconciliationQueueStore _store({
  required SharedPreferences preferences,
  required LocalPrivateCacheCodec codec,
  required String uid,
  required String scope,
}) {
  return BusinessReconciliationQueueStore(
    privateCache: LocalPrivateCachePreferences(
      preferences: preferences,
      uid: uid,
      scope: scope,
      codec: codec,
    ),
  );
}

class _MemoryKeyStore implements LocalPrivateCacheKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _LockedKeyStore implements LocalPrivateCacheKeyStore {
  @override
  Future<void> delete(String key) async {
    throw StateError('locked');
  }

  @override
  Future<String?> read(String key) async {
    throw StateError('locked');
  }

  @override
  Future<void> write(String key, String value) async {
    throw StateError('locked');
  }
}
