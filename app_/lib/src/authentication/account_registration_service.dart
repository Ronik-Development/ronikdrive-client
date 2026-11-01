import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../shared/release_runtime_config.dart';

class AccountRegistrationException implements Exception {
  const AccountRegistrationException(this.code, this.message);
  final String code;
  final String message;
}

class AccountRegistrationService {
  AccountRegistrationService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    http.Client? httpClient,
    Uri? restUri,
    bool? preferRest,
  }) : _functions = functions,
       _auth = auth,
       _httpClient = httpClient,
       _restUri = restUri,
       _preferRest =
           preferRest ??
           (kIsWeb ||
               defaultTargetPlatform == TargetPlatform.windows ||
               defaultTargetPlatform == TargetPlatform.linux);

  factory AccountRegistrationService.forApp(FirebaseApp app) =>
      AccountRegistrationService(
        functions: FirebaseFunctions.instanceFor(
          app: app,
          region: 'europe-west1',
        ),
        auth: FirebaseAuth.instanceFor(app: app),
      );

  final FirebaseFunctions? _functions;
  final FirebaseAuth? _auth;
  final http.Client? _httpClient;
  final Uri? _restUri;
  final bool _preferRest;

  Future<void> register({
    required String username,
    required String legalVersion,
    required String legalAcceptedAt,
    required bool productUpdatesOptIn,
    required bool recoveryEmailProvided,
    required String createdAt,
  }) async {
    final payload = <String, dynamic>{
      'username': username,
      'legalVersion': legalVersion,
      'legalAcceptedAt': legalAcceptedAt,
      'productUpdatesOptIn': productUpdatesOptIn,
      'recoveryEmailProvided': recoveryEmailProvided,
      'createdAt': createdAt,
    };
    try {
      if (_preferRest) {
        await _registerViaRest(payload);
      } else {
        await _functions!
            .httpsCallable('registerAccountProfile')
            .call(payload)
            .timeout(const Duration(seconds: 20));
      }
    } on AccountRegistrationException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw _failure(error.code);
    } on FirebaseAuthException catch (error) {
      throw _failure(
        error.code == 'network-request-failed'
            ? 'unavailable'
            : 'unauthenticated',
      );
    } on TimeoutException {
      throw _failure('deadline-exceeded');
    } on Exception {
      throw _failure('unavailable');
    }
  }

  Future<void> _registerViaRest(Map<String, dynamic> payload) async {
    final auth = _auth;
    final user = auth?.currentUser;
    if (auth == null || user == null) throw _failure('unauthenticated');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) throw _failure('unauthenticated');
    final uri =
        _restUri ??
        ReleaseRuntimeConfig.resolveCallableRestUri(
          projectId: auth.app.options.projectId,
          functionName: 'registerAccountProfile',
        );
    final client = _httpClient ?? http.Client();
    try {
      final response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'data': payload}),
          )
          .timeout(const Duration(seconds: 20));
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
      final error = decoded is Map ? decoded['error'] : null;
      if (error is Map) {
        final status = error['status'];
        throw _failure(
          status is String
              ? status.toLowerCase().replaceAll('_', '-')
              : 'internal',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _failure(switch (response.statusCode) {
          401 => 'unauthenticated',
          403 => 'permission-denied',
          429 => 'resource-exhausted',
          _ => 'unavailable',
        });
      }
      if (decoded is! Map || decoded['result'] is! Map) {
        throw _failure('internal');
      }
    } finally {
      if (_httpClient == null) client.close();
    }
  }

  AccountRegistrationException _failure(
    String code,
  ) => AccountRegistrationException(
    code,
    code == 'invalid-argument'
        ? 'Check your username and accept the current terms, then try again.'
        : 'Account setup could not be completed. Please try again.',
  );
}
