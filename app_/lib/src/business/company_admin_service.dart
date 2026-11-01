import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import '../security/business_encryption_registry.dart';
import '../security/business_encryption_service.dart';
import '../security/business_metadata_encryption.dart';
import '../shared/user_facing_cloud_error.dart';

typedef CompanyAdminCallable =
    Future<Map<String, Object?>> Function(
      String functionName,
      Map<String, Object?> data,
    );

enum CompanyAdminFailureKind {
  validation,
  reconciliation,
  protectedMetadata,
  businessEncryption,
  cloud,
}

class CompanyAdminException implements Exception {
  const CompanyAdminException._(this.kind, this.message);

  final CompanyAdminFailureKind kind;
  final String message;

  @override
  String toString() => 'CompanyAdminException(${kind.name})';
}

class CompanyStoragePolicy {
  const CompanyStoragePolicy({
    this.privateStorageEnabledByDefault = true,
    this.sharedStorageEnabled = true,
    this.defaultPrivateQuotaBytes,
  });

  factory CompanyStoragePolicy.fromMap(Map<String, Object?> data) {
    return CompanyStoragePolicy(
      privateStorageEnabledByDefault:
          data['privateStorageEnabledByDefault'] != false,
      sharedStorageEnabled: data['sharedStorageEnabled'] != false,
      defaultPrivateQuotaBytes: _nullableInt(data['defaultPrivateQuotaBytes']),
    );
  }

  final bool privateStorageEnabledByDefault;
  final bool sharedStorageEnabled;
  final int? defaultPrivateQuotaBytes;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'privateStorageEnabledByDefault': privateStorageEnabledByDefault,
      'sharedStorageEnabled': sharedStorageEnabled,
      'defaultPrivateQuotaBytes': defaultPrivateQuotaBytes,
    };
  }
}

class CompanyStorageInventory {
  const CompanyStorageInventory({
    this.available = false,
    this.status = 'not_checked',
    this.complete = false,
    this.observedBytes = 0,
    this.metadataUsageBytes = 0,
    this.objectCount = 0,
    this.orphanObjectCount = 0,
    this.missingObjectCount = 0,
    this.checkedAt,
  });

  factory CompanyStorageInventory.fromMap(Map<String, Object?> data) {
    final version = _nullableInt(data['version']);
    final status = _string(data['status'])?.toLowerCase();
    final validStatus = const <String>{
      'healthy',
      'partial',
      'diverged',
      'over_capacity',
    }.contains(status);
    if (version != 1 || !validStatus) {
      return const CompanyStorageInventory();
    }
    return CompanyStorageInventory(
      available: true,
      status: status!,
      complete: data['complete'] == true,
      observedBytes: _nonNegativeInt(data['observedBytes']),
      metadataUsageBytes: _nonNegativeInt(data['metadataUsageBytes']),
      objectCount: _nonNegativeInt(data['objectCount']),
      orphanObjectCount: _nonNegativeInt(data['orphanObjectCount']),
      missingObjectCount: _nonNegativeInt(data['missingObjectCount']),
      checkedAt: _date(data['checkedAt']),
    );
  }

  final bool available;
  final String status;
  final bool complete;
  final int observedBytes;
  final int metadataUsageBytes;
  final int objectCount;
  final int orphanObjectCount;
  final int missingObjectCount;
  final DateTime? checkedAt;

  bool get healthy => available && complete && status == 'healthy';
  bool get needsAttention =>
      available &&
      (status == 'diverged' ||
          status == 'over_capacity' ||
          orphanObjectCount > 0 ||
          missingObjectCount > 0);
}

class CompanyMemberStorageOverride {
  const CompanyMemberStorageOverride({
    this.privateStorageEnabled,
    this.privateQuotaBytes,
  });

  factory CompanyMemberStorageOverride.fromMap(Map<String, Object?> data) {
    return CompanyMemberStorageOverride(
      privateStorageEnabled: data['privateStorageEnabled'] is bool
          ? data['privateStorageEnabled'] as bool
          : null,
      privateQuotaBytes:
          _nullableInt(data['privateQuotaBytes']) ??
          _nullableInt(data['quotaBytes']),
    );
  }

  final bool? privateStorageEnabled;
  final int? privateQuotaBytes;

  bool get hasOverride =>
      privateStorageEnabled != null || privateQuotaBytes != null;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (privateStorageEnabled != null)
        'privateStorageEnabled': privateStorageEnabled,
      if (privateQuotaBytes != null) 'privateQuotaBytes': privateQuotaBytes,
    };
  }
}

class BusinessReconciliationState {
  const BusinessReconciliationState({
    this.requiredRevision = 0,
    this.completedRevision = 0,
  });

