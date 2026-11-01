import 'dart:convert';

import '../privacy/local_private_cache.dart';
import 'company_admin_service.dart';

enum BusinessReconciliationReason {
  memberAdded,
  memberAccessChanged,
  memberStatusChanged,
  groupMembershipChanged,
  groupStorageChanged,
  remoteAccessChanged,
}

class BusinessReconciliationLocation {
  const BusinessReconciliationLocation._({
    required this.companyId,
    required this.storageScope,
    this.groupId,
  });

  factory BusinessReconciliationLocation.companyShared({
    required String companyId,
  }) {
    return BusinessReconciliationLocation._(
      companyId: _requiredIdentifier(companyId, 'company'),
      storageScope: 'company_shared',
    );
  }

  factory BusinessReconciliationLocation.group({
    required String companyId,
    required String groupId,
  }) {
    return BusinessReconciliationLocation._(
      companyId: _requiredIdentifier(companyId, 'company'),
      storageScope: 'group',
      groupId: _requiredIdentifier(groupId, 'group'),
    );
  }

  final String companyId;
  final String storageScope;
  final String? groupId;

  String get identity => '$companyId\u0000$storageScope\u0000${groupId ?? ''}';

  @override
  bool operator ==(Object other) {
    return other is BusinessReconciliationLocation &&
        other.companyId == companyId &&
        other.storageScope == storageScope &&
        other.groupId == groupId;
  }

  @override
  int get hashCode => Object.hash(companyId, storageScope, groupId);
}

class BusinessReconciliationTarget {
  BusinessReconciliationTarget({
    required this.location,
    required Iterable<BusinessReconciliationReason> reasons,
    this.requiredRevision = 0,
    DateTime? queuedAt,
  }) : reasons = Set<BusinessReconciliationReason>.unmodifiable(reasons),
       queuedAt = (queuedAt ?? DateTime.now()).toUtc() {
    if (this.reasons.isEmpty) {
      throw const FormatException(
        'A Business reconciliation reason is required.',
      );
    }
    if (requiredRevision < 0 || requiredRevision > 2147483647) {
      throw const FormatException(
        'The Business reconciliation revision is invalid.',
      );
    }
  }

  factory BusinessReconciliationTarget.fromJson(Map<String, Object?> json) {
    final companyId = _requiredIdentifier(
      json['companyId']?.toString() ?? '',
      'company',
    );
    final storageScope = json['storageScope']?.toString().trim() ?? '';
    final location = switch (storageScope) {
      'company_shared' => BusinessReconciliationLocation.companyShared(
        companyId: companyId,
      ),
      'group' => BusinessReconciliationLocation.group(
        companyId: companyId,
        groupId: json['groupId']?.toString() ?? '',
      ),
      _ => throw const FormatException(
        'The Business reconciliation storage scope is invalid.',
      ),
    };
    final rawReasons = json['reasons'];
    if (rawReasons is! Iterable) {
      throw const FormatException(
        'Business reconciliation reasons are invalid.',
      );
    }
    final reasons = rawReasons.map((value) {
      final name = value?.toString().trim() ?? '';
      return BusinessReconciliationReason.values.firstWhere(
        (candidate) => candidate.name == name,
        orElse: () => throw const FormatException(
          'A Business reconciliation reason is unsupported.',
        ),
      );
    }).toSet();
    final queuedAt = DateTime.tryParse(
      json['queuedAt']?.toString() ?? '',
    )?.toUtc();
    if (queuedAt == null) {
      throw const FormatException(
        'The Business reconciliation timestamp is invalid.',
      );
    }
    return BusinessReconciliationTarget(
      location: location,
      reasons: reasons,
      requiredRevision: _optionalRevision(json['requiredRevision']),
      queuedAt: queuedAt,
    );
  }

  final BusinessReconciliationLocation location;
  final Set<BusinessReconciliationReason> reasons;
  final int requiredRevision;
  final DateTime queuedAt;

