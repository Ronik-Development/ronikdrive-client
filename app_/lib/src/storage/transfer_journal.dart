import '../shared/transfer_verification_pause.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../privacy/local_private_cache.dart';
import 'multipart_upload_checkpoint_sink.dart';

enum TransferJournalState {
  queued,
  inProgress,
  awaitingMetadata,
  completed,
  failed,
  canceled,
  cleanedUp,
  cleanupRequired,
  interrupted,
}

enum TransferJournalKind { upload, download, backup, restore, cleanup }

const String transferJournalMetadataRetryMessage =
    'The encrypted upload finished, but workspace indexing is waiting for a safe retry.';
const String transferJournalCleanupRetryMessage =
    'Encrypted remote cleanup is waiting for a safe retry.';
const String transferJournalFailureMessage =
    'This transfer did not finish. Retry it from the workspace.';

class TransferJournalEntry {
  TransferJournalEntry({
    required this.id,
    required this.kind,
    required this.state,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
    this.objectKey,
    this.localPath,
    this.resumeContext,
    this.totalBytes = 0,
    this.transferredBytes = 0,
    this.multipartUploadId,
    this.uploadCheckpoint,
    Map<int, String> completedParts = const <int, String>{},
    Map<String, dynamic>? metadataPayload,
    this.lastError,
  }) : completedParts = Map<int, String>.unmodifiable(completedParts),
       metadataPayload = metadataPayload == null
           ? null
           : Map<String, dynamic>.unmodifiable(metadataPayload);

  final String id;
  final TransferJournalKind kind;
  final TransferJournalState state;
  final String label;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? objectKey;
  final String? localPath;
  final String? resumeContext;
  final int totalBytes;
  final int transferredBytes;
  final String? multipartUploadId;
  final Map<String, dynamic>? uploadCheckpoint;
  final Map<int, String> completedParts;
  final Map<String, dynamic>? metadataPayload;
  final String? lastError;

  bool get canRetryMetadata =>
      state == TransferJournalState.awaitingMetadata && metadataPayload != null;

  bool get isPending => const <TransferJournalState>{
    TransferJournalState.queued,
    TransferJournalState.inProgress,
    TransferJournalState.awaitingMetadata,
    TransferJournalState.cleanupRequired,
    TransferJournalState.interrupted,
  }.contains(state);