  factory BusinessReconciliationState.fromMap(Map<String, Object?> data) {
    final required = _boundedRevision(data['requiredRevision']);
    final storedCompleted = _boundedRevision(data['completedRevision']);
    return BusinessReconciliationState(
      requiredRevision: required,
      completedRevision: storedCompleted > required ? 0 : storedCompleted,
    );
  }

  final int requiredRevision;
  final int completedRevision;

  bool get pending => requiredRevision > completedRevision;

  static int _boundedRevision(Object? value) {
    final parsed = _nullableInt(value);
    if (parsed == null || parsed < 0 || parsed > 2147483647) {
      return 0;
    }
    return parsed;
  }
}

class CompanyGroup {
  const CompanyGroup({
    required this.id,
    required this.name,
    this.description,
    this.memberUids = const <String>[],
    this.accessScopes = const <String>[],
    this.storageOverride = const CompanyMemberStorageOverride(),
    this.sharedStorageEnabled = true,
    this.encryptedMetadata,
    this.metadataProtected = false,
    this.metadataReadable = true,
    this.reconciliation = const BusinessReconciliationState(),
    this.createdAt,
    this.updatedAt,
  });

  factory CompanyGroup.fromMap(Map<String, Object?> data) {
    final encryptedMetadata = _encryptedMetadata(data['encryptedMetadata']);
    final metadataProtected = data['metadataProtected'] == true;
    return CompanyGroup(
      id: _string(data['id']) ?? '',
      name: _string(data['name']) ?? 'Group',
      description: _string(data['description']),
      memberUids: _stringList(data['memberUids']),
      accessScopes: _stringList(data['accessScopes']),
      storageOverride: CompanyMemberStorageOverride.fromMap(
        _map(data['storageOverride']),
      ),
      sharedStorageEnabled: data['sharedStorageEnabled'] != false,
      encryptedMetadata: encryptedMetadata,
      metadataProtected: metadataProtected,
      metadataReadable:
          !metadataProtected ||
          (data['metadataReadable'] != false && encryptedMetadata != null),
      reconciliation: BusinessReconciliationState.fromMap(
        _map(data['reconciliation']),
      ),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
    );
  }

  final String id;
  final String name;
  final String? description;
  final List<String> memberUids;
  final List<String> accessScopes;
  final CompanyMemberStorageOverride storageOverride;
  final bool sharedStorageEnabled;
  final BusinessEncryptedMetadata? encryptedMetadata;
  final bool metadataProtected;
  final bool metadataReadable;
  final BusinessReconciliationState reconciliation;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CompanyGroup copyWith({
    String? name,
    String? description,
    bool clearDescription = false,
    bool? metadataReadable,
  }) {
    return CompanyGroup(
      id: id,
      name: name ?? this.name,
      description: clearDescription ? null : description ?? this.description,
      memberUids: memberUids,
      accessScopes: accessScopes,
      storageOverride: storageOverride,
      sharedStorageEnabled: sharedStorageEnabled,
      encryptedMetadata: encryptedMetadata,
      metadataProtected: metadataProtected,
      metadataReadable: metadataReadable ?? this.metadataReadable,
      reconciliation: reconciliation,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class CompanyStorageSpace {
  const CompanyStorageSpace({
    required this.id,
    required this.scope,
    required this.label,
    this.companyId,
    this.groupId,
    this.enabled = true,
    this.quotaBytes,
  });

  final String id;
  final String scope;
  final String label;
  final String? companyId;
  final String? groupId;
  final bool enabled;
  final int? quotaBytes;
}

class SharedFileKeyEnvelope {
  const SharedFileKeyEnvelope({
    required this.recipientId,
    required this.recipientType,
    required this.wrappedKey,
    this.algorithm = 'x25519-xsalsa20poly1305',
    this.createdAt,
  });

  factory SharedFileKeyEnvelope.fromMap(Map<String, Object?> data) {
    return SharedFileKeyEnvelope(
      recipientId: _string(data['recipientId']) ?? '',
      recipientType: _string(data['recipientType']) ?? 'user',
      wrappedKey: _string(data['wrappedKey']) ?? '',
      algorithm: _string(data['algorithm']) ?? 'x25519-xsalsa20poly1305',
      createdAt: _date(data['createdAt']),
    );
  }

  final String recipientId;
  final String recipientType;
  final String wrappedKey;
  final String algorithm;
  final DateTime? createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'recipientId': recipientId,
      'recipientType': recipientType,
      'wrappedKey': wrappedKey,
      'algorithm': algorithm,
      if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    };
  }
}

class CompanyProfile {
  const CompanyProfile({
    required this.id,
    required this.name,
    this.domain,
    this.status = 'active',
    this.ownerUid,
    this.createdAt,
    this.updatedAt,
    this.storagePolicy = const CompanyStoragePolicy(),
    this.storageInventory = const CompanyStorageInventory(),
    this.securityModel = const <String, Object?>{},
    this.encryptedMetadata,
    this.metadataProtected = false,
    this.metadataReadable = true,
    this.reconciliation = const BusinessReconciliationState(),
  });

