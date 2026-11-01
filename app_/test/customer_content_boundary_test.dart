import 'dart:convert';
import 'dart:math';
import 'package:cloud_storage/src/security/business_encryption_registry.dart';
import 'package:cloud_storage/src/security/business_encryption_service.dart';
import 'package:cloud_storage/src/security/encryption_service.dart';
import 'package:cloud_storage/src/storage/wasabi_storage_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'client upload sends ciphertext to storage and no content key to API',
    () async {
      final keyBytes = List<int>.generate(32, (i) => i + 71);
      final key = SecretKey(keyBytes);
      final plaintext = utf8.encode(
        'SYNTHETIC_CUSTOMER_CONTENT_DO_NOT_TRANSMIT',
      );
      final apiBodies = <String>[];
      List<int>? stored;
      final service = WasabiStorageService.serverManaged(
        bucket: 'synthetic',
        idTokenProvider: () async => 'synthetic-token',
        authorizedObjectUri: Uri.parse('https://api.example/authorize'),
        serverManagedPrefixes: const ['user_opaque'],
        httpClient: MockClient((request) async {
          if (request.url.host == 'api.example') {
            apiBodies.add(request.body);
            return http.Response(
              jsonEncode({'ok': true, 'url': 'https://storage.example/object'}),
              200,
            );
          }
          stored = request.bodyBytes;
          return http.Response('', 200, headers: {'etag': 'synthetic'});
        }),
      );
      await service.upload(
        objectKey: 'user_opaque/objects/opaque',
        stream: Stream.value(plaintext),
        length: plaintext.length,
        encryptionKey: key,
      );
      expect(apiBodies, isNotEmpty);
      for (final body in [
        ...apiBodies,
        utf8.decode(stored!, allowMalformed: true),
      ]) {
        expect(body, isNot(contains(utf8.decode(plaintext))));
        expect(body, isNot(contains(base64Encode(plaintext))));
        expect(body, isNot(contains(base64Encode(keyBytes))));
        expect(body, isNot(contains(base64UrlEncode(keyBytes))));
        expect(
          body,
          isNot(contains(base64UrlEncode(keyBytes).replaceAll('=', ''))),
        );
        expect(body, isNot(contains(jsonEncode(keyBytes))));
      }
      final bytes = stored!;
      final cipher = EncryptionService.instance.fileContentAlgorithm;
      final box = SecretBox(
        bytes.sublist(16, bytes.length - 32),
        nonce: bytes.sublist(0, 16),
        mac: Mac(bytes.sublist(bytes.length - 32)),
      );
      expect(await cipher.decrypt(box, secretKey: key), plaintext);
      await expectLater(
        cipher.decrypt(box, secretKey: SecretKey(List.filled(32, 0))),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );

  test(
    'operator-visible registration contains only a protected identity',
    () async {
      final service = BusinessEncryptionService(random: Random(403));
      final protectionBytes = List<int>.generate(32, (i) => i + 101);
      final protection = SecretKey(protectionBytes);
      final calls = <Map<String, Object?>>[];
      final registry = BusinessEncryptionRegistry(
        encryptionService: service,
        callable: (name, payload) async {
          if (name == 'getBusinessEncryptionIdentity') {
            return {'identity': null};
          }
          expect(name, 'registerBusinessEncryptionIdentity');
          calls.add(payload!);
          return {'identity': payload['identity']};
        },
      );
      final identity = await registry.ensureIdentity(
        accountProtectionKey: protection,
      );
      final wire = jsonEncode(calls);
      expect(wire, isNot(contains(base64UrlEncode(protectionBytes))));
      expect(wire, isNot(contains('"privateKeyBase64"')));
      expect(wire, contains('wrappedPrivateKeyBase64'));
      const object = 'company_opaque/shared/object';
      final material = await service.createFileEncryptionMaterial(
        objectKey: object,
        recipients: [
          BusinessEncryptionRecipient(
            uid: 'customer',
            keyId: identity.keyId,
            publicKeyBase64: identity.publicKeyBase64,
          ),
        ],
      );
      final other = await service.createIdentity(
        accountProtectionKey: protection,
      );
      // Relabeling a stored envelope or substituting another identity grants no access.
      for (final attempt in [('operator', identity), ('customer', other)]) {
        await expectLater(
          service.openFileKey(
            objectKey: object,
            currentUid: attempt.$1,
            identity: attempt.$2,
            envelope: material.envelopes['customer']!,
            accountProtectionKey: protection,
          ),
          throwsA(isA<BusinessEncryptionException>()),
        );
      }
    },
  );
}
