import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_storage/src/security/encryption_setup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    test('$platform sets up encryption through authenticated HTTPS', () async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final salt = List<int>.generate(16, (i) => i);
      final service = EncryptionSetupService(
        functions: _UnusedFunctions(),
        auth: MockFirebaseAuth(
          mockUser: MockUser(uid: 'desktop'),
          signedIn: true,
        ),
        ensureStandardEncryptionSaltRestUri: Uri.https(
          'example.test',
          '/ensureStandardEncryptionSalt',
        ),
        httpClient: MockClient((request) async {
          expect(request.headers['Authorization'], startsWith('Bearer '));
          expect(jsonDecode(request.body), {'data': {}});
          return http.Response(
            jsonEncode({
              'result': {'saltBase64': base64Encode(salt)},
            }),
            200,
          );
        }),
      );
      expect(await service.ensureStandardEncryptionSalt(), salt);
    });
  }
  test('standard encryption setup sends no client identity fields', () {
    expect(standardEncryptionSetupRequestPayload, isEmpty);
    expect(standardEncryptionSetupRequestPayload, isNot(contains('email')));
    expect(
      standardEncryptionSetupRequestPayload,
      isNot(contains('displayName')),
    );
  });
}

class _UnusedFunctions extends Fake implements FirebaseFunctions {}