  factory CompanyProfile.fromMap(Map<String, Object?> data) {
    final encryptedMetadata = _encryptedMetadata(data['encryptedMetadata']);
    final metadataProtected = data['metadataProtected'] == true;
    return CompanyProfile(
      id: _string(data['id']) ?? '',
      name: _string(data['name']) ?? 'Company',
      domain: _string(data['domain']),
      status: _string(data['status']) ?? 'active',
      ownerUid: _string(data['ownerUid']),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
      storagePolicy: CompanyStoragePolicy.fromMap(_map(data['storagePolicy'])),
      storageInventory: CompanyStorageInventory.fromMap(
        _map(data['storageInventory']),
      ),
      securityModel: _map(data['securityModel']),
      encryptedMetadata: encryptedMetadata,
      metadataProtected: metadataProtected,
      metadataReadable:
          !metadataProtected ||
          (data['metadataReadable'] != false && encryptedMetadata != null),
      reconciliation: BusinessReconciliationState.fromMap(
        _map(data['reconciliation']),
      ),
    );
  }

  final String id;
  final String name;
  final String? domain;
  final String status;
  final String? ownerUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final CompanyStoragePolicy storagePolicy;
  final CompanyStorageInventory storageInventory;
  final Map<String, Object?> securityModel;
  final BusinessEncryptedMetadata? encryptedMetadata;
  final bool metadataProtected;
  final bool metadataReadable;
  final BusinessReconciliationState reconciliation;

  CompanyProfile copyWith({
    String? name,
    String? domain,
    bool clearDomain = false,
    bool? metadataReadable,
  }) {
    return CompanyProfile(
      id: id,
      name: name ?? this.name,
      domain: clearDomain ? null : domain ?? this.domain,
      status: status,
      ownerUid: ownerUid,
      createdAt: createdAt,
      updatedAt: updatedAt,
      storagePolicy: storagePolicy,
      storageInventory: storageInventory,
      securityModel: securityModel,
      encryptedMetadata: encryptedMetadata,
      metadataProtected: metadataProtected,
      metadataReadable: metadataReadable ?? this.metadataReadable,
      reconciliation: reconciliation,
    );
  }
}

class CompanyMember {
  const CompanyMember({
    required this.id,
    this.uid,
    this.email,
    this.displayName,
    this.role = 'member',
    this.status = 'active',
    this.permissions = const <String, bool>{},
    this.accessScopes = const <String>[],
    this.groupIds = const <String>[],
    this.storageOverride = const CompanyMemberStorageOverride(),
    this.encryptionReady = false,
    this.encryptionKeyId,
    this.invitationFingerprint,
    this.invitationExpiresAt,
    this.joinedAt,
    this.invitedAt,
    this.updatedAt,
  });

  factory CompanyMember.fromMap(Map<String, Object?> data) {
    return CompanyMember(
      id: _string(data['id']) ?? '',
      uid: _string(data['uid']),
      email: _string(data['email']),
      displayName: _string(data['displayName']),
      role: _string(data['role']) ?? 'member',
      status: _string(data['status']) ?? 'active',
      permissions: _boolMap(data['permissions']),
      accessScopes: _stringList(data['accessScopes']),
      groupIds: _stringList(data['groupIds']),
      storageOverride: CompanyMemberStorageOverride.fromMap(
        _map(data['storageOverride']),
      ),
      encryptionReady: data['encryptionReady'] == true,
      encryptionKeyId: _string(data['encryptionKeyId']),
      invitationFingerprint: _string(data['invitationFingerprint']),
      invitationExpiresAt: _date(data['invitationExpiresAt']),
      joinedAt: _date(data['joinedAt']),
      invitedAt: _date(data['invitedAt']),
      updatedAt: _date(data['updatedAt']),
    );
  }

  final String id;
  final String? uid;
  final String? email;
  final String? displayName;
  final String role;
  final String status;
  final Map<String, bool> permissions;
  final List<String> accessScopes;
  final List<String> groupIds;
  final CompanyMemberStorageOverride storageOverride;
  final bool encryptionReady;
  final String? encryptionKeyId;
  final String? invitationFingerprint;
  final DateTime? invitationExpiresAt;
  final DateTime? joinedAt;
  final DateTime? invitedAt;
  final DateTime? updatedAt;

