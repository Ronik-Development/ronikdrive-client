import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../shared/release_runtime_config.dart';
import '../shared/user_facing_cloud_error.dart';
import 'upload_coordinator.dart';

class UploadMetadataException implements Exception {
  const UploadMetadataException(this.message);

  final String message;

  @override
  String toString() => 'UploadMetadataException: $message';
}

class UploadMetadataPayloadEncoder {
  const UploadMetadataPayloadEncoder({required this.encodeLargeIntsAsStrings});

  static const int maxPayloadBytes = 2 * 1024 * 1024;
  static const Set<String> _allowedPayloadKeys = <String>{
    'objectKey',
    'size',
    'folderId',
    'encryptionMode',
    'storageLayout',
    'shardCount',
    'shardSizeBytes',
    'shardScheme',
    'contentEncryption',
    'secureContentEncoding',
    'secureRefreshedAt',
    'secureRefreshDueAt',
    'uploadedAt',
    'contentIntegrityTag',
    'contentIntegrityVersion',
    'encryptedName',
    'backupPathHash',
    'backupModifiedMillis',
    // Legacy encrypted journals may contain this provider-classifying flag.
    // It is accepted only so the replay can remove it before transmission.
    'hasThumbnail',
    'storageScope',
    'companyId',
    'ownerUid',
    'groupIds',
    'allowedUids',
    'sharedKeyEnvelopes',
    'supersedesFileId',
    'nativeExpectedVersion',
  };

  factory UploadMetadataPayloadEncoder.forCurrentPlatform() {
    return UploadMetadataPayloadEncoder(encodeLargeIntsAsStrings: kIsWeb);
  }

  final bool encodeLargeIntsAsStrings;

  Object callableNumber(int value) {
    // Flutter web's message codecs can throw when an int is encoded as int64.
    // The callable backend normalizes these with Number(...), so strings keep
    // large file sizes/timestamps safe without changing stored metadata.
    return encodeLargeIntsAsStrings ? value.toString() : value;
  }

  Map<String, dynamic> normalizeRecordUploadedFilePayload(
    Map<String, dynamic> input,
  ) {
    // Older authenticated local journals may contain readable folder hints.
    // Remove them on-device so recovery can finish without sending those
    // labels to the service. The server independently rejects these fields.
    final protectedInput = Map<String, dynamic>.from(input)
      ..remove('folderName')
      ..remove('folderColor')
      ..remove('pathSegments')
      ..remove('hasThumbnail');
    final unexpectedKeys = protectedInput.keys
        .where((key) => !_allowedPayloadKeys.contains(key))
        .toList(growable: false);
    if (unexpectedKeys.isNotEmpty) {
      throw const UploadMetadataException(
        'Saved upload metadata contains unsupported fields.',
      );
    }
    final objectKey = protectedInput['objectKey'];
    final size = protectedInput['size'];
    final encryptionMode = protectedInput['encryptionMode'];
    final storageLayout = protectedInput['storageLayout'];
    final contentEncryption = protectedInput['contentEncryption'];
    final uploadedAt = protectedInput['uploadedAt'];
    if (protectedInput.containsKey('nativeExpectedVersion')) {
      final version = protectedInput['nativeExpectedVersion'];
      final predecessor = protectedInput['supersedesFileId'];
      final validVersion = predecessor == null
          ? version == 'create'
          : version is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(version);
      if (!validVersion ||
          encryptionMode != 'standard' ||
          storageLayout != 'single' ||
          contentEncryption != 'standard' ||
          protectedInput['storageScope'] != 'personal') {
        throw const UploadMetadataException(
          'Saved native upload metadata has an invalid version precondition.',
        );
      }
    }
    if (objectKey is! String ||
        objectKey.trim().isEmpty ||
        objectKey.length > 2048 ||
        (size is! num && size is! String) ||
        int.tryParse(size.toString()) == null ||
        int.parse(size.toString()) < 0 ||
        !const <String>{'standard', 'secured'}.contains(encryptionMode) ||
        !const <String>{'single', 'sharded'}.contains(storageLayout) ||
        !const <String>{'standard', 'secure'}.contains(contentEncryption) ||
        uploadedAt is! String ||
        DateTime.tryParse(uploadedAt) == null) {
      throw const UploadMetadataException(
        'Saved upload metadata is incomplete or invalid.',
      );
    }
    try {
      final encoded = jsonEncode(protectedInput);
      if (utf8.encode(encoded).length > maxPayloadBytes) {
        throw const UploadMetadataException(
          'Saved upload metadata is too large to retry safely.',
        );
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        throw const UploadMetadataException(
          'Saved upload metadata is invalid.',
        );
      }
      return decoded;
    } on UploadMetadataException {
      rethrow;
    } on Object {
      throw const UploadMetadataException(
        'Saved upload metadata is not serializable.',
      );
    }
  }

