import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../privacy/local_private_cache.dart';

class BusinessReconciliationCheckpointException implements Exception {
  const BusinessReconciliationCheckpointException(this.message);

  final String message;

  @override
  String toString() => 'BusinessReconciliationCheckpointException: $message';
}

class BusinessReconciliationCheckpointLoad {
  const BusinessReconciliationCheckpointLoad({
    required this.checkpoints,
    this.discardedCorruptValue = false,
    this.temporarilyUnavailable = false,
  });

  final List<BusinessReconciliationCheckpoint> checkpoints;
  final bool discardedCorruptValue;
  final bool temporarilyUnavailable;
}

class BusinessReconciliationCheckpoint {
  BusinessReconciliationCheckpoint.start({
    required this.companyId,
    required this.storageScope,
    required this.groupId,
    required this.recipientFingerprint,
    DateTime? startedAt,
  }) : startedAt = (startedAt ?? DateTime.now()).toUtc(),
       updatedAt = (startedAt ?? DateTime.now()).toUtc(),
       _completedFileIds = <String>{},
       _completedFolderIds = <String>{},
       _completedMetadataFileIds = <String>{};

  BusinessReconciliationCheckpoint._({
    required this.companyId,
    required this.storageScope,
    required this.groupId,
    required this.recipientFingerprint,
    required this.startedAt,
    required this.updatedAt,
    required Set<String> completedFileIds,
    required Set<String> completedFolderIds,
    required Set<String> completedMetadataFileIds,
    required this.refreshedFiles,
    required this.rotatedFiles,
    required this.cleanupPendingFiles,
    required this.addedEnvelopes,
    required this.alreadyCurrentFiles,
    required this.protectedFileMetadata,
    required this.refreshedFolders,
    required this.alreadyCurrentFolders,
  }) : _completedFileIds = completedFileIds,
       _completedFolderIds = completedFolderIds,
       _completedMetadataFileIds = completedMetadataFileIds;

  static const int version = 1;
  static const int maxTrackedItems = 100000;

  final String companyId;
  final String storageScope;
  final String? groupId;
  final String recipientFingerprint;
  final DateTime startedAt;
  DateTime updatedAt;
  final Set<String> _completedFileIds;
  final Set<String> _completedFolderIds;
  final Set<String> _completedMetadataFileIds;

  int refreshedFiles = 0;
  int rotatedFiles = 0;
  int cleanupPendingFiles = 0;
  int addedEnvelopes = 0;
  int alreadyCurrentFiles = 0;
  int protectedFileMetadata = 0;
  int refreshedFolders = 0;
  int alreadyCurrentFolders = 0;

  String get workspaceKey => workspaceKeyFor(
    companyId: companyId,
    storageScope: storageScope,
    groupId: groupId,
  );

  int get completedFileCount => _completedFileIds.length;
  int get completedFolderCount => _completedFolderIds.length;
  int get completedMetadataFileCount => _completedMetadataFileIds.length;

  bool isFileComplete(String fileId) => _completedFileIds.contains(fileId);
  bool isFolderComplete(String folderId) =>
      _completedFolderIds.contains(folderId);
  bool isMetadataFileComplete(String fileId) =>
      _completedMetadataFileIds.contains(fileId);

  bool matches({
    required String companyId,
    required String storageScope,
    required String? groupId,
    required String recipientFingerprint,
  }) {
    return this.companyId == companyId.trim() &&
        this.storageScope == storageScope.trim().toLowerCase() &&
        this.groupId == _normalizeOptional(groupId) &&
        this.recipientFingerprint == recipientFingerprint.trim().toLowerCase();
  }

  void markFileComplete(
    String fileId, {
    int refreshed = 0,
    int rotated = 0,
    int cleanupPending = 0,
    int envelopesAdded = 0,
    int alreadyCurrent = 0,
  }) {
    final normalizedId = _validateId(fileId, 'file id');
    if (!_completedFileIds.add(normalizedId)) {
      return;
    }
    _checkTrackedItemLimit();
    refreshedFiles = _safeAdd(refreshedFiles, refreshed, 'refreshed files');
    rotatedFiles = _safeAdd(rotatedFiles, rotated, 'rotated files');
    cleanupPendingFiles = _safeAdd(
      cleanupPendingFiles,
      cleanupPending,
      'pending cleanup files',
    );
    addedEnvelopes = _safeAdd(
      addedEnvelopes,
      envelopesAdded,
      'added envelopes',
    );
    alreadyCurrentFiles = _safeAdd(
      alreadyCurrentFiles,
      alreadyCurrent,
      'current files',
    );
    updatedAt = DateTime.now().toUtc();
  }