  String get label {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final address = email?.trim();
    if (address != null && address.isNotEmpty) {
      return address;
    }
    final fingerprint = invitationFingerprint?.trim();
    if (status == 'invited') {
      return fingerprint == null || fingerprint.isEmpty
          ? 'Pending invitation'
          : 'Pending invitation • $fingerprint';
    }
    return 'Company member';
  }

  bool get isLegacyInvitation =>
      status == 'invited' &&
      (invitationFingerprint == null || invitationFingerprint!.trim().isEmpty);
}

class CompanyPendingInvitation {
  const CompanyPendingInvitation({
    required this.code,
    required this.fingerprint,
    required this.expiresAt,
  });

  factory CompanyPendingInvitation.fromMap(Map<String, Object?> data) {
    final code = _string(data['code']) ?? '';
    final fingerprint = _string(data['fingerprint']) ?? '';
    final expiresAt = _date(data['expiresAt']);
    if (data['version'] != 1 ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(code) ||
        !RegExp(r'^[A-F0-9]{10}$').hasMatch(fingerprint) ||
        expiresAt == null) {
      throw const FormatException('Invalid protected Business invitation.');
    }
    return CompanyPendingInvitation(
      code: code,
      fingerprint: fingerprint,
      expiresAt: expiresAt,
    );
  }

  final String code;
  final String fingerprint;
  final DateTime expiresAt;
}

class CompanyAccessPattern {
  const CompanyAccessPattern({
    required this.memberIndex,
    this.role = 'member',
    this.status = 'active',
    this.fileCount = 0,
    this.folderCount = 0,
    this.sharedFileCount = 0,
    this.usageBytes = 0,
    this.lastFileUploadedAt,
    this.accessScopes = const <String>[],
  });

  factory CompanyAccessPattern.fromMap(Map<String, Object?> data) {
    return CompanyAccessPattern(
      memberIndex: _int(data['memberIndex']),
      role: _string(data['role']) ?? 'member',
      status: _string(data['status']) ?? 'active',
      fileCount: _nonNegativeInt(data['fileCount']),
      folderCount: _nonNegativeInt(data['folderCount']),
      sharedFileCount: _nonNegativeInt(data['sharedFileCount']),
      usageBytes: _nonNegativeInt(data['usageBytes']),
      lastFileUploadedAt: _date(data['lastFileUploadedAt']),
      accessScopes: _stringList(data['accessScopes']),
    );
  }

  final int memberIndex;
  final String role;
  final String status;
  final int fileCount;
  final int folderCount;
  final int sharedFileCount;
  final int usageBytes;
  final DateTime? lastFileUploadedAt;
  final List<String> accessScopes;
}

const Map<String, String> _companyAuditTitles = <String, String>{
  'company.created': 'Company profile created',
  'company.group_created': 'Company group created',
  'company.group_deleted': 'Company group deleted',
  'company.group_updated': 'Company group updated',
  'company.member_added': 'Company user added',
  'company.member_invited': 'Company user invited',
  'company.member_invitation_revoked': 'Company invitation revoked',
  'company.member_permissions_updated': 'Company user permissions updated',
  'company.member_storage_policy_updated':
      'Company member storage policy updated',
  'company.profile_updated': 'Company profile updated',
  'company.session_started': 'Company workspace signed in',
  'company.storage_policy_updated': 'Company storage policy updated',
  'storage.encrypted_folder_created': 'Encrypted folder created',
  'storage.encrypted_folder_renamed': 'Encrypted folder renamed',
  'storage.file_encryption_rotated': 'Business file encryption rotated',
  'storage.file_metadata_protected': 'Encrypted file metadata protected',
  'storage.file_metadata_recorded': 'File metadata recorded',
  'storage.member_access_refreshed': 'Encrypted file member access refreshed',
};

String _companyAuditAction(Object? value) {
  final normalized = _string(value)?.toLowerCase();
  return normalized != null && _companyAuditTitles.containsKey(normalized)
      ? normalized
      : 'company.event';
}

String _companyAuditTitle(String action) =>
    _companyAuditTitles[action] ?? 'Company event';

class CompanyAuditLogEntry {
  const CompanyAuditLogEntry({
    required this.id,
    required this.action,
    required this.title,
    this.actorMemberId,
    this.actorPresent = false,
    this.targetMemberId,
    this.targetPresent = false,
    this.createdAt,
  });