  Map<String, dynamic> buildRecordUploadedFilePayload({
    required String objectKey,
    required int size,
    String? folderId,
    required String encryptionMode,
    String storageLayout = 'single',
    int? shardCount,
    int? shardSizeBytes,
    String? shardScheme,
    required String contentEncryption,
    String? secureContentEncoding,
    DateTime? secureRefreshedAt,
    DateTime? secureRefreshDueAt,
    DateTime? uploadedAt,
    String? contentIntegrityTag,
    String? contentIntegrityVersion,
    String? encryptedName,
    String? backupPathHash,
    int? backupModifiedMillis,
    String storageScope = 'personal',
    String? companyId,
    String? ownerUid,
    List<String>? groupIds,
    List<String>? allowedUids,
    Map<String, Object?>? sharedKeyEnvelopes,
    String? supersedesFileId,
  }) {
    final payload = <String, dynamic>{
      'objectKey': objectKey,
      'size': callableNumber(size),
      'encryptionMode': encryptionMode,
      'storageLayout': storageLayout,
      'uploadedAt': (uploadedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };

    void addString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        payload[key] = trimmed;
      }
    }

    void addInt(String key, int? value) {
      if (value != null) {
        payload[key] = callableNumber(value);
      }
    }

    addString('folderId', folderId);
    if (encryptionMode.trim().toLowerCase() == 'standard') {
      addString('contentIntegrityTag', contentIntegrityTag);
      addString('contentIntegrityVersion', contentIntegrityVersion);
    }
    addString('encryptedName', encryptedName);
    addString('shardScheme', shardScheme);
    addString('contentEncryption', contentEncryption);
    addString('secureContentEncoding', secureContentEncoding);
    addString('backupPathHash', backupPathHash);
    addString('storageScope', storageScope);
    addString('companyId', companyId);
    addString('ownerUid', ownerUid);
    addString('supersedesFileId', supersedesFileId);
    addInt('shardCount', shardCount);
    addInt('shardSizeBytes', shardSizeBytes);
    addInt('backupModifiedMillis', backupModifiedMillis);
    if (groupIds != null && groupIds.isNotEmpty) {
      payload['groupIds'] = groupIds
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    if (allowedUids != null && allowedUids.isNotEmpty) {
      payload['allowedUids'] = allowedUids
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    if (sharedKeyEnvelopes != null && sharedKeyEnvelopes.isNotEmpty) {
      payload['sharedKeyEnvelopes'] = sharedKeyEnvelopes;
    }
    if (secureRefreshedAt != null) {
      payload['secureRefreshedAt'] = secureRefreshedAt
          .toUtc()
          .toIso8601String();
    }
    if (secureRefreshDueAt != null) {
      payload['secureRefreshDueAt'] = secureRefreshDueAt
          .toUtc()
          .toIso8601String();
    }

    return normalizeRecordUploadedFilePayload(payload);
  }
}

class UploadMetadataService {
  UploadMetadataService({
    required FirebaseFunctions functions,
    FirebaseAuth? auth,
    http.Client? httpClient,
    Uri? recordUploadedFileRestUri,
    UploadMetadataPayloadEncoder? encoder,
    bool? preferRest,
  }) : _functions = functions,
       _auth = auth,
       _httpClient = httpClient ?? http.Client(),
       _recordUploadedFileRestUri = recordUploadedFileRestUri,
       _preferRest = preferRest ?? kIsWeb,
       _encoder = encoder ?? UploadMetadataPayloadEncoder.forCurrentPlatform();

