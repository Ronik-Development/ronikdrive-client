import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../shared/service_environment.dart';

/// Recover the provider's error category when the Windows C++ SDK loses it.
/// Authentication/session establishment always stays with the Firebase SDK.
Future<UserCredential> signInWithPassword({
  required FirebaseAuth auth,
  required String email,
  required String password,
}) async {
  try {
    return await auth.signInWithEmailAndPassword(email: email, password: password);
  } on FirebaseAuthException catch (error) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows ||
        error.code != 'unknown-error' ||
        ServiceEnvironmentConfig.current != ServiceEnvironment.production) {
      rethrow;
    }
    final code = await diagnoseWindowsPasswordError(
      apiKey: auth.app.options.apiKey, email: email, password: password,
    );
    throw FirebaseAuthException(code: code);
  }
}

/// No credentials, response bodies or issued tokens are logged or persisted.
/// A successful REST response is not used as a substitute Firebase session.
Future<String> diagnoseWindowsPasswordError({
  required String apiKey,
  required String email,
  required String password,
  http.Client? client,
}) async {
  final transport = client ?? http.Client();
  try {
    final request = http.Request('POST', Uri.https(
      'identitytoolkit.googleapis.com', '/v1/accounts:signInWithPassword',
      {'key': apiKey},
    ))..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'email': email, 'password': password, 'returnSecureToken': true});
    final response = await transport.send(request).timeout(const Duration(seconds: 10));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(const Duration(seconds: 10))) {
      if (bytes.length + chunk.length > 65536) return 'auth-service-unavailable';
      bytes.addAll(chunk);
    }
    if (response.statusCode == 429) return 'too-many-requests';
    if (response.statusCode != 400) return 'auth-service-unavailable';
    final body = jsonDecode(utf8.decode(bytes));
    final code = body is Map && body['error'] is Map ? body['error']['message'] : null;
    return switch (code) {
      'INVALID_LOGIN_CREDENTIALS' || 'INVALID_PASSWORD' || 'EMAIL_NOT_FOUND' => 'invalid-credential',
      'INVALID_EMAIL' => 'invalid-email',
      'USER_DISABLED' => 'user-disabled',
      'TOO_MANY_ATTEMPTS_TRY_LATER' => 'too-many-requests',
      'OPERATION_NOT_ALLOWED' || 'PASSWORD_LOGIN_DISABLED' => 'operation-not-allowed',
      _ => 'auth-service-unavailable',
    };
  } on TimeoutException {
    return 'network-request-failed';
  } on http.ClientException {
    return 'network-request-failed';
  } catch (_) {
    return 'auth-service-unavailable';
  } finally {
    if (client == null) transport.close();
  }
}