  factory CompanyAuditLogEntry.fromMap(Map<String, Object?> data) {
    final action = _companyAuditAction(data['action'] ?? data['type']);
    final actorMemberId =
        _string(data['actorMemberId']) ??
        _string(data['actorUid']) ??
        _string(data['uid']);
    final targetMemberId =
        _string(data['targetMemberId']) ?? _string(data['targetUid']);
    return CompanyAuditLogEntry(
      id: _string(data['id']) ?? '',
      action: action,
      // Never render a server-provided free-form title. A fixed local title
      // keeps legacy or compromised responses from placing private text in the
      // Business activity UI.
      title: _companyAuditTitle(action),
      actorMemberId: actorMemberId,
      actorPresent:
          data['actorPresent'] == true ||
          actorMemberId != null ||
          _string(data['actorEmail']) != null ||
          _string(data['email']) != null,
      targetMemberId: targetMemberId,
      targetPresent:
          data['targetPresent'] == true ||
          targetMemberId != null ||
          _string(data['targetEmail']) != null,
      createdAt: _date(data['createdAt']),
    );
  }

  final String id;
  final String action;
  final String title;
  final String? actorMemberId;
  final bool actorPresent;
  final String? targetMemberId;
  final bool targetPresent;
  final DateTime? createdAt;
}

class CompanyDashboard {
  const CompanyDashboard({
    this.company,
    this.currentMember,
    this.canCreate = true,
    this.canManage = false,
    this.members = const <CompanyMember>[],
    this.groups = const <CompanyGroup>[],
    this.accessPatternsAvailable = false,
    this.accessPatternsComplete = false,
    this.accessPatterns = const <CompanyAccessPattern>[],
    this.auditLogsAvailable = false,
    this.auditLogsComplete = false,
    this.auditLogs = const <CompanyAuditLogEntry>[],
    this.pendingInvitation,
  });

  factory CompanyDashboard.fromMap(Map<String, Object?> data) {
    final accessPatternsAvailable =
        _string(data['accessPatternsScope']) == 'business_v1';
    final auditLogsAvailable =
        _string(data['auditLogsScope']) == 'business_privacy_v2';
    return CompanyDashboard(
      company: _nullableModel(data['company'], CompanyProfile.fromMap),
      currentMember: _nullableModel(
        data['currentMember'],
        CompanyMember.fromMap,
      ),
      canCreate: data['canCreate'] == true,
      canManage: data['canManage'] == true,
      members: _modelList(data['members'], CompanyMember.fromMap),
      groups: _modelList(data['groups'], CompanyGroup.fromMap),
      accessPatternsAvailable: accessPatternsAvailable,
      accessPatternsComplete:
          accessPatternsAvailable && data['accessPatternsComplete'] == true,
      accessPatterns: accessPatternsAvailable
          ? _modelList(data['accessPatterns'], CompanyAccessPattern.fromMap)
          : const <CompanyAccessPattern>[],
      auditLogsAvailable: auditLogsAvailable,
      auditLogsComplete:
          auditLogsAvailable && data['auditLogsComplete'] == true,
      auditLogs: auditLogsAvailable
          ? _modelList(data['auditLogs'], CompanyAuditLogEntry.fromMap)
          : const <CompanyAuditLogEntry>[],
      pendingInvitation: _nullableModel(
        data['pendingInvitation'],
        CompanyPendingInvitation.fromMap,
      ),
    );
  }

  final CompanyProfile? company;
  final CompanyMember? currentMember;
  final bool canCreate;
  final bool canManage;
  final List<CompanyMember> members;
  final List<CompanyGroup> groups;
  final bool accessPatternsAvailable;
  final bool accessPatternsComplete;
  final List<CompanyAccessPattern> accessPatterns;
  final bool auditLogsAvailable;
  final bool auditLogsComplete;
  final List<CompanyAuditLogEntry> auditLogs;
  final CompanyPendingInvitation? pendingInvitation;

  CompanyDashboard copyWith({
    CompanyProfile? company,
    List<CompanyGroup>? groups,
    bool clearPendingInvitation = false,
  }) {
    return CompanyDashboard(
      company: company ?? this.company,
      currentMember: currentMember,
      canCreate: canCreate,
      canManage: canManage,
      members: members,
      groups: groups ?? this.groups,
      accessPatternsAvailable: accessPatternsAvailable,
      accessPatternsComplete: accessPatternsComplete,
      accessPatterns: accessPatterns,
      auditLogsAvailable: auditLogsAvailable,
      auditLogsComplete: auditLogsComplete,
      auditLogs: auditLogs,
      pendingInvitation: clearPendingInvitation ? null : pendingInvitation,
    );
  }
}

class CompanySession {
  const CompanySession({
    this.company,
    this.currentMember,
    this.canCreate = false,
    this.canManage = false,
    this.groups = const <CompanyGroup>[],
  });