  factory UploadMetadataService.forApp(FirebaseApp app) {
    return UploadMetadataService(
      functions: FirebaseFunctions.instanceFor(
        app: app,
        region: 'europe-west1',
      ),
      auth: FirebaseAuth.instanceFor(app: app),
    );
  }

  final FirebaseFunctions _functions;
  final FirebaseAuth? _auth;
  final http.Client _httpClient;
  final Uri? _recordUploadedFileRestUri;
  final bool _preferRest;
  final UploadMetadataPayloadEncoder _encoder;

  Map<String, dynamic> buildRecordUploadedFilePayload({
    required String objectKey,
    required int size,
    String? folderId,
    required String encryptionMode,
    String storageLayout = 'single',
    int? shardCount,
    int? shardSizeBytes,
    String? shardScheme,
    required String contentEncryption,
    String? secureContentEncoding,
    DateTime? secureRefreshedAt,
    DateTime? secureRefreshDueAt,
    DateTime? uploadedAt,
    String? contentIntegrityTag,
    String? contentIntegrityVersion,
    String? encryptedName,
    String? backupPathHash,
    int? backupModifiedMillis,
    String storageScope = 'personal',
    String? companyId,
    String? ownerUid,
    List<String>? groupIds,
    List<String>? allowedUids,
    Map<String, Object?>? sharedKeyEnvelopes,
    String? supersedesFileId,
  }) {
    return _encoder.buildRecordUploadedFilePayload(
      objectKey: objectKey,
      size: size,
      folderId: folderId,
      encryptionMode: encryptionMode,
      storageLayout: storageLayout,
      shardCount: shardCount,
      shardSizeBytes: shardSizeBytes,
      shardScheme: shardScheme,
      contentEncryption: contentEncryption,
      secureContentEncoding: secureContentEncoding,
      secureRefreshedAt: secureRefreshedAt,
      secureRefreshDueAt: secureRefreshDueAt,
      uploadedAt: uploadedAt,
      contentIntegrityTag: contentIntegrityTag,
      contentIntegrityVersion: contentIntegrityVersion,
      encryptedName: encryptedName,
      backupPathHash: backupPathHash,
      backupModifiedMillis: backupModifiedMillis,
      storageScope: storageScope,
      companyId: companyId,
      ownerUid: ownerUid,
      groupIds: groupIds,
      allowedUids: allowedUids,
      sharedKeyEnvelopes: sharedKeyEnvelopes,
      supersedesFileId: supersedesFileId,
    );
  }

  Future<void> recordUploadedFile({
    required String objectKey,
    required int size,
    String? folderId,
    required String encryptionMode,
    String storageLayout = 'single',
    int? shardCount,
    int? shardSizeBytes,
    String? shardScheme,
    required String contentEncryption,
    String? secureContentEncoding,
    DateTime? secureRefreshedAt,
    DateTime? secureRefreshDueAt,
    DateTime? uploadedAt,
    String? contentIntegrityTag,
    String? contentIntegrityVersion,
    String? encryptedName,
    String? backupPathHash,
    int? backupModifiedMillis,
    String storageScope = 'personal',
    String? companyId,
    String? ownerUid,
    List<String>? groupIds,
    List<String>? allowedUids,
    Map<String, Object?>? sharedKeyEnvelopes,
    String? supersedesFileId,
  }) async {
    final payload = buildRecordUploadedFilePayload(
      objectKey: objectKey,
      size: size,
      folderId: folderId,
      encryptionMode: encryptionMode,
      storageLayout: storageLayout,
      shardCount: shardCount,
      shardSizeBytes: shardSizeBytes,
      shardScheme: shardScheme,
      contentEncryption: contentEncryption,
      secureContentEncoding: secureContentEncoding,
      secureRefreshedAt: secureRefreshedAt,
      secureRefreshDueAt: secureRefreshDueAt,
      uploadedAt: uploadedAt,
      contentIntegrityTag: contentIntegrityTag,
      contentIntegrityVersion: contentIntegrityVersion,
      encryptedName: encryptedName,
      backupPathHash: backupPathHash,
      backupModifiedMillis: backupModifiedMillis,
      storageScope: storageScope,
      companyId: companyId,
      ownerUid: ownerUid,
      groupIds: groupIds,
      allowedUids: allowedUids,
      sharedKeyEnvelopes: sharedKeyEnvelopes,
      supersedesFileId: supersedesFileId,
    );

    await recordUploadedFilePayload(payload);
  }