  BusinessReconciliationTarget merge(BusinessReconciliationTarget other) {
    if (location != other.location) {
      throw const FormatException(
        'Only the same Business workspace can be merged.',
      );
    }
    return BusinessReconciliationTarget(
      location: location,
      reasons: <BusinessReconciliationReason>{...reasons, ...other.reasons},
      requiredRevision: requiredRevision > other.requiredRevision
          ? requiredRevision
          : other.requiredRevision,
      queuedAt: queuedAt.isAfter(other.queuedAt) ? queuedAt : other.queuedAt,
    );
  }

  Map<String, Object?> toJson() {
    final sortedReasons = reasons.map((reason) => reason.name).toList()..sort();
    return <String, Object?>{
      'companyId': location.companyId,
      'storageScope': location.storageScope,
      if (location.groupId != null) 'groupId': location.groupId,
      'reasons': sortedReasons,
      if (requiredRevision > 0) 'requiredRevision': requiredRevision,
      'queuedAt': queuedAt.toIso8601String(),
    };
  }
}

class BusinessReconciliationQueueLoad {
  const BusinessReconciliationQueueLoad({
    this.targets = const <BusinessReconciliationTarget>[],
    this.temporarilyUnavailable = false,
    this.discardedCorruptValue = false,
  });

  final List<BusinessReconciliationTarget> targets;
  final bool temporarilyUnavailable;
  final bool discardedCorruptValue;
}

class BusinessReconciliationQueueStore {
  BusinessReconciliationQueueStore({
    required LocalPrivateCachePreferences privateCache,
  }) : _privateCache = privateCache;

  static const int _schemaVersion = 1;
  static const int maxTargets = 64;

  final LocalPrivateCachePreferences _privateCache;

  Future<BusinessReconciliationQueueLoad> load() async {
    final read = await _privateCache.read(
      baseKey: LocalPrivateCacheCodec.businessReconciliationQueuePreferenceKey,
      namespace: LocalPrivateCacheCodec.businessReconciliationQueueNamespace,
    );
    if (read.temporarilyUnavailable) {
      return const BusinessReconciliationQueueLoad(
        temporarilyUnavailable: true,
      );
    }
    if (read.value == null) {
      return BusinessReconciliationQueueLoad(
        discardedCorruptValue: read.discardedCorruptValue,
      );
    }
    try {
      final decoded = jsonDecode(read.value!);
      if (decoded is! Map ||
          decoded['version'] != _schemaVersion ||
          decoded['targets'] is! List) {
        throw const FormatException(
          'The Business reconciliation queue is invalid.',
        );
      }
      final targets = <BusinessReconciliationTarget>[];
      final identities = <String>{};
      for (final value in decoded['targets'] as List) {
        if (value is! Map) {
          throw const FormatException(
            'A Business reconciliation target is invalid.',
          );
        }
        final target = BusinessReconciliationTarget.fromJson(
          Map<String, Object?>.fromEntries(
            value.entries.map(
              (entry) => MapEntry(entry.key.toString(), entry.value),
            ),
          ),
        );
        if (!identities.add(target.location.identity)) {
          throw const FormatException(
            'The Business reconciliation queue contains duplicates.',
          );
        }
        targets.add(target);
      }
      if (targets.length > maxTargets) {
        throw const FormatException(
          'The Business reconciliation queue is too large.',
        );
      }
      targets.sort((first, second) {
        return second.queuedAt.compareTo(first.queuedAt);
      });
      return BusinessReconciliationQueueLoad(targets: targets);
    } on FormatException {
      await clear();
      return const BusinessReconciliationQueueLoad(discardedCorruptValue: true);
    } on Exception {
      await clear();
      return const BusinessReconciliationQueueLoad(discardedCorruptValue: true);
    }
  }

  Future<void> save(Iterable<BusinessReconciliationTarget> targets) async {
    final byIdentity = <String, BusinessReconciliationTarget>{};
    for (final target in targets) {
      final identity = target.location.identity;
      final existing = byIdentity[identity];
      byIdentity[identity] = existing == null ? target : existing.merge(target);
    }
    final normalized = byIdentity.values.toList()
      ..sort((first, second) {
        return second.queuedAt.compareTo(first.queuedAt);
      });
    if (normalized.length > maxTargets) {
      normalized.removeRange(maxTargets, normalized.length);
    }
    if (normalized.isEmpty) {
      await clear();
      return;
    }
    await _privateCache.write(
      baseKey: LocalPrivateCacheCodec.businessReconciliationQueuePreferenceKey,
      namespace: LocalPrivateCacheCodec.businessReconciliationQueueNamespace,
      value: jsonEncode(<String, Object?>{
        'version': _schemaVersion,
        'targets': normalized
            .map((target) => target.toJson())
            .toList(growable: false),
      }),
    );
  }

