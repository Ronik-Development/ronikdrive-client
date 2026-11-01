import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../shared/release_runtime_config.dart';
import '../shared/user_facing_cloud_error.dart';

class WasabiProvisioningException implements Exception {
  const WasabiProvisioningException(this.message);

  final String message;

  @override
  String toString() => 'WasabiProvisioningException: $message';
}

class WasabiProvisioningService {
  WasabiProvisioningService({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    http.Client? httpClient,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _functions = functions,
       _httpClient = httpClient ?? http.Client();

  factory WasabiProvisioningService.forApp(FirebaseApp app) {
    final preferRest =
        kIsWeb ||
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    return WasabiProvisioningService(
      auth: FirebaseAuth.instanceFor(app: app),
      functions: preferRest
          ? null
          : FirebaseFunctions.instanceFor(app: app, region: 'europe-west1'),
    );
  }

  final FirebaseAuth _auth;
  final FirebaseFunctions? _functions;
  final http.Client _httpClient;

  void _log(String message) {
    if (!kDebugMode) {
      return;
    }
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[RonikCloud][wasabi][$timestamp] $message');
  }

  Future<Map<String, dynamic>> ensureProvisioned({User? user}) async {
    _log('Starting protected storage provisioning.');
    final response = _shouldPreferRestOnThisPlatform
        ? await _callViaRest(user)
        : await _callViaPluginOrRest(user);

    if (response is Map) {
      _log('Secure-storage provisioning returned a response.');
      return Map<String, dynamic>.from(
        response.map((key, value) => MapEntry(key.toString(), value)),
      );
    }

    throw const WasabiProvisioningException(
      'Secure-storage setup returned an invalid response. Retry shortly.',
    );
  }

  Future<void> ensureBrowserUploadCors() async {
    _log(
      'Wasabi browser upload CORS is deployment/admin-owned; skipping '
      'client-side bucket CORS mutation.',
    );
  }

  bool get _shouldPreferRestOnThisPlatform {
    if (kIsWeb) {
      return true;
    }
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  Future<dynamic> _callViaPluginOrRest(User? user) async {
    try {
      _log('Calling ensureWasabiProvisioned through Firebase Functions.');
      final functions =
          _functions ??
          FirebaseFunctions.instanceFor(app: _auth.app, region: 'europe-west1');
      final result = await functions
          .httpsCallable('ensureWasabiProvisioned')
          .call(const <String, dynamic>{
            'supportsServerManagedCompanyStorage': true,
            'supportsServerManagedPersonalStorage': true,
          });
      _log('Firebase Functions returned a Wasabi provisioning response.');
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      if ({
        'failed-precondition',
        'permission-denied',
        'unauthenticated',
        'invalid-argument',
      }.contains(error.code)) {
        throw WasabiProvisioningException(
          userFacingCloudErrorMessage(
            operation: UserFacingCloudOperation.storageProvisioning,
            code: error.code,
          ),
        );
      }
      _log('Callable setup failed; trying authenticated HTTPS.');
      return _callViaRest(user);
    } catch (_) {
      _log(
        'Callable provisioning path threw unexpectedly; falling back to HTTPS.',
      );
      return _callViaRest(user);
    }
  }

  Future<dynamic> _callViaRest(User? user) async {
    final signedInUser = user ?? _auth.currentUser;
    if (signedInUser == null) {
      throw WasabiProvisioningException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.storageProvisioning,
          code: 'unauthenticated',
        ),
      );
    }

    final token = await signedInUser.getIdToken();
    if (token == null || token.isEmpty) {
      throw WasabiProvisioningException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.storageProvisioning,
          code: 'unauthenticated',
        ),
      );
    }

    var projectId = ReleaseRuntimeConfig.defaultWebProjectId;
    try {
      final configuredProjectId = _auth.app.options.projectId.trim();
      if (configuredProjectId.isNotEmpty) {
        projectId = configuredProjectId;
      }
    } catch (_) {
      // Test and embedded auth adapters may not expose FirebaseOptions.
    }
    final endpoint = ReleaseRuntimeConfig.resolveCallableRestUri(
      projectId: projectId,
      functionName: 'ensureWasabiProvisioned',
    );
    _log('Posting authenticated secure-storage setup request.');

    http.Response response;
    try {
      response = await _httpClient.post(
        endpoint,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(const <String, dynamic>{
          'data': <String, dynamic>{
            'supportsServerManagedCompanyStorage': true,
            'supportsServerManagedPersonalStorage': true,
          },
        }),
      );
    } on Exception {
      throw WasabiProvisioningException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.storageProvisioning,
          code: 'unavailable',
        ),
      );
    }

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _log('Protected storage provisioning was unavailable.');
      throw WasabiProvisioningException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.storageProvisioning,
          code: _callableErrorCode(decoded),
          httpStatus: response.statusCode,
        ),
      );
    }

    _log('Authenticated secure-storage setup request completed.');
    if (decoded is Map<String, dynamic> && decoded['error'] is Map) {
      throw WasabiProvisioningException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.storageProvisioning,
          code: _callableErrorCode(decoded),
        ),
      );
    }
    if (decoded is Map<String, dynamic> && decoded.containsKey('result')) {
      return decoded['result'];
    }

    return decoded;
  }

  String? _callableErrorCode(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        final status = error['status'];
        if (status is String && status.trim().isNotEmpty) {
          return status.trim();
        }
      }
    }
    return null;
  }
}