  Future<void> recordUploadedFilePayload(Map<String, dynamic> input) async {
    final payload = _encoder.normalizeRecordUploadedFilePayload(input);

    try {
      if (payload.containsKey('nativeExpectedVersion')) {
        await _recordUploadedFileViaRest(
          payload,
          functionName: 'recordDesktopDriveFile',
        );
        UploadCoordinator.instance.metadataCompleted(payload['objectKey'] as String);
        return;
      }
      if (_preferRest) {
        await _recordUploadedFileViaRest(payload);
        UploadCoordinator.instance.metadataCompleted(payload['objectKey'] as String);
        return;
      }
      await _functions
          .httpsCallable('recordUploadedFile')
          .call<void>(payload)
          .timeout(const Duration(seconds: 20));
      UploadCoordinator.instance.metadataCompleted(payload['objectKey'] as String);
    } on UploadMetadataException {
      UploadCoordinator.instance.metadataDeferred(payload['objectKey'] as String);
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      UploadCoordinator.instance.metadataDeferred(payload['objectKey'] as String);
      throw UploadMetadataException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.uploadMetadata,
          code: error.code,
        ),
      );
    } on Exception {
      UploadCoordinator.instance.metadataDeferred(payload['objectKey'] as String);
      throw UploadMetadataException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.uploadMetadata,
        ),
      );
    }
  }

  Future<void> _recordUploadedFileViaRest(
    Map<String, dynamic> payload, {
    String functionName = 'recordUploadedFile',
  }) async {
    final auth = _auth;
    final user = auth?.currentUser;
    if (auth == null || user == null) {
      throw const UploadMetadataException(
        'You must be signed in before file metadata can be saved.',
      );
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const UploadMetadataException(
        'Unable to retrieve an authenticated session for file metadata.',
      );
    }

    final response = await _httpClient
        .post(
          _recordUploadedFileRestUri ?? _callableUri(auth, functionName),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(<String, dynamic>{'data': payload}),
        )
        .timeout(const Duration(seconds: 20));

    final decoded = _decodeJsonMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UploadMetadataException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.uploadMetadata,
          code: _callableErrorCode(decoded),
          httpStatus: response.statusCode,
        ),
      );
    }

    final error = decoded?['error'];
    if (error is Map<String, dynamic>) {
      throw UploadMetadataException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.uploadMetadata,
          code: _callableErrorCode(decoded),
          httpStatus: response.statusCode,
        ),
      );
    }
  }

  Uri _callableUri(FirebaseAuth auth, String functionName) {
    final configuredProjectId = auth.app.options.projectId.trim();
    final projectId = configuredProjectId.isEmpty
        ? ReleaseRuntimeConfig.defaultWebProjectId
        : configuredProjectId;
    return ReleaseRuntimeConfig.resolveCallableRestUri(
      projectId: projectId,
      functionName: functionName,
    );
  }

  Map<String, dynamic>? _decodeJsonMap(String body) {
    if (body.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  String? _callableErrorCode(Map<String, dynamic>? decoded) {
    final error = decoded?['error'];
    if (error is Map<String, dynamic>) {
      final status = error['status'];
      if (status is String && status.trim().isNotEmpty) {
        return status.trim();
      }
    }
    return null;
  }
}