  factory CompanySession.fromMap(Map<String, Object?> data) {
    return CompanySession(
      company: _nullableModel(data['company'], CompanyProfile.fromMap),
      currentMember: _nullableModel(
        data['currentMember'],
        CompanyMember.fromMap,
      ),
      canCreate: data['canCreate'] == true,
      canManage: data['canManage'] == true,
      groups: _modelList(data['groups'], CompanyGroup.fromMap),
    );
  }

  final CompanyProfile? company;
  final CompanyMember? currentMember;
  final bool canCreate;
  final bool canManage;
  final List<CompanyGroup> groups;

  bool get hasActiveMembership =>
      company != null && currentMember?.status == 'active';

  CompanySession copyWith({
    CompanyProfile? company,
    List<CompanyGroup>? groups,
  }) {
    return CompanySession(
      company: company ?? this.company,
      currentMember: currentMember,
      canCreate: canCreate,
      canManage: canManage,
      groups: groups ?? this.groups,
    );
  }
}

abstract class CompanyMetadataProtection {
  Future<CompanySession> decryptSession(CompanySession session);

  Future<CompanyDashboard> decryptDashboard(CompanyDashboard dashboard);

  Future<Map<String, Object?>> prepareCompanyCreate({
    required String name,
    String? domain,
  });

  Future<Map<String, Object?>> prepareCompanyUpdate({
    required CompanyProfile company,
    required String name,
    String? domain,
  });

  Future<Map<String, Object?>> prepareGroupWrite({
    required String name,
    String? description,
    required List<String> memberUids,
    CompanyGroup? existing,
  });

  Future<int> refreshMetadataAccess({
    required CompanyProfile company,
    CompanyGroup? group,
  });
}

abstract class CompanyMetadataProtectionFailure {
  String get message;
}

class CompanyAdminService {
  CompanyAdminService({
    FirebaseFunctions? functions,
    CompanyAdminCallable? callable,
    CompanyMetadataProtection? metadataProtection,
  }) : _metadataProtection = metadataProtection,
       _callable = callable,
       _functions =
           functions ??
           (callable == null
               ? FirebaseFunctions.instanceFor(region: 'europe-west1')
               : null);

  factory CompanyAdminService.forApp(
    FirebaseApp app, {
    CompanyMetadataProtection? metadataProtection,
  }) {
    return CompanyAdminService(
      functions: FirebaseFunctions.instanceFor(
        app: app,
        region: 'europe-west1',
      ),
      metadataProtection: metadataProtection,
    );
  }

  final FirebaseFunctions? _functions;
  final CompanyAdminCallable? _callable;
  final CompanyMetadataProtection? _metadataProtection;

  Future<CompanySession> beginSession() async {
    final data = await _call('beginCompanySession');
    final session = CompanySession.fromMap(data);
    final protection = _metadataProtection;
    return protection == null
        ? session
        : _protect(() => protection.decryptSession(session));
  }

  Future<CompanyDashboard> fetchDashboard() async {
    final data = await _call('getCompanyAdminDashboard');
    return _dashboardFromData(data);
  }

  Future<CompanyDashboard> createCompany({
    required String name,
    String? domain,
  }) async {
    final protection = _requireProtection();
    final payload = await _protect(
      () => protection.prepareCompanyCreate(name: name, domain: domain),
    );
    final data = await _call('createCompanyProfile', payload);
    return _dashboardFromData(data);
  }

  Future<CompanyDashboard> updateCompany({
    required CompanyProfile company,
    required String name,
    String? domain,
  }) async {
    final protection = _requireProtection();
    final payload = await _protect(
      () => protection.prepareCompanyUpdate(
        company: company,
        name: name,
        domain: domain,
      ),
    );
    final data = await _call('updateCompanyProfile', payload);
    return _dashboardFromData(data);
  }

  Future<CompanyDashboard> setStoragePolicy(CompanyStoragePolicy policy) async {
    final data = await _call('setCompanyStoragePolicy', policy.toMap());
    return _dashboardFromData(data);
  }

  Future<CompanyDashboard> addMember({
    String role = 'member',
    Map<String, bool> permissions = const <String, bool>{},
    List<String> accessScopes = const <String>['personal_workspace'],
  }) async {
    final data = await _call('addCompanyMember', <String, Object?>{
      'invitationMode': 'token_v2',
      'role': role,
      'permissions': permissions,
      'accessScopes': accessScopes,
    });
    return _dashboardFromData(data);
  }

  Future<CompanyDashboard> claimInvitation(String code) async {
    final normalized = code.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(normalized)) {
      throw const CompanyAdminException._(
        CompanyAdminFailureKind.validation,
        'Enter the complete 43-character Business invitation code.',
      );
    }
    final data = await _call('claimCompanyInvitation', <String, Object?>{
      'code': normalized,
    });
    return _dashboardFromData(data);
  }

