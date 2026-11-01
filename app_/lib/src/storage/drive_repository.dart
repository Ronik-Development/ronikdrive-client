import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../security/workspace_metadata_encryption_service.dart';
import 'file_identity.dart';

class BackupCatalogEntry {
  const BackupCatalogEntry({
    required this.pathHash,
    required this.size,
    required this.modified,
    this.contentIntegrityTag = '',
    this.legacyHashBase64 = '',
  });

  final String pathHash;
  final int size;
  final DateTime modified;
  final String contentIntegrityTag;
  final String legacyHashBase64;
}

class DriveRepository {
  DriveRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  static void _log(String message) {
    if (!kDebugMode) {
      return;
    }
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[RonikCloud][drive-repo][$timestamp] $message');
  }

  static void _ensureDirectMetadataWritesSupported() {
    if (!kIsWeb) {
      return;
    }
    throw UnsupportedError(
      'Direct Firestore upload metadata writes are disabled on Flutter web. '
      'Use UploadMetadataService so large file sizes and timestamps are sent '
      'through the callable web-safe payload encoder.',
    );
  }

  Future<List<String>> getUserFileKeys(String uid) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) {
      return [];
    }

    final query = await _firestore
        .collection('files')
        .where('uid', isEqualTo: trimmedUid)
        .get();

    return query.docs
        .map((doc) => doc.data()['fileName'] as String?)
        .whereType<String>()
        .toList();
  }

  Future<void> deleteAllUserFiles(String uid) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) {
      return;
    }

    while (true) {
      final page = await _firestore
          .collection('files')
          .where('uid', isEqualTo: trimmedUid)
          .limit(400)
          .get();
      if (page.docs.isEmpty) {
        return;
      }
      final batch = _firestore.batch();
      for (final doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<int> syncUserUsageBytes({required String ownerId}) async {
    _ensureDirectMetadataWritesSupported();
    final trimmedOwnerId = ownerId.trim();
    if (trimmedOwnerId.isEmpty) {
      throw ArgumentError('ownerId cannot be empty.');
    }

    _log('Reconciling encrypted-storage usage.');

    final query = await _loadUserFiles(trimmedOwnerId);

    var totalUsageBytes = 0;
    for (final doc in query.docs) {
      final data = doc.data();
      totalUsageBytes += _resolveExistingSize(data) ?? 0;
    }

    await _firestore.collection('users').doc(trimmedOwnerId).set({
      'usageBytes': totalUsageBytes,
      'usageBytesUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _log('Encrypted-storage usage reconciliation finished.');

    return totalUsageBytes;
  }

  Future<void> upsertFileRecord({
    required String ownerId,
    required String objectKey,
    required int size,
    String? folderId,
    String? folderName,
    String? folderColorHex,
    required String encryptionMode,
    DateTime? uploadedAt,
    List<String>? pathSegments,
    String? contentIntegrityTag,
    String? contentIntegrityVersion,
    required String encryptedName,
    String storageLayout = 'single',
    int? shardCount,
    int? shardSizeBytes,
    String? shardScheme,
    required String contentEncryption,
    String? secureContentEncoding,
    DateTime? secureRefreshedAt,
    DateTime? secureRefreshDueAt,
    String? backupPathHash,
    int? backupModifiedMillis,
  }) async {
    _ensureDirectMetadataWritesSupported();
    final trimmedOwnerId = ownerId.trim();
    if (trimmedOwnerId.isEmpty) {
      throw ArgumentError('ownerId cannot be empty.');
    }

    final sanitizedObjectKey = objectKey.trim();
    if (sanitizedObjectKey.isEmpty) {
      throw ArgumentError('objectKey cannot be empty.');
    }
    String? normalized(String? value) {
      if (value == null) {
        return null;
      }
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final normalizedMode = encryptionMode.trim().toLowerCase();
    final normalizedContentEncryption = contentEncryption.trim().toLowerCase();
    final normalizedEncryptedName = encryptedName.trim();
    if ((normalizedMode != 'standard' && normalizedMode != 'secured') ||
        (normalizedMode == 'standard' &&
            normalizedContentEncryption != 'standard') ||
        (normalizedMode == 'secured' &&
            normalizedContentEncryption != 'secure') ||
        normalizedEncryptedName.isEmpty) {
      throw ArgumentError(
        'File metadata requires a consistent client-side encryption mode and '
        'an encrypted name.',
      );
    }
    final normalizedStorageLayout =
        storageLayout.trim().toLowerCase() == 'sharded' ? 'sharded' : 'single';
    final normalizedIntegrityTag = normalized(contentIntegrityTag);
    final normalizedIntegrityVersion = normalized(contentIntegrityVersion);
    if ((normalizedIntegrityTag == null) !=
            (normalizedIntegrityVersion == null) ||
        (normalizedIntegrityTag != null &&
            (!normalizedIntegrityTag.startsWith(
                  WorkspaceMetadataEncryptionService.contentIntegrityTagPrefix,
                ) ||
                normalizedIntegrityVersion !=
                    WorkspaceMetadataEncryptionService
                        .contentIntegrityVersion ||
                normalizedMode != 'standard'))) {
      throw ArgumentError(
        'Content integrity metadata requires a valid keyed tag and version.',
      );
    }

    final normalizedSize = size < 0 ? 0 : size;
    final uploadTimestamp = Timestamp.fromDate(
      (uploadedAt ?? DateTime.now().toUtc()).toUtc(),
    );
    final normalizedPathSegments = <String>[
      for (final segment in pathSegments ?? const <String>[])
        if (segment.trim().isNotEmpty) segment.trim(),
    ];

    final createPayload = <String, dynamic>{
      'uid': trimmedOwnerId,
      'fileName': sanitizedObjectKey,
      'objectKeyHash': objectKeyHash(sanitizedObjectKey),
      'fileIdVersion': 3,
      'sizeBytes': normalizedSize,
      'encryptionMode': normalizedMode,
      'storageLayout': normalizedStorageLayout,
      'uploadedAt': uploadTimestamp,
    };

    void addOptional(Map<String, dynamic> map, String key, String? value) {
      final normalizedValue = normalized(value);
      if (normalizedValue != null) {
        map[key] = normalizedValue;
      }
    }

    void addOptionalInt(Map<String, dynamic> map, String key, int? value) {
      if (value != null) {
        map[key] = value;
      }
    }

    void addOptionalPathSegments(
      Map<String, dynamic> map,
      List<String> segments,
    ) {
      if (segments.isNotEmpty) {
        map['pathSegments'] = segments;
      }
    }

    void setOptionalForUpdate(
      Map<String, dynamic> map,
      String key,
      String? value,
    ) {
      final normalizedValue = normalized(value);
      map[key] = normalizedValue ?? FieldValue.delete();
    }

    void setOptionalIntForUpdate(
      Map<String, dynamic> map,
      String key,
      int? value,
    ) {
      map[key] = value ?? FieldValue.delete();
    }

    void setOptionalPathSegmentsForUpdate(
      Map<String, dynamic> map,
      List<String> segments,
    ) {
      map['pathSegments'] = segments.isEmpty ? FieldValue.delete() : segments;
    }

    addOptional(createPayload, 'folderId', folderId);
    addOptional(createPayload, 'folderName', folderName);
    addOptional(createPayload, 'folderColor', folderColorHex);
    addOptionalPathSegments(createPayload, normalizedPathSegments);
    addOptional(createPayload, 'contentIntegrityTag', normalizedIntegrityTag);
    addOptional(
      createPayload,
      'contentIntegrityVersion',
      normalizedIntegrityVersion,
    );
    addOptional(createPayload, 'encryptedName', normalizedEncryptedName);
    addOptional(createPayload, 'shardScheme', shardScheme);
    addOptionalInt(createPayload, 'shardCount', shardCount);
    addOptionalInt(createPayload, 'shardSizeBytes', shardSizeBytes);
    addOptional(
      createPayload,
      'contentEncryption',
      normalizedContentEncryption,
    );
    addOptional(createPayload, 'secureContentEncoding', secureContentEncoding);
    if (secureRefreshedAt != null) {
      createPayload['secureRefreshedAt'] = Timestamp.fromDate(
        secureRefreshedAt.toUtc(),
      );
    }
    if (secureRefreshDueAt != null) {
      createPayload['secureRefreshDueAt'] = Timestamp.fromDate(
        secureRefreshDueAt.toUtc(),
      );
    }
    addOptional(createPayload, 'backupPathHash', backupPathHash);
    addOptionalInt(createPayload, 'backupModifiedMillis', backupModifiedMillis);

    final files = _firestore.collection('files');
    final hash = objectKeyHash(sanitizedObjectKey);
    final matching = await files
        .where('uid', isEqualTo: trimmedOwnerId)
        .where('objectKeyHash', isEqualTo: hash)
        .limit(10)
        .get();
    DocumentReference<Map<String, dynamic>>? matchingRef;
    Map<String, dynamic>? matchingData;
    for (final candidate in matching.docs) {
      final candidateKey = _trimmedString(
        candidate.data()['fileName'] ?? candidate.data()['objectKey'],
      );
      if (candidateKey == sanitizedObjectKey) {
        matchingRef = candidate.reference;
        matchingData = candidate.data();
        break;
      }
    }
    final hashedRef = files.doc(
      hashedFileDocumentIdForObjectKey(sanitizedObjectKey),
    );
    final legacyRef = files.doc(
      legacyFileDocumentIdForObjectKey(sanitizedObjectKey),
    );
    var fileRef = matchingRef;
    var existingData = matchingData;
    if (fileRef == null) {
      final hashedData = await _fetchExistingData(hashedRef);
      final hashedObjectKey = _trimmedString(
        hashedData?['fileName'] ?? hashedData?['objectKey'],
      );
      if (hashedData != null && hashedObjectKey == sanitizedObjectKey) {
        fileRef = hashedRef;
        existingData = hashedData;
      }
    }
    if (fileRef == null && legacyRef.id != hashedRef.id) {
      final legacyData = await _fetchExistingData(legacyRef);
      final legacyObjectKey = _trimmedString(
        legacyData?['fileName'] ?? legacyData?['objectKey'],
      );
      if (legacyData != null && legacyObjectKey == sanitizedObjectKey) {
        fileRef = legacyRef;
        existingData = legacyData;
      }
    }
    final resolvedFileRef = fileRef ?? files.doc();
    createPayload['fileId'] = resolvedFileRef.id;
    var existingSize = existingData == null
        ? null
        : _resolveExistingSize(existingData);
    var needsFullUsageReconciliation = false;

    Future<void> createRecord() async {
      _log('Writing protected file metadata.');
      await resolvedFileRef.set(createPayload);
      _log('Protected file metadata write completed.');
    }

    try {
      await createRecord();
    } on FirebaseException catch (error) {
      _log('The initial protected file metadata write was unavailable.');
      if (error.code != 'permission-denied') {
        rethrow;
      }

      existingData ??= await _fetchExistingData(resolvedFileRef);
      existingSize ??= existingData == null
          ? null
          : _resolveExistingSize(existingData);
      if (existingData == null) {
        _log(
          'No existing protected file metadata was readable after a denied '
          'write; replacement was not attempted.',
        );
        rethrow;
      } else {
        final existingOwner = _trimmedString(existingData['uid']);
        if (existingOwner != null && existingOwner != trimmedOwnerId) {
          rethrow;
        }

        final updatePayload = <String, dynamic>{
          'uid': trimmedOwnerId,
          'fileName': sanitizedObjectKey,
          'fileId': resolvedFileRef.id,
          'objectKeyHash': objectKeyHash(sanitizedObjectKey),
          'fileIdVersion': 3,
          'encryptionMode': normalizedMode,
          'storageLayout': normalizedStorageLayout,
          'hasThumbnail': FieldValue.delete(),
        };

        setOptionalForUpdate(updatePayload, 'folderId', folderId);
        setOptionalForUpdate(updatePayload, 'folderName', folderName);
        setOptionalForUpdate(updatePayload, 'folderColor', folderColorHex);
        setOptionalPathSegmentsForUpdate(updatePayload, normalizedPathSegments);
        setOptionalForUpdate(
          updatePayload,
          'contentIntegrityTag',
          normalizedIntegrityTag,
        );
        setOptionalForUpdate(
          updatePayload,
          'contentIntegrityVersion',
          normalizedIntegrityVersion,
        );
        updatePayload['hashBase64'] = FieldValue.delete();
        setOptionalForUpdate(updatePayload, 'encryptedName', encryptedName);
        setOptionalForUpdate(updatePayload, 'shardScheme', shardScheme);
        setOptionalIntForUpdate(updatePayload, 'shardCount', shardCount);
        setOptionalIntForUpdate(
          updatePayload,
          'shardSizeBytes',
          shardSizeBytes,
        );
        setOptionalForUpdate(
          updatePayload,
          'contentEncryption',
          contentEncryption,
        );
        setOptionalForUpdate(
          updatePayload,
          'secureContentEncoding',
          secureContentEncoding,
        );
        updatePayload['secureRefreshedAt'] = secureRefreshedAt == null
            ? FieldValue.delete()
            : Timestamp.fromDate(secureRefreshedAt.toUtc());
        updatePayload['secureRefreshDueAt'] = secureRefreshDueAt == null
            ? FieldValue.delete()
            : Timestamp.fromDate(secureRefreshDueAt.toUtc());
        setOptionalForUpdate(updatePayload, 'backupPathHash', backupPathHash);
        setOptionalIntForUpdate(
          updatePayload,
          'backupModifiedMillis',
          backupModifiedMillis,
        );

        if (existingSize == null || existingSize == normalizedSize) {
          updatePayload['sizeBytes'] = normalizedSize;
        } else {
          _log(
            'Protected file metadata required replacement and usage '
            'reconciliation.',
          );
          await _replaceRecord(resolvedFileRef, createPayload);
          needsFullUsageReconciliation = true;
        }

        if (!needsFullUsageReconciliation) {
          try {
            _log('Merging existing protected file metadata.');
            await resolvedFileRef.set(updatePayload, SetOptions(merge: true));
            _log('Protected file metadata merge completed.');
          } on FirebaseException catch (updateError) {
            _log('Protected file metadata merge was unavailable.');
            if (updateError.code != 'permission-denied') {
              rethrow;
            }
            await _replaceRecord(resolvedFileRef, createPayload);
            needsFullUsageReconciliation = true;
          }
        }
      }
    }

    try {
      if (needsFullUsageReconciliation) {
        _log('Running full usage reconciliation after a metadata update.');
        await syncUserUsageBytes(ownerId: trimmedOwnerId);
      } else {
        final usageDeltaBytes = normalizedSize - (existingSize ?? 0);
        if (usageDeltaBytes != 0) {
          _log('Applying a bounded usage update after metadata confirmation.');
          await _applyUserUsageDelta(
            ownerId: trimmedOwnerId,
            deltaBytes: usageDeltaBytes,
          );
          _log('Bounded usage update applied.');
        }
      }
    } catch (_) {
      _log('Usage reconciliation was unavailable after a metadata update.');
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadUserFiles(
    String ownerId,
  ) async {
    final query = _firestore
        .collection('files')
        .where('uid', isEqualTo: ownerId);
    try {
      return await query.get(const GetOptions(source: Source.server));
    } on FirebaseException catch (error) {
      if (error.code != 'unavailable') {
        rethrow;
      }
      return query.get();
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadUserFolders(
    String ownerId,
  ) async {
    final query = _firestore
        .collection('folders')
        .where('uid', isEqualTo: ownerId);
    try {
      return await query.get(const GetOptions(source: Source.server));
    } on FirebaseException catch (error) {
      if (error.code != 'unavailable') {
        rethrow;
      }
      return query.get();
    }
  }

  Future<Map<String, BackupCatalogEntry>> loadBackupCatalog({
    required String ownerId,
    required String folderId,
  }) async {
    final trimmedOwnerId = ownerId.trim();
    final trimmedFolderId = folderId.trim();
    if (trimmedOwnerId.isEmpty || trimmedFolderId.isEmpty) {
      return const <String, BackupCatalogEntry>{};
    }

    final snapshot = await _loadUserFiles(trimmedOwnerId);
    final foldersSnapshot = await _loadUserFolders(trimmedOwnerId);
    final descendantFolderIds = <String>{trimmedFolderId};

    var changed = true;
    while (changed) {
      changed = false;
      for (final doc in foldersSnapshot.docs) {
        final data = doc.data();
        final parentId = _trimmedString(data['parentId']);
        if (parentId == null || !descendantFolderIds.contains(parentId)) {
          continue;
        }
        if (descendantFolderIds.add(doc.id)) {
          changed = true;
        }
      }
    }

    final catalog = <String, BackupCatalogEntry>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final lifecycleState = _trimmedString(data['lifecycleState']) ?? 'active';
      if (lifecycleState != 'active') {
        continue;
      }
      final entryFolderId = _trimmedString(data['folderId']);
      if (entryFolderId == null ||
          !descendantFolderIds.contains(entryFolderId)) {
        continue;
      }

      final pathHash = _trimmedString(data['backupPathHash']);
      if (pathHash == null) {
        continue;
      }

      final size = _resolveExistingSize(data) ?? 0;
      final rawModifiedMillis = data['backupModifiedMillis'];
      final modifiedMillis = _parseSizeValue(rawModifiedMillis);
      if (modifiedMillis == null) {
        continue;
      }

      final contentIntegrityTag =
          _trimmedString(data['contentIntegrityTag']) ?? '';
      final legacyHashBase64 = _trimmedString(data['hashBase64']) ?? '';
      catalog[pathHash] = BackupCatalogEntry(
        pathHash: pathHash,
        size: size,
        modified: DateTime.fromMillisecondsSinceEpoch(
          modifiedMillis,
          isUtc: true,
        ),
        contentIntegrityTag: contentIntegrityTag,
        legacyHashBase64: legacyHashBase64,
      );
    }

    return catalog;
  }

  Future<void> _applyUserUsageDelta({
    required String ownerId,
    required int deltaBytes,
  }) async {
    _ensureDirectMetadataWritesSupported();
    if (deltaBytes == 0) {
      return;
    }

    if (deltaBytes < 0) {
      _log('A decreasing usage update requires full reconciliation.');
      await syncUserUsageBytes(ownerId: ownerId);
      return;
    }

    final userRef = _firestore.collection('users').doc(ownerId);
    await userRef.set({
      'usageBytes': FieldValue.increment(deltaBytes),
      'usageBytesUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> _fetchExistingData(
    DocumentReference<Map<String, dynamic>> reference,
  ) async {
    try {
      final snapshot = await reference.get();
      if (!snapshot.exists) {
        return null;
      }
      return snapshot.data();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }

  Future<void> _replaceRecord(
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> payload,
  ) async {
    try {
      await reference.delete();
    } on FirebaseException catch (error) {
      if (error.code != 'not-found') {
        rethrow;
      }
    }

    await reference.set(payload);
  }

  int? _resolveExistingSize(Map<String, dynamic> data) {
    final sizeBytes = _parseSizeValue(data['sizeBytes']);
    if (sizeBytes != null) {
      return sizeBytes;
    }
    return _parseSizeValue(data['size']);
  }

  int? _parseSizeValue(dynamic value) {
    if (value is int) {
      return value < 0 ? 0 : value;
    }
    if (value is double) {
      if (value.isNaN || !value.isFinite) {
        return null;
      }
      final rounded = value.round();
      return rounded < 0 ? 0 : rounded;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final direct = int.tryParse(trimmed);
      if (direct != null) {
        return direct < 0 ? 0 : direct;
      }
      final numeric = double.tryParse(trimmed);
      if (numeric != null && numeric.isFinite) {
        final rounded = numeric.round();
        return rounded < 0 ? 0 : rounded;
      }
      final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(trimmed);
      if (match != null) {
        final fallback = double.tryParse(match.group(1)!);
        if (fallback != null && fallback.isFinite) {
          final rounded = fallback.round();
          return rounded < 0 ? 0 : rounded;
        }
      }
    }
    return null;
  }

  String? _trimmedString(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }
}