  Future<void> clear() {
    return _privateCache.write(
      baseKey: LocalPrivateCacheCodec.businessReconciliationQueuePreferenceKey,
      namespace: LocalPrivateCacheCodec.businessReconciliationQueueNamespace,
      value: null,
    );
  }
}

class BusinessReconciliationPlanner {
  const BusinessReconciliationPlanner._();

  static List<BusinessReconciliationTarget> forAddedMember({
    required String companyId,
    required String status,
    required Iterable<String> accessScopes,
    required Map<String, bool> permissions,
  }) {
    if (!_hasCompanySharedKeyAccess(status, accessScopes, permissions)) {
      return const <BusinessReconciliationTarget>[];
    }
    return <BusinessReconciliationTarget>[
      BusinessReconciliationTarget(
        location: BusinessReconciliationLocation.companyShared(
          companyId: companyId,
        ),
        reasons: const <BusinessReconciliationReason>{
          BusinessReconciliationReason.memberAdded,
        },
      ),
    ];
  }

  static List<BusinessReconciliationTarget> forRemoteState({
    required CompanyProfile company,
    required Iterable<CompanyGroup> groups,
  }) {
    final targets = <BusinessReconciliationTarget>[];
    if (company.reconciliation.pending) {
      targets.add(
        BusinessReconciliationTarget(
          location: BusinessReconciliationLocation.companyShared(
            companyId: company.id,
          ),
          reasons: const <BusinessReconciliationReason>{
            BusinessReconciliationReason.remoteAccessChanged,
          },
          requiredRevision: company.reconciliation.requiredRevision,
        ),
      );
    }
    for (final group in groups) {
      if (!group.reconciliation.pending) {
        continue;
      }
      targets.add(
        BusinessReconciliationTarget(
          location: BusinessReconciliationLocation.group(
            companyId: company.id,
            groupId: group.id,
          ),
          reasons: const <BusinessReconciliationReason>{
            BusinessReconciliationReason.remoteAccessChanged,
          },
          requiredRevision: group.reconciliation.requiredRevision,
        ),
      );
    }
    return targets;
  }

  static List<BusinessReconciliationTarget> synchronizeRemoteState({
    required Iterable<BusinessReconciliationTarget> existingTargets,
    required CompanyProfile company,
    required Iterable<CompanyGroup> groups,
  }) {
    final groupList = groups.toList(growable: false);
    final observedStates = <String, BusinessReconciliationState>{
      BusinessReconciliationLocation.companyShared(
        companyId: company.id,
      ).identity: company.reconciliation,
      for (final group in groupList)
        BusinessReconciliationLocation.group(
          companyId: company.id,
          groupId: group.id,
        ).identity: group.reconciliation,
    };
    final merged = <String, BusinessReconciliationTarget>{};
    for (final target in existingTargets) {
      final state = observedStates[target.location.identity];
      final completedElsewhere =
          target.requiredRevision > 0 &&
          state != null &&
          state.completedRevision >= target.requiredRevision;
      if (!completedElsewhere) {
        merged[target.location.identity] = target;
      }
    }
    for (final target in forRemoteState(company: company, groups: groupList)) {
      final identity = target.location.identity;
      final existing = merged[identity];
      merged[identity] = existing == null ? target : existing.merge(target);
    }
    final result = merged.values.toList()
      ..sort((first, second) => second.queuedAt.compareTo(first.queuedAt));
    if (result.length > BusinessReconciliationQueueStore.maxTargets) {
      result.removeRange(
        BusinessReconciliationQueueStore.maxTargets,
        result.length,
      );
    }
    return result;
  }

