import 'dart:convert';

import 'package:cloud_storage/src/home/migration/oauth_pkce.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('PKCE generator creates RFC 7636 compatible verifier and challenge', () {
    final pair = OAuthPkcePair.generate();
    expect(pair.verifier.length, inInclusiveRange(43, 128));
    expect(pair.verifier, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(pair.challenge, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
  });

  test(
    'authorization code exchange validates state and sends verifier',
    () async {
      late Map<String, String> submitted;
      final client = MockClient((request) async {
        submitted = Uri.splitQueryString(request.body);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'access_token': 'token',
            'expires_in': 3600,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final result = await exchangeOAuthAuthorizationCode(
        client: client,
        tokenEndpoint: Uri.parse('https://provider.example/token'),
        redirect: Uri.parse(
          'https://app.example/callback?code=abc&state=expected',
        ),
        expectedState: 'expected',
        clientId: 'client',
        codeVerifier: 'verifier',
        redirectUri: Uri.parse('https://app.example/callback'),
      );
      expect(result['access_token'], 'token');
      expect(submitted['code'], 'abc');
      expect(submitted['code_verifier'], 'verifier');
      expect(submitted['grant_type'], 'authorization_code');
    },
  );

  test(
    'authorization code exchange rejects state mismatch before token request',
    () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      await expectLater(
        exchangeOAuthAuthorizationCode(
          client: client,
          tokenEndpoint: Uri.parse('https://provider.example/token'),
          redirect: Uri.parse(
            'https://app.example/callback?code=abc&state=wrong',
          ),
          expectedState: 'expected',
          clientId: 'client',
          codeVerifier: 'verifier',
          redirectUri: Uri.parse('https://app.example/callback'),
        ),
        throwsStateError,
      );
      expect(called, isFalse);
    },
  );
}