  Future<CompanyDashboard> revokeInvitation({required String memberId}) async {
    final normalized = memberId.trim();
    if (normalized.isEmpty || normalized.length > 160) {
      throw const CompanyAdminException._(
        CompanyAdminFailureKind.validation,
        'Refresh the company user list before revoking this invitation.',
      );
    }
    final data = await _call('revokeCompanyInvitation', <String, Object?>{
      'memberId': normalized,
    });
    return _dashboardFromData(data);
  }

  Future<CompanyDashboard> createGroup({
    required String name,
    String? description,
    List<String> memberUids = const <String>[],
    List<String> accessScopes = const <String>['company_workspace'],
    CompanyMemberStorageOverride storageOverride =
        const CompanyMemberStorageOverride(),
    bool sharedStorageEnabled = true,
  }) async {
    final protection = _requireProtection();
    final protectedPayload = await _protect(
      () => protection.prepareGroupWrite(
        name: name,
        description: description,
        memberUids: memberUids,
      ),
    );
    final data = await _call('createCompanyGroup', <String, Object?>{
      ...protectedPayload,
      'memberUids': memberUids,
      'accessScopes': accessScopes,
      'storageOverride': storageOverride.toMap(),
      'sharedStorageEnabled': sharedStorageEnabled,
    });
    return _dashboardFromData(data);
  }

  Future<CompanyDashboard> updateGroup({
    required CompanyGroup group,
    required String name,
    String? description,
    required List<String> memberUids,
    List<String> accessScopes = const <String>['company_workspace'],
    CompanyMemberStorageOverride storageOverride =
        const CompanyMemberStorageOverride(),
    bool sharedStorageEnabled = true,
  }) async {
    final protection = _requireProtection();
    final protectedPayload = await _protect(
      () => protection.prepareGroupWrite(
        name: name,
        description: description,
        memberUids: memberUids,
        existing: group,
      ),
    );
    final data = await _call('updateCompanyGroup', <String, Object?>{
      'groupId': group.id,
      ...protectedPayload,
      'memberUids': memberUids,
      'accessScopes': accessScopes,
      'storageOverride': storageOverride.toMap(),
      'sharedStorageEnabled': sharedStorageEnabled,
    });
    return _dashboardFromData(data);
  }

  Future<CompanyDashboard> deleteGroup({required String groupId}) async {
    final data = await _call('deleteCompanyGroup', <String, Object?>{
      'groupId': groupId,
    });
    return _dashboardFromData(data);
  }

  Future<CompanyDashboard> updateMember({
    required String memberId,
    required String role,
    required String status,
    required Map<String, bool> permissions,
    required List<String> accessScopes,
  }) async {
    final data =
        await _call('updateCompanyMemberPermissions', <String, Object?>{
          'memberId': memberId,
          'role': role,
          'status': status,
          'permissions': permissions,
          'accessScopes': accessScopes,
        });
    return _dashboardFromData(data);
  }

  Future<CompanyDashboard> setMemberStoragePolicy({
    required String memberId,
    required CompanyMemberStorageOverride override,
  }) async {
    final data = await _call('setCompanyMemberStoragePolicy', <String, Object?>{
      'memberId': memberId,
      ...override.toMap(),
    });
    return _dashboardFromData(data);
  }

  Future<int> refreshProtectedLabels({
    required CompanyProfile company,
    CompanyGroup? group,
  }) {
    final protection = _requireProtection();
    return _protect(
      () => protection.refreshMetadataAccess(company: company, group: group),
    );
  }

  Future<BusinessReconciliationState> acknowledgeReconciliation({
    required String storageScope,
    String? groupId,
    required int expectedRevision,
  }) async {
    final normalizedScope = storageScope.trim().toLowerCase();
    final normalizedGroupId = groupId?.trim();
    if (normalizedScope != 'company_shared' && normalizedScope != 'group') {
      throw const CompanyAdminException._(
        CompanyAdminFailureKind.validation,
        'Select a valid Business storage space.',
      );
    }
    if (normalizedScope == 'group' &&
        (normalizedGroupId == null || normalizedGroupId.isEmpty)) {
      throw const CompanyAdminException._(
        CompanyAdminFailureKind.validation,
        'Select a valid Business group.',
      );
    }
    if (expectedRevision <= 0 || expectedRevision > 2147483647) {
      throw const CompanyAdminException._(
        CompanyAdminFailureKind.validation,
        'Refresh Business access before confirming reconciliation.',
      );
    }
    final data =
        await _call('acknowledgeBusinessReconciliation', <String, Object?>{
          'storageScope': normalizedScope,
          if (normalizedScope == 'group') 'groupId': normalizedGroupId,
          'expectedRevision': expectedRevision,
        });
    final state = BusinessReconciliationState.fromMap(
      _map(data['reconciliation']),
    );
    if (state.requiredRevision != expectedRevision || state.pending) {
      throw const CompanyAdminException._(
        CompanyAdminFailureKind.reconciliation,
        'Business access changed again. Refresh and reconcile the latest state.',
      );
    }
    return state;
  }