  TransferJournalEntry copyWith({
    required DateTime updatedAt,
    TransferJournalState? state,
    String? label,
    int? totalBytes,
    int? transferredBytes,
    String? objectKey,
    String? localPath,
    String? multipartUploadId,
    Map<String, dynamic>? uploadCheckpoint,
    Map<int, String>? completedParts,
    Map<String, dynamic>? metadataPayload,
    String? lastError,
    bool clearMultipartUploadId = false,
    bool clearMetadataPayload = false,
    bool clearLastError = false,
  }) {
    return TransferJournalEntry(
      id: id,
      kind: kind,
      state: state ?? this.state,
      label: label ?? this.label,
      createdAt: createdAt,
      updatedAt: updatedAt,
      objectKey: objectKey ?? this.objectKey,
      localPath: localPath ?? this.localPath,
      resumeContext: resumeContext,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      multipartUploadId: clearMultipartUploadId
          ? null
          : multipartUploadId ?? this.multipartUploadId,
      completedParts: Map<int, String>.unmodifiable(
        completedParts ?? this.completedParts,
      ),
      uploadCheckpoint: uploadCheckpoint ?? this.uploadCheckpoint,
      metadataPayload: clearMetadataPayload
          ? null
          : metadataPayload ?? this.metadataPayload,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'state': state.name,
    'label': label,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'objectKey': objectKey,
    'localPath': localPath,
    if (resumeContext != null) 'resumeContext': resumeContext,
    'totalBytes': totalBytes,
    'transferredBytes': transferredBytes,
    'multipartUploadId': multipartUploadId,
    if (uploadCheckpoint != null) 'uploadCheckpoint': uploadCheckpoint,
    'completedParts': completedParts.map(
      (key, value) => MapEntry(key.toString(), value),
    ),
    'metadataPayload': metadataPayload,
    'lastError': lastError,
  };

  factory TransferJournalEntry.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
        values.where((value) => value.name == raw?.toString()).firstOrNull ??
        fallback;
    final partPayload = json['completedParts'];
    final completedParts = <int, String>{};
    if (partPayload is Map) {
      for (final entry in partPayload.entries) {
        final partNumber = int.tryParse(entry.key.toString());
        final eTag = entry.value?.toString().trim() ?? '';
        if (partNumber != null && partNumber > 0 && eTag.isNotEmpty) {
          completedParts[partNumber] = eTag;
        }
      }
    }
    final now = DateTime.now().toUtc();
    final state = enumValue(
      TransferJournalState.values,
      json['state'],
      TransferJournalState.interrupted,
    );
    return TransferJournalEntry(
      id: json['id']?.toString() ?? '',
      kind: enumValue(
        TransferJournalKind.values,
        json['kind'],
        TransferJournalKind.upload,
      ),
      state: state,
      label: json['label']?.toString() ?? 'Transfer',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      objectKey: _optionalString(json['objectKey']),
      localPath: _optionalString(json['localPath']),
      resumeContext: _optionalString(json['resumeContext']),
      totalBytes: _nonNegativeIntValue(json['totalBytes']),
      transferredBytes: _nonNegativeIntValue(json['transferredBytes']),
      multipartUploadId: _optionalString(json['multipartUploadId']),
      uploadCheckpoint: _metadataPayload(json['uploadCheckpoint']),
      completedParts: Map<int, String>.unmodifiable(completedParts),
      metadataPayload: _metadataPayload(json['metadataPayload']),
      lastError: _safeStoredError(state, json['lastError']),
    );
  }

  static String? _safeStoredError(TransferJournalState state, Object? value) {
    if (_optionalString(value) == null) return null;
    if (state == TransferJournalState.interrupted &&
        value == transferVerificationMessage) {
      return transferVerificationMessage;
    }
    return switch (state) {
      TransferJournalState.awaitingMetadata =>
        transferJournalMetadataRetryMessage,
      TransferJournalState.cleanupRequired =>
        transferJournalCleanupRetryMessage,
      TransferJournalState.failed ||
      TransferJournalState.interrupted => transferJournalFailureMessage,
      _ => null,
    };
  }

