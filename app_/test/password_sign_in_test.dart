import 'dart:convert';
import 'package:cloud_storage/src/authentication/password_sign_in.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final code in ['INVALID_LOGIN_CREDENTIALS', 'INVALID_PASSWORD', 'EMAIL_NOT_FOUND']) {
    test('$code preserves a non-enumerating credential error', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'identitytoolkit.googleapis.com');
        expect(request.followRedirects, isFalse);
        return http.Response(jsonEncode({'error': {'message': code}}), 400);
      });
      expect(await diagnoseWindowsPasswordError(apiKey:'public-test-key',email:'probe@example.invalid',password:'synthetic',client:client), 'invalid-credential');
      client.close();
    });
  }
  for (final status in [200, 302, 500]) {
    test('HTTP $status never creates an alternate session or blames credentials', () async {
      final client = MockClient((_) async => http.Response('{}', status));
      expect(await diagnoseWindowsPasswordError(apiKey:'public-test-key',email:'probe@example.invalid',password:'synthetic',client:client), 'auth-service-unavailable');
      client.close();
    });
  }
  test('rate limit is retained', () async {
    final client = MockClient((_) async => http.Response('', 429));
    expect(await diagnoseWindowsPasswordError(apiKey:'public-test-key',email:'probe@example.invalid',password:'synthetic',client:client), 'too-many-requests');
    client.close();
  });
}
