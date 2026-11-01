import 'business_recipient_trust.dart';
import 'business_recipient_trust_runtime.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_core/firebase_core.dart';

import '../shared/user_facing_cloud_error.dart';
import 'business_encryption_service.dart';

typedef RecipientDirectoryVerifier =
    Future<List<BusinessEncryptionRecipient>> Function(
      Map<String, Object?> response,
      String scope,
      List<BusinessEncryptionRecipient> recipients,
    );

typedef BusinessEncryptionCallable =
    Future<Map<String, Object?>> Function(
      String functionName,
      Map<String, Object?>? payload,
    );

class BusinessEncryptionRegistryException implements Exception {
  const BusinessEncryptionRegistryException(this.message);

  final String message;

  @override
  String toString() => 'BusinessEncryptionRegistryException: $message';
}

class BusinessEncryptionRecipientSet {
  const BusinessEncryptionRecipientSet({
    required this.storageScope,
    required this.recipients,
    required this.missingUids,
    required this.eligibleCount,
    required this.readyCount,
  });

  final String storageScope;
  final List<BusinessEncryptionRecipient> recipients;
  final List<String> missingUids;
  final int eligibleCount;
  final int readyCount;

  bool get isComplete =>
      eligibleCount > 0 &&
      readyCount == eligibleCount &&
      missingUids.isEmpty &&
      recipients.length == readyCount;
}

class BusinessMetadataRecipientSet {
  const BusinessMetadataRecipientSet({
    required this.entityType,
    required this.recipients,
    required this.missingUids,
    required this.metadataMissingUids,
    required this.eligibleCount,
    required this.readyCount,
  });

  final String entityType;
  final List<BusinessEncryptionRecipient> recipients;
  final List<String> missingUids;
  final List<String> metadataMissingUids;
  final int eligibleCount;
  final int readyCount;

  bool get currentMemberCanEncrypt => recipients.isNotEmpty;
}

class BusinessMetadataEnvelopeAppendResult {
  const BusinessMetadataEnvelopeAppendResult({
    required this.entityType,
    required this.addedCount,
    required this.recipientCount,
    this.groupId,
  });

  final String entityType;
  final String? groupId;
  final int addedCount;
  final int recipientCount;
}

class BusinessEnvelopeAppendResult {
  const BusinessEnvelopeAppendResult({
    required this.fileId,
    required this.addedCount,
    required this.recipientCount,
  });

  final String fileId;
  final int addedCount;
  final int recipientCount;
}

class BusinessFileRotationResult {
  const BusinessFileRotationResult({
    required this.fileId,
    required this.recipientCount,
    required this.rotationGeneration,
    required this.cleanupPending,
  });

  final String fileId;
  final int recipientCount;
  final int rotationGeneration;
  final bool cleanupPending;
}

class BusinessEncryptedFolderSaveResult {
  const BusinessEncryptedFolderSaveResult({
    required this.folderId,
    required this.recipientCount,
    required this.created,
  });

  final String folderId;
  final int recipientCount;
  final bool created;
}

class BusinessEncryptionRegistry {
  BusinessEncryptionRegistry({
    FirebaseFunctions? functions,
    BusinessEncryptionCallable? callable,
    BusinessEncryptionService? encryptionService,
    RecipientDirectoryVerifier? recipientVerifier,
  }) : _functions =
           functions ??
           (callable == null
               ? FirebaseFunctions.instanceFor(region: 'europe-west1')
               : null),
       _callable = callable,
       _recipientVerifier = recipientVerifier,
       _encryptionService = encryptionService ?? BusinessEncryptionService();

  factory BusinessEncryptionRegistry.forApp(FirebaseApp app) {
    return BusinessEncryptionRegistry(
      functions: FirebaseFunctions.instanceFor(
        app: app,
        region: 'europe-west1',
      ),
      recipientVerifier: (response, scope, recipients) async {
        final company = response['companyId'];
        if (company is! String || company.isEmpty) {
          throw const RecipientTrustException(
            'Refresh company access before preparing encryption.',
          );
        }
        final trust = await BusinessRecipientTrustRuntime.forApp(app);
        return trust.verifyRecipients(
          companyId: company,
          scope: scope,
          policy: response['recipientTrust'],
          recipients: recipients,
        );
      },
    );
  }