  void markFolderComplete(
    String folderId, {
    int refreshed = 0,
    int alreadyCurrent = 0,
  }) {
    final normalizedId = _validateId(folderId, 'folder id');
    if (!_completedFolderIds.add(normalizedId)) {
      return;
    }
    _checkTrackedItemLimit();
    refreshedFolders = _safeAdd(
      refreshedFolders,
      refreshed,
      'refreshed folders',
    );
    alreadyCurrentFolders = _safeAdd(
      alreadyCurrentFolders,
      alreadyCurrent,
      'current folders',
    );
    updatedAt = DateTime.now().toUtc();
  }

  void markMetadataComplete(
    Iterable<String> fileIds, {
    required int protectedCount,
  }) {
    var addedCount = 0;
    for (final fileId in fileIds) {
      if (_completedMetadataFileIds.add(_validateId(fileId, 'file id'))) {
        addedCount += 1;
      }
    }
    _checkTrackedItemLimit();
    if (addedCount > 0) {
      protectedFileMetadata = _safeAdd(
        protectedFileMetadata,
        protectedCount,
        'protected metadata files',
      );
      updatedAt = DateTime.now().toUtc();
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
      'companyId': companyId,
      'storageScope': storageScope,
      if (groupId != null) 'groupId': groupId,
      'recipientFingerprint': recipientFingerprint,
      'startedAtMs': startedAt.millisecondsSinceEpoch,
      'updatedAtMs': updatedAt.millisecondsSinceEpoch,
      'completedFileIds': _completedFileIds.toList()..sort(),
      'completedFolderIds': _completedFolderIds.toList()..sort(),
      'completedMetadataFileIds': _completedMetadataFileIds.toList()..sort(),
      'refreshedFiles': refreshedFiles,
      'rotatedFiles': rotatedFiles,
      'cleanupPendingFiles': cleanupPendingFiles,
      'addedEnvelopes': addedEnvelopes,
      'alreadyCurrentFiles': alreadyCurrentFiles,
      'protectedFileMetadata': protectedFileMetadata,
      'refreshedFolders': refreshedFolders,
      'alreadyCurrentFolders': alreadyCurrentFolders,
    };
  }

