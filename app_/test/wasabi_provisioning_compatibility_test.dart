import 'dart:convert';

import 'package:cloud_storage/src/storage/wasabi_provisioning_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'updated clients opt into server-managed personal and company storage',
    () async {
      late Map<String, dynamic> submitted;
      final client = MockClient((request) async {
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'result': <String, dynamic>{
              'credentialMode': 'server_managed',
              'storagePrefix': 'account_opaque',
              'serverManagedPrefixes': <String>['account_opaque'],
              'wasabiPolicyVersion': 2,
            },
          }),
          200,
        );
      });
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'user', email: 'user@example.test'),
        signedIn: true,
      );
      final service = WasabiProvisioningService(auth: auth, httpClient: client);

      final result = await service.ensureProvisioned();

      expect(result['wasabiPolicyVersion'], 2);
      expect(result['credentialMode'], 'server_managed');
      expect(
        (submitted['data']
            as Map<String, dynamic>)['supportsServerManagedCompanyStorage'],
        isTrue,
      );
      expect(
        (submitted['data']
            as Map<String, dynamic>)['supportsServerManagedPersonalStorage'],
        isTrue,
      );
    },
  );

  test('provisioning errors ignore REST message and detail fields', () async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'user', email: 'user@example.test'),
      signedIn: true,
    );
    final service = WasabiProvisioningService(
      auth: auth,
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'error': <String, dynamic>{
              'status': 'UNAVAILABLE',
              'message': 'host=private.example object=private/photo.jpg',
            },
            'detail': 'token=secret',
          }),
          503,
        ),
      ),
    );

    await expectLater(
      service.ensureProvisioned(),
      throwsA(
        isA<WasabiProvisioningException>()
            .having(
              (error) => error.message,
              'safe recovery',
              contains('temporarily unavailable'),
            )
            .having(
              (error) => error.message,
              'provider detail',
              isNot(contains('private.example')),
            )
            .having(
              (error) => error.message,
              'file detail',
              isNot(contains('photo.jpg')),
            ),
      ),
    );
  });
}