  final FirebaseFunctions? _functions;
  final BusinessEncryptionCallable? _callable;
  final BusinessEncryptionService _encryptionService;
  final RecipientDirectoryVerifier? _recipientVerifier;

  Future<BusinessEncryptionIdentity?> getIdentity() async {
    final response = await _call('getBusinessEncryptionIdentity');
    final rawIdentity = response['identity'];
    if (rawIdentity == null) {
      return null;
    }
    return BusinessEncryptionIdentity.fromMap(_objectMap(rawIdentity));
  }

  Future<BusinessEncryptionIdentity> ensureIdentity({
    required SecretKey accountProtectionKey,
  }) async {
    final existing = await getIdentity();
    if (existing != null) {
      return existing;
    }
    final created = await _encryptionService.createIdentity(
      accountProtectionKey: accountProtectionKey,
    );
    final response = await _call(
      'registerBusinessEncryptionIdentity',
      <String, Object?>{'identity': created.toMap()},
    );
    return BusinessEncryptionIdentity.fromMap(_objectMap(response['identity']));
  }

  Future<BusinessEncryptionRecipientSet> listRecipients({
    required String storageScope,
    String? groupId,
  }) async {
    final normalizedScope = storageScope.trim();
    if (normalizedScope != 'company_shared' && normalizedScope != 'group') {
      throw const BusinessEncryptionRegistryException(
        'Business encryption recipients require shared or group storage.',
      );
    }
    final normalizedGroupId = groupId?.trim();
    if (normalizedScope == 'group' &&
        (normalizedGroupId == null || normalizedGroupId.isEmpty)) {
      throw const BusinessEncryptionRegistryException(
        'A group id is required for group encryption.',
      );
    }
    final response =
        await _call('listBusinessEncryptionRecipients', <String, Object?>{
          'storageScope': normalizedScope,
          if (normalizedScope == 'group') 'groupId': normalizedGroupId,
        });
    var recipients = <BusinessEncryptionRecipient>[];
    final rawRecipients = response['recipients'];
    if (rawRecipients is Iterable) {
      for (final value in rawRecipients) {
        recipients.add(BusinessEncryptionRecipient.fromMap(_objectMap(value)));
      }
    }
    final missingUids = _stringList(response['missingUids']);
    final eligibleCount = _nonNegativeInt(response['eligibleCount']);
    final readyCount = _nonNegativeInt(response['readyCount']);
    if (eligibleCount == null ||
        readyCount == null ||
        readyCount != recipients.length ||
        readyCount > eligibleCount ||
        readyCount + missingUids.length != eligibleCount) {
      throw const BusinessEncryptionRegistryException(
        'Business encryption readiness data is inconsistent.',
      );
    }
    if (_recipientVerifier != null) {
      recipients = await _recipientVerifier(
        response,
        normalizedScope == 'group'
            ? 'group:$normalizedGroupId'
            : 'company_shared',
        recipients,
      );
    }
    return BusinessEncryptionRecipientSet(
      storageScope: normalizedScope,
      recipients: List<BusinessEncryptionRecipient>.unmodifiable(recipients),
      missingUids: List<String>.unmodifiable(missingUids),
      eligibleCount: eligibleCount,
      readyCount: readyCount,
    );
  }