  factory BusinessReconciliationCheckpoint.fromJson(Map<String, dynamic> json) {
    if (json['version'] != version) {
      throw const BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint version is unsupported.',
      );
    }
    final companyId = _validateId(json['companyId'], 'company id', max: 160);
    final storageScope = _validateScope(json['storageScope']);
    final groupId = _normalizeOptional(json['groupId']);
    if (storageScope == 'group' && groupId == null) {
      throw const BusinessReconciliationCheckpointException(
        'A group reconciliation checkpoint requires a group id.',
      );
    }
    if (storageScope != 'group' && groupId != null) {
      throw const BusinessReconciliationCheckpointException(
        'Only group reconciliation checkpoints may contain a group id.',
      );
    }
    final fingerprint = _validateFingerprint(json['recipientFingerprint']);
    final startedAt = _parseTimestamp(json['startedAtMs'], 'start time');
    final updatedAt = _parseTimestamp(json['updatedAtMs'], 'update time');
    if (updatedAt.isBefore(startedAt)) {
      throw const BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint timestamps are inconsistent.',
      );
    }

    final checkpoint = BusinessReconciliationCheckpoint._(
      companyId: companyId,
      storageScope: storageScope,
      groupId: groupId,
      recipientFingerprint: fingerprint,
      startedAt: startedAt,
      updatedAt: updatedAt,
      completedFileIds: _parseIds(json['completedFileIds'], 'file ids'),
      completedFolderIds: _parseIds(json['completedFolderIds'], 'folder ids'),
      completedMetadataFileIds: _parseIds(
        json['completedMetadataFileIds'],
        'metadata file ids',
      ),
      refreshedFiles: _parseCount(json['refreshedFiles'], 'refreshed files'),
      rotatedFiles: _parseCount(json['rotatedFiles'], 'rotated files'),
      cleanupPendingFiles: _parseCount(
        json['cleanupPendingFiles'],
        'pending cleanup files',
      ),
      addedEnvelopes: _parseCount(json['addedEnvelopes'], 'added envelopes'),
      alreadyCurrentFiles: _parseCount(
        json['alreadyCurrentFiles'],
        'current files',
      ),
      protectedFileMetadata: _parseCount(
        json['protectedFileMetadata'],
        'protected metadata files',
      ),
      refreshedFolders: _parseCount(
        json['refreshedFolders'],
        'refreshed folders',
      ),
      alreadyCurrentFolders: _parseCount(
        json['alreadyCurrentFolders'],
        'current folders',
      ),
    );
    checkpoint._checkTrackedItemLimit();
    return checkpoint;
  }

  static String workspaceKeyFor({
    required String companyId,
    required String storageScope,
    required String? groupId,
  }) {
    final normalizedCompanyId = _validateId(companyId, 'company id', max: 160);
    final normalizedScope = _validateScope(storageScope);
    final normalizedGroupId = _normalizeOptional(groupId);
    if (normalizedScope == 'group' && normalizedGroupId == null) {
      throw const BusinessReconciliationCheckpointException(
        'A group workspace requires a group id.',
      );
    }
    final input =
        'ronikdrive-business-reconciliation-v1\n'
        '$normalizedCompanyId\n$normalizedScope\n${normalizedGroupId ?? ''}';
    return crypto.sha256.convert(utf8.encode(input)).toString();
  }

  void _checkTrackedItemLimit() {
    final tracked =
        _completedFileIds.length +
        _completedFolderIds.length +
        _completedMetadataFileIds.length;
    if (tracked > maxTrackedItems) {
      throw const BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint contains too many items.',
      );
    }
  }

  static String _validateScope(Object? value) {
    final scope = value is String ? value.trim().toLowerCase() : '';
    if (scope != 'company_shared' && scope != 'group') {
      throw const BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint storage scope is invalid.',
      );
    }
    return scope;
  }

  static String _validateFingerprint(Object? value) {
    final fingerprint = value is String ? value.trim().toLowerCase() : '';
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw const BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint recipient fingerprint is invalid.',
      );
    }
    return fingerprint;
  }

  static Set<String> _parseIds(Object? value, String label) {
    if (value is! List || value.length > maxTrackedItems) {
      throw BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint $label are invalid.',
      );
    }
    final result = <String>{};
    for (final item in value) {
      result.add(_validateId(item, label));
    }
    return result;
  }

  static String _validateId(Object? value, String label, {int max = 1024}) {
    final normalized = value is String ? value.trim() : '';
    if (normalized.isEmpty || normalized.length > max) {
      throw BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint $label is invalid.',
      );
    }
    return normalized;
  }

  static String? _normalizeOptional(Object? value) {
    if (value == null) {
      return null;
    }
    final normalized = value is String ? value.trim() : '';
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.length > 160) {
      throw const BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint group id is invalid.',
      );
    }
    return normalized;
  }

  static DateTime _parseTimestamp(Object? value, String label) {
    if (value is! int || value <= 0) {
      throw BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint $label is invalid.',
      );
    }
    try {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    } catch (_) {
      throw BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint $label is invalid.',
      );
    }
  }

  static int _parseCount(Object? value, String label) {
    if (value is! int || value < 0 || value > 1000000000) {
      throw BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint $label count is invalid.',
      );
    }
    return value;
  }

  static int _safeAdd(int current, int addition, String label) {
    if (addition < 0 || current + addition > 1000000000) {
      throw BusinessReconciliationCheckpointException(
        'The reconciliation checkpoint $label count is invalid.',
      );
    }
    return current + addition;
  }
}

class BusinessReconciliationCheckpointStore {
  BusinessReconciliationCheckpointStore({
    required LocalPrivateCachePreferences privateCache,
  }) : _privateCache = privateCache;

  static const int _maxCheckpoints = 64;

  final LocalPrivateCachePreferences _privateCache;
  Map<String, BusinessReconciliationCheckpoint>? _cached;