  CompanyMetadataProtection _requireProtection() {
    final protection = _metadataProtection;
    if (protection == null) {
      throw const CompanyAdminException._(
        CompanyAdminFailureKind.protectedMetadata,
        'Protected Business labels are unavailable in this client.',
      );
    }
    return protection;
  }

  Future<CompanyDashboard> _dashboardFromData(Map<String, Object?> data) async {
    final dashboard = CompanyDashboard.fromMap(data);
    final protection = _metadataProtection;
    return protection == null
        ? dashboard
        : _protect(() => protection.decryptDashboard(dashboard));
  }

  Future<T> _protect<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on CompanyMetadataProtectionFailure {
      throw const CompanyAdminException._(
        CompanyAdminFailureKind.protectedMetadata,
        'Protected Business labels could not be prepared on this device. Refresh access and try again.',
      );
    } on BusinessEncryptionRegistryException {
      throw CompanyAdminException._(
        CompanyAdminFailureKind.businessEncryption,
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.businessEncryption,
        ),
      );
    } on BusinessMetadataEncryptionException {
      throw const CompanyAdminException._(
        CompanyAdminFailureKind.protectedMetadata,
        'Protected Business labels could not be prepared on this device. Refresh access and try again.',
      );
    } on BusinessEncryptionException {
      throw CompanyAdminException._(
        CompanyAdminFailureKind.businessEncryption,
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.businessEncryption,
        ),
      );
    } on CompanyAdminException {
      rethrow;
    } catch (_) {
      throw const CompanyAdminException._(
        CompanyAdminFailureKind.protectedMetadata,
        'Protected Business labels could not be prepared on this device.',
      );
    }
  }

  Future<Map<String, Object?>> _call(
    String functionName, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) async {
    try {
      final callable = _callable;
      if (callable != null) {
        return await callable(
          functionName,
          data,
        ).timeout(const Duration(seconds: 30));
      }
      final result = await _functions!
          .httpsCallable(functionName)
          .call<Object?>(data)
          .timeout(const Duration(seconds: 30));
      return _map(result.data);
    } on FirebaseFunctionsException catch (error) {
      throw CompanyAdminException._(
        CompanyAdminFailureKind.cloud,
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.business,
          code: error.code,
        ),
      );
    } on CompanyAdminException {
      rethrow;
    } catch (_) {
      throw CompanyAdminException._(
        CompanyAdminFailureKind.cloud,
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.business,
        ),
      );
    }
  }
}

T? _nullableModel<T>(
  Object? value,
  T Function(Map<String, Object?> data) parser,
) {
  final data = _map(value);
  if (data.isEmpty) {
    return null;
  }
  return parser(data);
}

List<T> _modelList<T>(
  Object? value,
  T Function(Map<String, Object?> data) parser,
) {
  if (value is! Iterable) {
    return <T>[];
  }
  return value
      .map(_map)
      .where((data) => data.isNotEmpty)
      .map(parser)
      .toList(growable: false);
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.fromEntries(
      value.entries.map((entry) => MapEntry(entry.key.toString(), entry.value)),
    );
  }
  return const <String, Object?>{};
}

Map<String, bool> _boolMap(Object? value) {
  final data = _map(value);
  return Map<String, bool>.fromEntries(
    data.entries.map((entry) => MapEntry(entry.key, entry.value == true)),
  );
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) {
    return const <String>[];
  }
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String? _string(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _int(Object? value) {
  return _nullableInt(value) ?? 0;
}

int _nonNegativeInt(Object? value) {
  final parsed = _int(value);
  return parsed < 0 ? 0 : parsed;
}

int? _nullableInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

BusinessEncryptedMetadata? _encryptedMetadata(Object? value) {
  if (value is! Map) {
    return null;
  }
  try {
    return BusinessEncryptedMetadata.fromMap(<String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    });
  } on BusinessMetadataEncryptionException {
    return null;
  }
}

DateTime? _date(Object? value) {
  if (value is DateTime) {
    return value.toLocal();
  }
  final text = _string(value);
  if (text == null) {
    return null;
  }
  return DateTime.tryParse(text)?.toLocal();
}
