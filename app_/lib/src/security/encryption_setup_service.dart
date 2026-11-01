import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../shared/release_runtime_config.dart';
import '../shared/user_facing_cloud_error.dart';

const Map<String, Object?> standardEncryptionSetupRequestPayload =
    <String, Object?>{};

class EncryptionSetupException implements Exception {
  const EncryptionSetupException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'EncryptionSetupException: $message';
}

class EncryptionSetupService {
  EncryptionSetupService({
    required FirebaseFunctions functions,
    FirebaseAuth? auth,
    http.Client? httpClient,
    Uri? ensureStandardEncryptionSaltRestUri,
    bool? preferRest,
  }) : _functions = functions,
       _auth = auth,
       _httpClient = httpClient ?? http.Client(),
       _ensureStandardEncryptionSaltRestUri =
           ensureStandardEncryptionSaltRestUri,
       _preferRest =
           preferRest ??
           (kIsWeb ||
               defaultTargetPlatform == TargetPlatform.windows ||
               defaultTargetPlatform == TargetPlatform.linux);

  factory EncryptionSetupService.forApp(FirebaseApp app) {
    return EncryptionSetupService(
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
  final Uri? _ensureStandardEncryptionSaltRestUri;
  final bool _preferRest;

  Future<Uint8List> ensureStandardEncryptionSalt() async {
    try {
      if (_preferRest) {
        return _ensureStandardEncryptionSaltViaRest(
          standardEncryptionSetupRequestPayload,
        );
      }
      final result = await _functions
          .httpsCallable('ensureStandardEncryptionSalt')
          .call<Map<String, dynamic>>(standardEncryptionSetupRequestPayload)
          .timeout(const Duration(seconds: 20));
      final data = result.data;
      final saltBase64 = data['saltBase64'];
      if (saltBase64 is! String || saltBase64.trim().isEmpty) {
        throw const EncryptionSetupException(
          'The encryption setup response did not include a salt.',
        );
      }
      return Uint8List.fromList(base64Decode(saltBase64));
    } on EncryptionSetupException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw EncryptionSetupException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.encryptionSetup,
          code: error.code,
        ),
        cause: error,
      );
    } catch (error) {
      throw EncryptionSetupException(
        'Unable to set up encryption for this account.',
        cause: error,
      );
    }
  }

  Future<Uint8List> _ensureStandardEncryptionSaltViaRest(
    Map<String, Object?> payload,
  ) async {
    final auth = _auth;
    final user = auth?.currentUser;
    if (auth == null || user == null) {
      throw const EncryptionSetupException(
        'You must be signed in before encryption setup can continue.',
      );
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const EncryptionSetupException(
        'Unable to retrieve an authenticated session for encryption setup.',
      );
    }

    final response = await _httpClient
        .post(
          _ensureStandardEncryptionSaltRestUri ??
              _callableUri(auth, 'ensureStandardEncryptionSalt'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(<String, dynamic>{'data': payload}),
        )
        .timeout(const Duration(seconds: 20));

    final decoded = _decodeJsonMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EncryptionSetupException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.encryptionSetup,
          code: _callableErrorCode(decoded),
          httpStatus: response.statusCode,
        ),
      );
    }

    final error = decoded?['error'];
    if (error is Map<String, dynamic>) {
      throw EncryptionSetupException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.encryptionSetup,
          code: _callableErrorCode(decoded),
        ),
      );
    }

    final result = decoded?['result'];
    final data = result is Map<String, dynamic> ? result : decoded;
    final saltBase64 = data?['saltBase64'];
    if (saltBase64 is! String || saltBase64.trim().isEmpty) {
      throw const EncryptionSetupException(
        'The encryption setup response did not include a salt.',
      );
    }
    return Uint8List.fromList(base64Decode(saltBase64));
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
