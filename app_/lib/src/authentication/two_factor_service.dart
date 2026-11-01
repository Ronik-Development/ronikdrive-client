import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../shared/release_runtime_config.dart';
import '../shared/user_facing_cloud_error.dart';

class TwoFactorStatus {
  const TwoFactorStatus({
    required this.enabled,
    required this.verified,
    this.verifiedUntil,
  });

  factory TwoFactorStatus.fromData(dynamic data) {
    if (data is Map) {
      final rawEnabled = data['enabled'];
      final rawVerified = data['verified'];
      final rawVerifiedUntil = data['verifiedUntil'];
      return TwoFactorStatus(
        enabled: rawEnabled == true,
        verified: rawEnabled == true ? rawVerified == true : true,
        verifiedUntil: rawVerifiedUntil is String
            ? DateTime.tryParse(rawVerifiedUntil)
            : null,
      );
    }
    return const TwoFactorStatus(enabled: false, verified: true);
  }

  final bool enabled;
  final bool verified;
  final DateTime? verifiedUntil;
}

abstract class TwoFactorApi {
  Future<TwoFactorStatus> fetchStatus();

  Future<TwoFactorStatus> verifyCode(String code);

  Future<void> enable({required String secret, required String code});

  Future<void> disable();
}

class FirebaseTwoFactorApi implements TwoFactorApi {
  FirebaseTwoFactorApi({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    http.Client? httpClient,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
       _auth = auth ?? FirebaseAuth.instance,
       _httpClient = httpClient ?? http.Client();

  factory FirebaseTwoFactorApi.forApp(FirebaseApp app) {
    return FirebaseTwoFactorApi(
      functions: FirebaseFunctions.instanceFor(
        app: app,
        region: 'europe-west1',
      ),
      auth: FirebaseAuth.instanceFor(app: app),
    );
  }

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final http.Client _httpClient;

  HttpsCallable _callable(String name) => _functions.httpsCallable(name);

  Future<dynamic> _call(
    String name, [
    Map<String, dynamic> data = const {},
  ]) async {
    try {
      final result = await _callable(name).call(data);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw TwoFactorException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.twoFactor,
          code: error.code,
        ),
      );
    } catch (_) {
      return _callViaRest(name, data);
    }
  }

  Future<dynamic> _callViaRest(String name, Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const TwoFactorException(
        'You must be signed in to complete the security check.',
      );
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const TwoFactorException(
        'Unable to retrieve an authenticated session for the security check.',
      );
    }

    final projectId = _auth.app.options.projectId.trim().isEmpty
        ? ReleaseRuntimeConfig.defaultWebProjectId
        : _auth.app.options.projectId.trim();
    final endpoint = ReleaseRuntimeConfig.resolveCallableRestUri(
      projectId: projectId,
      functionName: name,
    );

    http.Response response;
    try {
      response = await _httpClient.post(
        endpoint,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, dynamic>{'data': data}),
      );
    } on Exception {
      throw const TwoFactorException(
        'Unable to reach the security verification service.',
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
      throw TwoFactorException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.twoFactor,
          code: _callableErrorCode(decoded),
          httpStatus: response.statusCode,
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

  @override
  Future<TwoFactorStatus> fetchStatus() async {
    try {
      final result = await _call('getTwoFactorStatus');
      return TwoFactorStatus.fromData(result);
    } on TwoFactorException {
      rethrow;
    } catch (_) {
      throw TwoFactorException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.twoFactor,
        ),
      );
    }
  }

  @override
  Future<TwoFactorStatus> verifyCode(String code) async {
    try {
      final result = await _call('verifyTwoFactorCode', <String, dynamic>{
        'code': code.trim(),
      });
      return TwoFactorStatus.fromData(result);
    } on TwoFactorException {
      rethrow;
    } catch (_) {
      throw TwoFactorException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.twoFactor,
        ),
      );
    }
  }

  @override
  Future<void> enable({required String secret, required String code}) async {
    try {
      await _call('enableTwoFactor', <String, dynamic>{
        'secret': secret.trim(),
        'code': code.trim(),
      });
    } on TwoFactorException {
      rethrow;
    } catch (_) {
      throw TwoFactorException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.twoFactor,
        ),
      );
    }
  }

  @override
  Future<void> disable() async {
    try {
      await _call('disableTwoFactor');
    } on TwoFactorException {
      rethrow;
    } catch (_) {
      throw TwoFactorException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.twoFactor,
        ),
      );
    }
  }
}

class TwoFactorException implements Exception {
  const TwoFactorException(this.message);

  final String message;

  @override
  String toString() => 'TwoFactorException';
}
