import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

class OAuthPkcePair {
  const OAuthPkcePair({required this.verifier, required this.challenge});

  factory OAuthPkcePair.generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(64, (_) => random.nextInt(256));
    final verifier = base64UrlEncode(bytes).replaceAll('=', '');
    final challenge = base64UrlEncode(
      crypto.sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    return OAuthPkcePair(verifier: verifier, challenge: challenge);
  }

  final String verifier;
  final String challenge;
}

Future<Map<String, dynamic>> exchangeOAuthAuthorizationCode({
  required http.Client client,
  required Uri tokenEndpoint,
  required Uri redirect,
  required String expectedState,
  required String clientId,
  required String codeVerifier,
  required Uri redirectUri,
  Map<String, String> extraFields = const <String, String>{},
}) async {
  final returnedState = redirect.queryParameters['state'];
  final code = redirect.queryParameters['code'];
  final oauthError = redirect.queryParameters['error'];
  if (returnedState != expectedState) {
    throw StateError('The sign-in provider returned an invalid state.');
  }
  if (oauthError != null || code == null || code.isEmpty) {
    throw StateError(
      'The sign-in provider did not return an authorization code.',
    );
  }
  final response = await client
      .post(
        tokenEndpoint,
        headers: const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: <String, String>{
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'code': code,
          'redirect_uri': redirectUri.toString(),
          'code_verifier': codeVerifier,
          ...extraFields,
        },
      )
      .timeout(const Duration(seconds: 30));
  dynamic decoded;
  try {
    decoded = jsonDecode(response.body);
  } on FormatException {
    decoded = null;
  }
  if (response.statusCode < 200 ||
      response.statusCode >= 300 ||
      decoded is! Map) {
    throw StateError('The sign-in provider rejected the authorization code.');
  }
  return Map<String, dynamic>.from(
    decoded.map((key, value) => MapEntry(key.toString(), value)),
  );
}