  static String? _optionalString(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static int _nonNegativeIntValue(Object? value) {
    final parsed = value is num
        ? value.round()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  static Map<String, dynamic>? _metadataPayload(Object? value) {
    if (value is! Map) return null;
    try {
      final payload = Map<String, dynamic>.from(value);
      final encoded = jsonEncode(payload);
      if (utf8.encode(encoded).length > 2 * 1024 * 1024) {
        return null;
      }
      final decoded = jsonDecode(encoded);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }
}

class TransferJournal extends ChangeNotifier
    implements MultipartUploadCheckpointSink, ResumableUploadCheckpointSink {
  TransferJournal._({
    required LocalPrivateCachePreferences privateCache,
    required Map<String, TransferJournalEntry> entries,
    required this.storageAvailable,
    required this.recoveredCorruptState,
    required this.migratedLegacyState,
    required this.lastBackupScanAt,
    required this.lastBackupScanSuccessful,
    required this.lastSuccessfulUploadAt,
    required this.lastVerifiedRestoreAt,
    required DateTime Function() clock,
  }) : _privateCache = privateCache,
       _entries = entries,
       _clock = clock;

  static const int _schemaVersion = 2;
  static const int _maxTerminalEntries = 100;
  final LocalPrivateCachePreferences _privateCache;
  final Map<String, TransferJournalEntry> _entries;
  final DateTime Function() _clock;
  final ChangeNotifier lifecycle = ChangeNotifier();
  List<TransferJournalEntry>? _cachedEntries;
  List<TransferJournalEntry>? _cachedPending;
  @override
  void dispose() {
    lifecycle.dispose();
    super.dispose();
  }

  Future<void> _writeChain = Future<void>.value();

  DateTime? lastBackupScanAt;
  bool? lastBackupScanSuccessful;
  DateTime? lastSuccessfulUploadAt;
  DateTime? lastVerifiedRestoreAt;
  final bool storageAvailable;
  final bool recoveredCorruptState;
  final bool migratedLegacyState;

  DateTime _now() => _clock().toUtc();

  List<TransferJournalEntry> get entries =>
      _cachedEntries ??= List.unmodifiable(
        _entries.values.toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      );
  List<TransferJournalEntry> get pendingEntries => _cachedPending ??=
      List.unmodifiable(entries.where((entry) => entry.isPending));
  int? _cachedPendingCount;
  int get pendingCount =>
      _cachedPendingCount ??= _entries.values.where((e) => e.isPending).length;

  static Future<TransferJournal> open({
    required SharedPreferences preferences,
    required String uid,
    String scope = '',
    LocalPrivateCacheCodec? codec,
    DateTime Function()? clock,
  }) async {
    final entries = <String, TransferJournalEntry>{};
    DateTime? lastBackupScanAt;
    bool? lastBackupScanSuccessful;
    DateTime? lastSuccessfulUploadAt;
    DateTime? lastVerifiedRestoreAt;
    final privateCache = LocalPrivateCachePreferences(
      preferences: preferences,
      uid: uid,
      scope: scope,
      codec: codec,
    );
    final cacheRead = await privateCache.read(
      baseKey: LocalPrivateCacheCodec.transferJournalPreferenceKey,
      namespace: LocalPrivateCacheCodec.transferJournalNamespace,
    );
    var recoveredCorruptState = cacheRead.discardedCorruptValue;
    var sanitizedLegacyErrors = false;
    final raw = cacheRead.value;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map ||
            ![1, _schemaVersion].contains(decoded['version'])) {
          throw const FormatException('Unsupported transfer journal schema.');
        }
        final payload = decoded['entries'];
        if (payload is! List) {
          throw const FormatException('Transfer journal entries are invalid.');
        }
        for (final item in payload) {
          if (item is! Map) {
            throw const FormatException('A transfer journal entry is invalid.');
          }
          final entry = TransferJournalEntry.fromJson(
            Map<String, dynamic>.from(item),
          );
          final storedError = item['lastError']?.toString().trim() ?? '';
          if (storedError.isNotEmpty && storedError != entry.lastError) {
            sanitizedLegacyErrors = true;
          }
          if (entry.id.isNotEmpty) entries[entry.id] = entry;
        }
        lastBackupScanAt = DateTime.tryParse(
          decoded['lastBackupScanAt']?.toString() ?? '',
        );
        lastBackupScanSuccessful = decoded['lastBackupScanSuccessful'] is bool
            ? decoded['lastBackupScanSuccessful'] as bool
            : null;
        lastSuccessfulUploadAt = DateTime.tryParse(
          decoded['lastSuccessfulUploadAt']?.toString() ?? '',
        );
        lastVerifiedRestoreAt = DateTime.tryParse(
          decoded['lastVerifiedRestoreAt']?.toString() ?? '',
        );
      } catch (_) {
        entries.clear();
        lastBackupScanAt = null;
        lastBackupScanSuccessful = null;
        lastSuccessfulUploadAt = null;
        lastVerifiedRestoreAt = null;
        recoveredCorruptState = true;
        try {
          await privateCache.write(
            baseKey: LocalPrivateCacheCodec.transferJournalPreferenceKey,
            namespace: LocalPrivateCacheCodec.transferJournalNamespace,
            value: null,
          );
        } catch (_) {
          // The in-memory journal still fails closed. A later startup can
          // retry removing the authenticated but semantically invalid value.
        }
      }
    }
    lastSuccessfulUploadAt ??= entries.values
        .where(
          (entry) =>
              (entry.kind == TransferJournalKind.upload ||
                  entry.kind == TransferJournalKind.backup) &&
              entry.state == TransferJournalState.completed,
        )
        .fold<DateTime?>(
          null,
          (latest, entry) => latest == null || entry.updatedAt.isAfter(latest)
              ? entry.updatedAt
              : latest,
        );

    final journal = TransferJournal._(
      privateCache: privateCache,
      entries: entries,
      storageAvailable: !cacheRead.temporarilyUnavailable,
      recoveredCorruptState: recoveredCorruptState,
      migratedLegacyState: cacheRead.migrated,
      lastBackupScanAt: lastBackupScanAt,
      lastBackupScanSuccessful: lastBackupScanSuccessful,
      lastSuccessfulUploadAt: lastSuccessfulUploadAt,
      lastVerifiedRestoreAt: lastVerifiedRestoreAt,
      clock: clock ?? () => DateTime.now().toUtc(),
    );
    if (journal.storageAvailable) {
      await journal._markInterruptedAfterRestart();
      if (sanitizedLegacyErrors) {
        await journal._persist();
      }
    }
    return journal;
  }

