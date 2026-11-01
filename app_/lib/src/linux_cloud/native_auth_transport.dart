import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// User authentication only. Never accepts an administrator credential or a
/// configurable remote credential endpoint. Emulator traffic stays on loopback.
class NativeAuthTransport {
  NativeAuthTransport({
    required this.apiKey,
    http.Client? client,
    this.emulatorPort,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (apiKey.isEmpty || apiKey.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError('A Firebase public API key is required.');
    }
    if (emulatorPort != null && (emulatorPort! < 1 || emulatorPort! > 65535)) {
      throw ArgumentError('Invalid loopback emulator port.');
    }
  }

  final String apiKey;
  final int? emulatorPort;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;

  String get sessionAuthority => emulatorPort == null
      ? 'https://identitytoolkit.googleapis.com'
      : 'http://127.0.0.1:$emulatorPort';

  Future<Map<String, dynamic>> account(
    String operation,
    Map<String, Object?> body, {
    String? languageCode,
  }) {
    if (!const {
      'signInWithPassword',
      'signInWithCustomToken',
      'signUp',
      'lookup',
      'update',
      'delete',
      'sendOobCode',
      'resetPassword',
    }.contains(operation)) {
      throw ArgumentError('Unsupported Firebase authentication operation.');
    }
    return _request(
      'identitytoolkit.googleapis.com',
      'accounts:$operation',
      body,
      languageCode: languageCode,
    );
  }

  Future<Map<String, dynamic>> refresh(String refreshToken) => _request(
    'securetoken.googleapis.com',
    'token',
    {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
    form: true,
  );

  Future<Map<String, dynamic>> _request(
    String host,
    String action,
    Map<String, Object?> body, {
    bool form = false,
    String? languageCode,
  }) async {
    if (_closed) throw StateError('Authentication transport is closed.');
    final uri = emulatorPort == null
        ? Uri.https(host, '/v1/$action', {'key': apiKey})
        : Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: emulatorPort,
            path: '/$host/v1/$action',
            queryParameters: {'key': apiKey},
          );
    final abort = Completer<void>();
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    final request = http.AbortableRequest(
      'POST',
      uri,
      abortTrigger: abort.future,
    )..followRedirects = false;
    if (languageCode != null) {
      if (!RegExp(r'^[A-Za-z0-9-]{1,35}$').hasMatch(languageCode)) {
        timer.cancel();
        throw ArgumentError('Invalid authentication language code.');
      }
      request.headers['X-Firebase-Locale'] = languageCode;
    }
    try {
      if (form) {
        request.bodyFields = body.map((key, value) => MapEntry(key, '$value'));
      } else {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      return await (() async {
        final response = await _client.send(request);
        final bytes = <int>[];
        await for (final part in response.stream) {
          if (bytes.length + part.length > 1024 * 1024) {
            if (!abort.isCompleted) abort.complete();
            throw _failure('internal-error');
          }
          bytes.addAll(part);
        }
        if (response.statusCode == 429) throw _failure('too-many-requests');
        if (response.statusCode >= 500) {
          throw _failure('auth-service-unavailable');
        }
        if (response.statusCode >= 300 && response.statusCode < 400) {
          throw _failure('auth-service-unavailable');
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) throw _failure('internal-error');
        if (response.statusCode != 200) {
          final error = decoded['error'];
          final raw = error is Map ? error['message'] : null;
          final category = raw is String
              ? raw.split(RegExp(r'[ :\n]')).first
              : '';
          throw _failure(switch (category) {
            'INVALID_LOGIN_CREDENTIALS' ||
            'INVALID_PASSWORD' ||
            'EMAIL_NOT_FOUND' => 'invalid-credential',
            'EMAIL_EXISTS' => 'email-already-in-use',
            'INVALID_EMAIL' => 'invalid-email',
            'USER_DISABLED' => 'user-disabled',
            'WEAK_PASSWORD' => 'weak-password',
            'TOKEN_EXPIRED' || 'INVALID_ID_TOKEN' => 'invalid-user-token',
            'INVALID_REFRESH_TOKEN' || 'USER_NOT_FOUND' => 'user-token-expired',
            'CREDENTIAL_TOO_OLD_LOGIN_AGAIN' => 'requires-recent-login',
            'TOO_MANY_ATTEMPTS_TRY_LATER' => 'too-many-requests',
            'OPERATION_NOT_ALLOWED' ||
            'PASSWORD_LOGIN_DISABLED' => 'operation-not-allowed',
            'EXPIRED_OOB_CODE' => 'expired-action-code',
            'INVALID_OOB_CODE' => 'invalid-action-code',
            _ => 'internal-error',
          });
        }
        return decoded;
      })().timeout(timeout);
    } on FirebaseAuthException {
      rethrow;
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw _failure('network-request-failed');
    } on http.ClientException {
      throw _failure('network-request-failed');
    } on FormatException {
      throw _failure('internal-error');
    } finally {
      timer.cancel();
    }
  }

  static FirebaseAuthException _failure(String code) => FirebaseAuthException(
    code: code,
    message: 'The authentication request could not be completed.',
  );

  void close() {
    _closed = true;
    if (_ownsClient) _client.close();
  }
}