  Future<BusinessMetadataRecipientSet> listMetadataRecipients({
    required String entityType,
    String? groupId,
    List<String>? memberUids,
  }) async {
    final normalizedType = entityType.trim().toLowerCase();
    if (normalizedType != 'company' && normalizedType != 'group') {
      throw const BusinessEncryptionRegistryException(
        'Protected metadata recipients require a company or group entity.',
      );
    }
    final normalizedGroupId = groupId?.trim();
    if (normalizedType == 'group' &&
        memberUids == null &&
        (normalizedGroupId == null || normalizedGroupId.isEmpty)) {
      throw const BusinessEncryptionRegistryException(
        'A group id or draft member set is required.',
      );
    }
    final response =
        await _call('listBusinessMetadataRecipients', <String, Object?>{
          'entityType': normalizedType,
          if (normalizedType == 'group' &&
              normalizedGroupId != null &&
              normalizedGroupId.isNotEmpty)
            'groupId': normalizedGroupId,
          if (normalizedType == 'group' && memberUids != null)
            'memberUids': memberUids,
        });
    var recipients = <BusinessEncryptionRecipient>[];
    final rawRecipients = response['recipients'];
    if (rawRecipients is Iterable) {
      for (final value in rawRecipients) {
        recipients.add(BusinessEncryptionRecipient.fromMap(_objectMap(value)));
      }
    }
    final missingUids = _stringList(response['missingUids']);
    final metadataMissingUids = _stringList(response['metadataMissingUids']);
    final eligibleCount = _nonNegativeInt(response['eligibleCount']);
    final readyCount = _nonNegativeInt(response['readyCount']);
    if (response['entityType'] != normalizedType ||
        eligibleCount == null ||
        readyCount == null ||
        readyCount != recipients.length ||
        readyCount > eligibleCount ||
        readyCount + missingUids.length != eligibleCount ||
        metadataMissingUids.any(
          (uid) => !recipients.any((recipient) => recipient.uid == uid),
        )) {
      throw const BusinessEncryptionRegistryException(
        'Protected Business metadata readiness is inconsistent.',
      );
    }
    if (_recipientVerifier != null) {
      recipients = await _recipientVerifier(
        response,
        normalizedType == 'company'
            ? 'metadata:company'
            : 'metadata:group:${normalizedGroupId ?? 'draft'}',
        recipients,
      );
    }
    return BusinessMetadataRecipientSet(
      entityType: normalizedType,
      recipients: List<BusinessEncryptionRecipient>.unmodifiable(recipients),
      missingUids: List<String>.unmodifiable(missingUids),
      metadataMissingUids: List<String>.unmodifiable(metadataMissingUids),
      eligibleCount: eligibleCount,
      readyCount: readyCount,
    );
  }

  Future<BusinessMetadataEnvelopeAppendResult> appendMetadataEnvelopes({
    required String entityType,
    required Map<String, BusinessFileKeyEnvelope> additions,
    String? groupId,
  }) async {
    final normalizedType = entityType.trim().toLowerCase();
    final normalizedGroupId = groupId?.trim();
    if ((normalizedType != 'company' && normalizedType != 'group') ||
        additions.isEmpty ||
        (normalizedType == 'group' &&
            (normalizedGroupId == null || normalizedGroupId.isEmpty))) {
      throw const BusinessEncryptionRegistryException(
        'Protected Business metadata envelope additions are incomplete.',
      );
    }
    final response = await _call(
      'appendBusinessMetadataKeyEnvelopes',
      <String, Object?>{
        'entityType': normalizedType,
        if (normalizedType == 'group') 'groupId': normalizedGroupId,
        'additions': <String, Object?>{
          for (final entry in additions.entries) entry.key: entry.value.toMap(),
        },
      },
    );
    final addedCount = _nonNegativeInt(response['addedCount']);
    final recipientCount = _nonNegativeInt(response['recipientCount']);
    if (response['entityType'] != normalizedType ||
        (normalizedType == 'group' &&
            response['groupId'] != normalizedGroupId) ||
        addedCount == null ||
        recipientCount == null ||
        addedCount != additions.length ||
        recipientCount < addedCount) {
      throw const BusinessEncryptionRegistryException(
        'Protected Business metadata access returned an inconsistent result.',
      );
    }
    return BusinessMetadataEnvelopeAppendResult(
      entityType: normalizedType,
      groupId: normalizedType == 'group' ? normalizedGroupId : null,
      addedCount: addedCount,
      recipientCount: recipientCount,
    );
  }