  Future<BusinessReconciliationCheckpointLoad> load() async {
    final read = await _privateCache.read(
      baseKey: LocalPrivateCacheCodec.businessReconciliationPreferenceKey,
      namespace: LocalPrivateCacheCodec.businessReconciliationNamespace,
    );
    if (read.temporarilyUnavailable) {
      return const BusinessReconciliationCheckpointLoad(
        checkpoints: <BusinessReconciliationCheckpoint>[],
        temporarilyUnavailable: true,
      );
    }
    if (read.value == null) {
      _cached = <String, BusinessReconciliationCheckpoint>{};
      return BusinessReconciliationCheckpointLoad(
        checkpoints: const <BusinessReconciliationCheckpoint>[],
        discardedCorruptValue: read.discardedCorruptValue,
      );
    }

    try {
      final decoded = jsonDecode(read.value!);
      if (decoded is! Map ||
          decoded['version'] != BusinessReconciliationCheckpoint.version ||
          decoded['checkpoints'] is! List) {
        throw const FormatException('Invalid checkpoint container.');
      }
      final rawCheckpoints = decoded['checkpoints'] as List;
      if (rawCheckpoints.length > _maxCheckpoints) {
        throw const FormatException('Too many checkpoints.');
      }
      final checkpoints = <String, BusinessReconciliationCheckpoint>{};
      for (final raw in rawCheckpoints) {
        if (raw is! Map) {
          throw const FormatException('Invalid checkpoint entry.');
        }
        final checkpoint = BusinessReconciliationCheckpoint.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (checkpoints.containsKey(checkpoint.workspaceKey)) {
          throw const FormatException('Duplicate checkpoint workspace.');
        }
        checkpoints[checkpoint.workspaceKey] = checkpoint;
      }
      _cached = checkpoints;
      return BusinessReconciliationCheckpointLoad(
        checkpoints: _copies(checkpoints.values),
      );
    } catch (_) {
      await _privateCache.write(
        baseKey: LocalPrivateCacheCodec.businessReconciliationPreferenceKey,
        namespace: LocalPrivateCacheCodec.businessReconciliationNamespace,
        value: null,
      );
      _cached = <String, BusinessReconciliationCheckpoint>{};
      return const BusinessReconciliationCheckpointLoad(
        checkpoints: <BusinessReconciliationCheckpoint>[],
        discardedCorruptValue: true,
      );
    }
  }

  Future<void> save(BusinessReconciliationCheckpoint checkpoint) async {
    final current = await _ensureAvailable();
    final next = <String, BusinessReconciliationCheckpoint>{
      for (final entry in current.entries) entry.key: _copy(entry.value),
      checkpoint.workspaceKey: _copy(checkpoint),
    };
    if (next.length > _maxCheckpoints) {
      final oldest = next.values.reduce(
        (left, right) =>
            left.updatedAt.isBefore(right.updatedAt) ? left : right,
      );
      next.remove(oldest.workspaceKey);
    }
    await _persist(next);
  }

  Future<void> remove(String workspaceKey) async {
    final current = await _ensureAvailable();
    if (!current.containsKey(workspaceKey)) {
      return;
    }
    final next = <String, BusinessReconciliationCheckpoint>{
      for (final entry in current.entries)
        if (entry.key != workspaceKey) entry.key: _copy(entry.value),
    };
    await _persist(next);
  }

  Future<void> clearAll() async {
    await _privateCache.write(
      baseKey: LocalPrivateCacheCodec.businessReconciliationPreferenceKey,
      namespace: LocalPrivateCacheCodec.businessReconciliationNamespace,
      value: null,
    );
    _cached = <String, BusinessReconciliationCheckpoint>{};
  }

  Future<Map<String, BusinessReconciliationCheckpoint>>
  _ensureAvailable() async {
    final existing = _cached;
    if (existing != null) {
      return existing;
    }
    final loaded = await load();
    if (loaded.temporarilyUnavailable) {
      throw const BusinessReconciliationCheckpointException(
        'Encrypted reconciliation progress is waiting for the device credential store.',
      );
    }
    return _cached ?? <String, BusinessReconciliationCheckpoint>{};
  }

  Future<void> _persist(
    Map<String, BusinessReconciliationCheckpoint> checkpoints,
  ) async {
    final ordered = checkpoints.values.toList()
      ..sort((left, right) => left.workspaceKey.compareTo(right.workspaceKey));
    final payload = jsonEncode(<String, Object?>{
      'version': BusinessReconciliationCheckpoint.version,
      'checkpoints': ordered.map((item) => item.toJson()).toList(),
    });
    await _privateCache.write(
      baseKey: LocalPrivateCacheCodec.businessReconciliationPreferenceKey,
      namespace: LocalPrivateCacheCodec.businessReconciliationNamespace,
      value: checkpoints.isEmpty ? null : payload,
    );
    _cached = <String, BusinessReconciliationCheckpoint>{
      for (final checkpoint in ordered)
        checkpoint.workspaceKey: _copy(checkpoint),
    };
  }

  static BusinessReconciliationCheckpoint _copy(
    BusinessReconciliationCheckpoint checkpoint,
  ) {
    return BusinessReconciliationCheckpoint.fromJson(
      Map<String, dynamic>.from(checkpoint.toJson()),
    );
  }

  static List<BusinessReconciliationCheckpoint> _copies(
    Iterable<BusinessReconciliationCheckpoint> checkpoints,
  ) {
    return checkpoints.map(_copy).toList(growable: false);
  }
}