  static List<BusinessReconciliationTarget> forMemberChange({
    required String companyId,
    required CompanyMember before,
    required String status,
    required Iterable<String> accessScopes,
    required Map<String, bool> permissions,
    required Iterable<CompanyGroup> groups,
  }) {
    final targets = <BusinessReconciliationTarget>[];
    final beforeShared = _hasCompanySharedKeyAccess(
      before.status,
      before.accessScopes,
      before.permissions,
    );
    final afterShared = _hasCompanySharedKeyAccess(
      status,
      accessScopes,
      permissions,
    );
    if (beforeShared != afterShared) {
      targets.add(
        BusinessReconciliationTarget(
          location: BusinessReconciliationLocation.companyShared(
            companyId: companyId,
          ),
          reasons: <BusinessReconciliationReason>{
            BusinessReconciliationReason.memberAccessChanged,
            if (before.status != status)
              BusinessReconciliationReason.memberStatusChanged,
          },
        ),
      );
    }

    final uid = before.uid?.trim();
    final beforeGroupAccess = _canReceiveKeys(
      before.status,
      before.permissions,
    );
    final afterGroupAccess = _canReceiveKeys(status, permissions);
    if (uid != null &&
        uid.isNotEmpty &&
        beforeGroupAccess != afterGroupAccess) {
      for (final group in groups) {
        if (group.memberUids.contains(uid)) {
          targets.add(
            BusinessReconciliationTarget(
              location: BusinessReconciliationLocation.group(
                companyId: companyId,
                groupId: group.id,
              ),
              reasons: const <BusinessReconciliationReason>{
                BusinessReconciliationReason.memberStatusChanged,
              },
            ),
          );
        }
      }
    }
    return _mergeTargets(targets);
  }

  static List<BusinessReconciliationTarget> forGroupChange({
    required String companyId,
    required CompanyGroup before,
    required Iterable<String> memberUids,
    required bool sharedStorageEnabled,
  }) {
    final beforeMembers = before.memberUids.toSet();
    final afterMembers = memberUids.toSet();
    final membershipChanged =
        beforeMembers.length != afterMembers.length ||
        !beforeMembers.containsAll(afterMembers);
    final storageChanged = before.sharedStorageEnabled != sharedStorageEnabled;
    // Storage can only be disabled or emptied after the backend proves the
    // group contains no files/folders. A storage-only toggle therefore has no
    // historical member keys to rotate and must not create a stuck reminder.
    if (!membershipChanged) {
      return const <BusinessReconciliationTarget>[];
    }
    return <BusinessReconciliationTarget>[
      BusinessReconciliationTarget(
        location: BusinessReconciliationLocation.group(
          companyId: companyId,
          groupId: before.id,
        ),
        reasons: <BusinessReconciliationReason>{
          if (membershipChanged)
            BusinessReconciliationReason.groupMembershipChanged,
          if (storageChanged) BusinessReconciliationReason.groupStorageChanged,
        },
      ),
    ];
  }

  static bool _hasCompanySharedKeyAccess(
    String status,
    Iterable<String> accessScopes,
    Map<String, bool> permissions,
  ) {
    if (!_canReceiveKeys(status, permissions)) {
      return false;
    }
    final normalized = accessScopes
        .map((scope) => scope.trim().toLowerCase())
        .toSet();
    return normalized.contains('company_workspace') ||
        normalized.contains('shared_folders');
  }

  static bool _canReceiveKeys(String status, Map<String, bool> permissions) {
    return status.trim().toLowerCase() == 'active' &&
        permissions['downloadFiles'] == true;
  }

  static List<BusinessReconciliationTarget> _mergeTargets(
    Iterable<BusinessReconciliationTarget> targets,
  ) {
    final merged = <String, BusinessReconciliationTarget>{};
    for (final target in targets) {
      final identity = target.location.identity;
      final existing = merged[identity];
      merged[identity] = existing == null ? target : existing.merge(target);
    }
    return merged.values.toList(growable: false);
  }
}

String _requiredIdentifier(String value, String label) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 256) {
    throw FormatException('A valid Business $label identifier is required.');
  }
  return normalized;
}

int _optionalRevision(Object? value) {
  if (value == null) {
    return 0;
  }
  final revision = value is int ? value : int.tryParse(value.toString());
  if (revision == null || revision < 0 || revision > 2147483647) {
    throw const FormatException(
      'The Business reconciliation revision is invalid.',
    );
  }
  return revision;
}