  Future<BusinessEnvelopeAppendResult> appendFileEnvelopes({
    required String fileId,
    required Map<String, BusinessFileKeyEnvelope> additions,
  }) async {
    final normalizedFileId = fileId.trim();
    if (normalizedFileId.isEmpty || additions.isEmpty) {
      throw const BusinessEncryptionRegistryException(
        'A file and its missing member envelopes are required.',
      );
    }
    final response = await _call(
      'appendBusinessFileKeyEnvelopes',
      <String, Object?>{
        'fileId': normalizedFileId,
        'additions': <String, Object?>{
          for (final entry in additions.entries) entry.key: entry.value.toMap(),
        },
      },
    );
    final returnedFileId = _nonEmptyString(response['fileId']);
    final addedCount = _nonNegativeInt(response['addedCount']);
    final recipientCount = _nonNegativeInt(response['recipientCount']);
    if (returnedFileId != normalizedFileId ||
        addedCount == null ||
        recipientCount == null ||
        addedCount != additions.length ||
        recipientCount < addedCount) {
      throw const BusinessEncryptionRegistryException(
        'Business file access refresh returned an inconsistent result.',
      );
    }
    return BusinessEnvelopeAppendResult(
      fileId: returnedFileId!,
      addedCount: addedCount,
      recipientCount: recipientCount,
    );
  }

  Future<BusinessFileRotationResult> rotateFileEncryption({
    required String fileId,
    required String expectedObjectKey,
    required String replacementObjectKey,
    required String encryptedName,
    required Map<String, BusinessFileKeyEnvelope> envelopes,
  }) async {
    final normalizedFileId = fileId.trim();
    final normalizedExpectedObjectKey = expectedObjectKey.trim();
    final normalizedReplacementObjectKey = replacementObjectKey.trim();
    final normalizedEncryptedName = encryptedName.trim();
    if (normalizedFileId.isEmpty ||
        normalizedExpectedObjectKey.isEmpty ||
        normalizedReplacementObjectKey.isEmpty ||
        normalizedExpectedObjectKey == normalizedReplacementObjectKey ||
        !normalizedEncryptedName.startsWith('enc--') ||
        envelopes.isEmpty) {
      throw const BusinessEncryptionRegistryException(
        'The Business file encryption rotation request is incomplete.',
      );
    }
    final response = await _call(
      'rotateBusinessFileEncryption',
      <String, Object?>{
        'fileId': normalizedFileId,
        'expectedObjectKey': normalizedExpectedObjectKey,
        'replacementObjectKey': normalizedReplacementObjectKey,
        'encryptedName': normalizedEncryptedName,
        'sharedKeyEnvelopes': <String, Object?>{
          for (final entry in envelopes.entries) entry.key: entry.value.toMap(),
        },
      },
    );
    final returnedFileId = _nonEmptyString(response['fileId']);
    final recipientCount = _nonNegativeInt(response['recipientCount']);
    final rotationGeneration = _positiveInt(response['rotationGeneration']);
    final cleanupPending = response['cleanupPending'];
    if (returnedFileId != normalizedFileId ||
        recipientCount == null ||
        recipientCount != envelopes.length ||
        rotationGeneration == null ||
        cleanupPending is! bool) {
      throw const BusinessEncryptionRegistryException(
        'Business file encryption rotation returned an inconsistent result.',
      );
    }
    return BusinessFileRotationResult(
      fileId: returnedFileId!,
      recipientCount: recipientCount,
      rotationGeneration: rotationGeneration,
      cleanupPending: cleanupPending,
    );
  }