  Future<void> begin({
    required String id,
    required TransferJournalKind kind,
    required String label,
    String? objectKey,
    String? localPath,
    String? resumeContext,
    int totalBytes = 0,
  }) async {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'A transfer id is required.');
    }
    final now = _now();
    _entries[id] = TransferJournalEntry(
      id: id,
      kind: kind,
      state: TransferJournalState.inProgress,
      label: label,
      createdAt: now,
      updatedAt: now,
      objectKey: objectKey,
      localPath: localPath,
      resumeContext: resumeContext,
      totalBytes: totalBytes,
    );
    await _changed();
  }

  Future<void> updateProgress(
    String id, {
    int? transferredBytes,
    String? label,
    TransferJournalState? state,
  }) async {
    final existing = _entries[id];
    if (existing == null) return;
    final int normalized = transferredBytes == null
        ? existing.transferredBytes
        : existing.totalBytes > 0
        ? transferredBytes.clamp(0, existing.totalBytes).toInt()
        : transferredBytes < 0
        ? 0
        : transferredBytes;
    if (normalized == existing.transferredBytes &&
        (label == null || label == existing.label) &&
        (state == null || state == existing.state)) {
      return;
    }
    _entries[id] = existing.copyWith(
      updatedAt: _now(),
      label: label,
      state: state,
      transferredBytes: normalized,
    );
    await _changed(
      lifecycleChanged:
          (state != null && state != existing.state) ||
          (label != null && label != existing.label),
    );
  }

  Future<void> complete(String id) =>
      _finish(id, state: TransferJournalState.completed, clearMultipart: true);

  Future<void> fail(String id, Object error) async {
    if (requiresTransferVerification(error)) {
      final entry = _entries[id];
      if (entry == null) return;
      _entries[id] = entry.copyWith(
        updatedAt: _now(),
        state: TransferJournalState.interrupted,
        lastError: transferVerificationMessage,
      );
      await _changed();
      return;
    }
    await _finish(
      id,
      state: _entries[id]?.uploadCheckpoint == null
          ? TransferJournalState.failed
          : TransferJournalState.interrupted,
      error: error,
    );
  }

  Future<void> metadataCommitFailed(String id, Object error) async {
    final existing = _entries[id];
    if (existing == null) return;
    _entries[id] = existing.copyWith(
      updatedAt: _now(),
      state: TransferJournalState.awaitingMetadata,
      lastError: transferJournalMetadataRetryMessage,
    );
    await _changed();
  }

  Future<void> stageMetadataCommit(
    String id, {
    required Map<String, dynamic> payload,
  }) async {
    final existing = _entries[id];
    if (existing == null) return;
    final normalizedPayload = TransferJournalEntry._metadataPayload(payload);
    if (normalizedPayload == null) {
      throw const FormatException(
        'Upload metadata recovery payload is invalid or too large.',
      );
    }
    final payloadObjectKey = normalizedPayload['objectKey']?.toString().trim();
    if (payloadObjectKey == null ||
        payloadObjectKey.isEmpty ||
        payloadObjectKey != existing.objectKey) {
      throw const FormatException(
        'Upload metadata recovery does not match its encrypted object.',
      );
    }
    _entries[id] = existing.copyWith(
      updatedAt: _now(),
      state: TransferJournalState.awaitingMetadata,
      transferredBytes: existing.totalBytes,
      metadataPayload: normalizedPayload,
      clearLastError: true,
    );
    await _changed();
  }

  Future<void> cancel(String id) =>
      _finish(id, state: TransferJournalState.canceled);

  Future<void> markBackupScan({required bool successful}) async {
    lastBackupScanAt = _now();
    lastBackupScanSuccessful = successful;
    await _changed();
  }

  Future<void> markRestoreVerified() async {
    lastVerifiedRestoreAt = _now();
    await _changed();
  }

  @override
  Future<void> multipartCreated({
    required String transferId,
    required String objectKey,
    required String uploadId,
  }) async {
    final existing = _entries[transferId];
    if (existing == null) return;
    _entries[transferId] = existing.copyWith(
      updatedAt: _now(),
      objectKey: objectKey,
      multipartUploadId: uploadId,
      state: TransferJournalState.inProgress,
    );
    await _changed();
  }

  @override
  Future<void> multipartPartCompleted({
    required String transferId,
    required int partNumber,
    required String eTag,
    required int uploadedBytes,
  }) async {
    final existing = _entries[transferId];
    if (existing == null) return;
    final alreadyRecorded = existing.completedParts.containsKey(partNumber);
    final parts = Map<int, String>.from(existing.completedParts)
      ..[partNumber] = eTag;
    _entries[transferId] = existing.copyWith(
      updatedAt: _now(),
      completedParts: parts,
      transferredBytes: alreadyRecorded
          ? existing.transferredBytes
          : existing.transferredBytes + uploadedBytes,
    );
    await _changed(lifecycleChanged: false);
  }

  @override
  Future<void> multipartCompleted({required String transferId}) async {
    final existing = _entries[transferId];
    if (existing == null) return;
    _entries[transferId] = existing.copyWith(
      updatedAt: _now(),
      state: TransferJournalState.awaitingMetadata,
      clearMultipartUploadId: true,
    );
    await _changed();
  }

  @override
  Future<void> multipartAborted({required String transferId}) async {
    final existing = _entries[transferId];
    if (existing == null) return;
    _entries[transferId] = existing.copyWith(
      updatedAt: _now(),
      state: TransferJournalState.failed,
      clearMultipartUploadId: true,
    );
    await _changed();
  }

  @override
  Future<void> multipartCleanupRequired({
    required String transferId,
    required Object error,
  }) async {
    final existing = _entries[transferId];
    if (existing == null) return;
    _entries[transferId] = existing.copyWith(
      updatedAt: _now(),
      state: TransferJournalState.cleanupRequired,
      lastError: transferJournalCleanupRetryMessage,
    );
    await _changed();
  }

  Future<void> cleanupCompleted(String id) async {
    final existing = _entries[id];
    if (existing == null) return;
    _entries[id] = existing.copyWith(
      updatedAt: _now(),
      state: TransferJournalState.cleanedUp,
      clearMultipartUploadId: true,
      clearMetadataPayload: true,
      clearLastError: true,
    );
    await _changed();
  }

  Future<void> _finish(
    String id, {
    required TransferJournalState state,
    Object? error,
    bool clearMultipart = false,
  }) async {
    final existing = _entries[id];
    if (existing == null) return;
    final updatedAt = _now();
    if (state == TransferJournalState.completed &&
        (existing.kind == TransferJournalKind.upload ||
            existing.kind == TransferJournalKind.backup)) {
      lastSuccessfulUploadAt = updatedAt;
    }
    _entries[id] = existing.copyWith(
      updatedAt: updatedAt,
      state: state,
      transferredBytes: state == TransferJournalState.completed
          ? existing.totalBytes
          : null,
      lastError: error == null ? null : transferJournalFailureMessage,
      clearMultipartUploadId: clearMultipart,
      clearMetadataPayload: true,
      clearLastError: error == null,
    );
    await _changed();
  }

  Future<void> _markInterruptedAfterRestart() async {
    var changed = false;
    for (final item in _entries.entries.toList(growable: false)) {
      final entry = item.value;
      if (entry.state != TransferJournalState.inProgress &&
          entry.state != TransferJournalState.queued) {
        continue;
      }
      _entries[item.key] = entry.copyWith(
        updatedAt: _now(),
        state: entry.multipartUploadId == null || entry.uploadCheckpoint != null
            ? TransferJournalState.interrupted
            : TransferJournalState.cleanupRequired,
        lastError: transferJournalFailureMessage,
      );
      changed = true;
    }
    if (changed) await _changed();
  }

  @override
  Map<String, dynamic>? uploadCheckpoint(String transferId) =>
      _entries[transferId]?.uploadCheckpoint;

  @override
  Future<void> saveUploadCheckpoint(
    String transferId,
    Map<String, dynamic> checkpoint,
  ) async {
    final entry = _entries[transferId];
    if (entry == null) return;
    const allowed = {
      'version',
      'sessionId',
      'batchId',
      'nonce',
      'sourceFingerprint',
      'partBytes',
      'parts',
      'eTags',
      'retryCount',
      'objectKey',
      'encryptedBytes',
      'secureSharded',
      'shards',
    };
    if (checkpoint.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Unsupported upload checkpoint');
    }
    _entries[transferId] = entry.copyWith(
      updatedAt: _now(),
      uploadCheckpoint: Map<String, dynamic>.from(checkpoint),
    );
    await _changed(lifecycleChanged: false);
  }

  Future<void> _changed({bool lifecycleChanged = true}) async {
    _cachedEntries = null;
    _cachedPending = null;
    _prune();
    if (lifecycleChanged) _cachedPendingCount = null;
    notifyListeners();
    if (lifecycleChanged) lifecycle.notifyListeners();
    final previousWrite = _writeChain;
    final nextWrite = () async {
      try {
        await previousWrite;
      } catch (_) {
        // A transient preferences failure must not poison all later writes.
      }
      await _persist();
    }();
    _writeChain = nextWrite;
    await nextWrite;
  }

  void _prune() {
    final terminalEntries = entries
        .where((entry) => !entry.isPending)
        .toList(growable: false);
    for (final entry in terminalEntries.skip(_maxTerminalEntries)) {
      _entries.remove(entry.id);
      _cachedEntries = null;
      _cachedPending = null;
    }
  }

  Future<void> _persist() async {
    if (!storageAvailable) {
      throw const LocalPrivateCacheException(
        LocalPrivateCacheFailure.keyUnavailable,
        'The transfer journal is securely locked.',
      );
    }
    await _privateCache.write(
      baseKey: LocalPrivateCacheCodec.transferJournalPreferenceKey,
      namespace: LocalPrivateCacheCodec.transferJournalNamespace,
      value: jsonEncode(<String, Object?>{
        'version': _schemaVersion,
        'entries': entries.map((entry) => entry.toJson()).toList(),
        'lastBackupScanAt': lastBackupScanAt?.toIso8601String(),
        'lastBackupScanSuccessful': lastBackupScanSuccessful,
        'lastSuccessfulUploadAt': lastSuccessfulUploadAt?.toIso8601String(),
        'lastVerifiedRestoreAt': lastVerifiedRestoreAt?.toIso8601String(),
      }),
    );
  }
}