  Future<BusinessEncryptedFolderSaveResult> saveEncryptedFolder({
    required String folderId,
    required String encryptedName,
    required String storageScope,
    required String color,
    required Map<String, BusinessFileKeyEnvelope> envelopes,
    String? parentId,
    String? groupId,
  }) async {
    final normalizedFolderId = folderId.trim();
    final normalizedEncryptedName = encryptedName.trim();
    final normalizedScope = storageScope.trim();
    final normalizedColor = color.trim();
    final normalizedParentId = parentId?.trim();
    final normalizedGroupId = groupId?.trim();
    if (normalizedFolderId.isEmpty ||
        normalizedEncryptedName.isEmpty ||
        normalizedColor.isEmpty ||
        envelopes.isEmpty ||
        (normalizedScope != 'company_shared' && normalizedScope != 'group') ||
        (normalizedScope == 'group' &&
            (normalizedGroupId == null || normalizedGroupId.isEmpty))) {
      throw const BusinessEncryptionRegistryException(
        'Encrypted Business folder metadata is incomplete.',
      );
    }
    final response = await _call(
      'saveBusinessEncryptedFolder',
      <String, Object?>{
        'folderId': normalizedFolderId,
        'encryptedName': normalizedEncryptedName,
        'metadataEncryption': 'business-envelope-aes-gcm-v1',
        'storageScope': normalizedScope,
        'color': normalizedColor,
        if (normalizedParentId != null && normalizedParentId.isNotEmpty)
          'parentId': normalizedParentId,
        if (normalizedScope == 'group') 'groupId': normalizedGroupId,
        'sharedKeyEnvelopes': <String, Object?>{
          for (final entry in envelopes.entries) entry.key: entry.value.toMap(),
        },
      },
    );
    final returnedFolderId = _nonEmptyString(response['folderId']);
    final recipientCount = _nonNegativeInt(response['recipientCount']);
    final created = response['created'];
    if (returnedFolderId != normalizedFolderId ||
        recipientCount == null ||
        recipientCount != envelopes.length ||
        created is! bool) {
      throw const BusinessEncryptionRegistryException(
        'The encrypted Business folder response is inconsistent.',
      );
    }
    return BusinessEncryptedFolderSaveResult(
      folderId: normalizedFolderId,
      recipientCount: recipientCount,
      created: created,
    );
  }

  Future<int> protectFileMetadata({
    required Iterable<String> fileIds,
    required String storageScope,
    String? groupId,
  }) async {
    final normalizedIds = fileIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final normalizedScope = storageScope.trim();
    final normalizedGroupId = groupId?.trim();
    if (normalizedIds.isEmpty ||
        normalizedIds.length > 200 ||
        (normalizedScope != 'company_shared' && normalizedScope != 'group') ||
        (normalizedScope == 'group' &&
            (normalizedGroupId == null || normalizedGroupId.isEmpty))) {
      throw const BusinessEncryptionRegistryException(
        'The Business metadata protection request is invalid.',
      );
    }
    final response =
        await _call('protectBusinessFileMetadata', <String, Object?>{
          'fileIds': normalizedIds,
          'storageScope': normalizedScope,
          if (normalizedScope == 'group') 'groupId': normalizedGroupId,
        });
    final requestedCount = _nonNegativeInt(response['requestedCount']);
    final protectedCount = _nonNegativeInt(response['protectedCount']);
    if (requestedCount != normalizedIds.length ||
        protectedCount == null ||
        protectedCount > requestedCount!) {
      throw const BusinessEncryptionRegistryException(
        'The Business metadata protection response is inconsistent.',
      );
    }
    return protectedCount;
  }

  Future<Map<String, Object?>> _call(
    String functionName, [
    Map<String, Object?>? payload,
  ]) async {
    try {
      final callable = _callable;
      if (callable != null) {
        return await callable(functionName, payload);
      }
      final result = await _functions!
          .httpsCallable(functionName)
          .call<Object?>(payload)
          .timeout(const Duration(seconds: 20));
      return _objectMap(result.data);
    } on BusinessEncryptionRegistryException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw BusinessEncryptionRegistryException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.businessEncryption,
          code: error.code,
        ),
      );
    } on BusinessEncryptionException catch (error) {
      throw BusinessEncryptionRegistryException(error.message);
    } on Exception {
      throw const BusinessEncryptionRegistryException(
        'Business encryption could not be prepared. Check your connection '
        'and try again.',
      );
    }
  }
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    throw const BusinessEncryptionRegistryException(
      'Business encryption returned an invalid response.',
    );
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int? _nonNegativeInt(Object? value) {
  if (value is int && value >= 0) {
    return value;
  }
  if (value is num && value.isFinite && value >= 0 && value.round() == value) {
    return value.toInt();
  }
  return null;
}

int? _positiveInt(Object? value) {
  final parsed = _nonNegativeInt(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
