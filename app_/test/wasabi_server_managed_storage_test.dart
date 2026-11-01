import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_storage/src/security/encryption_service.dart';
import 'package:cloud_storage/src/storage/wasabi_storage_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final corrupt in [false, true]) {
    test(
      'buffered encrypted download uses one GET and verifies integrity (corrupt: $corrupt)',
      () async {
        final key = SecretKey(List<int>.filled(32, 7));
        final original = Uint8List.fromList(
          utf8.encode('A private shared file'),
        );
        final encrypted = await EncryptionService.instance.encryptData(
          original,
          key,
        );
        if (corrupt) encrypted[encrypted.length - 1] ^= 1;
        var storageGets = 0;
        var authorizations = 0;
        final service = WasabiStorageService.serverManaged(
          bucket: 'bucket',
          idTokenProvider: () async => 'firebase-token',
          authorizedObjectUri: Uri.parse('https://api.example/authorize'),
          serverManagedPrefixes: const ['user_opaque'],
          httpClient: MockClient((request) async {
            if (request.url.host == 'api.example') {
              authorizations++;
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'url': 'https://storage.example/object',
                }),
                200,
              );
            }
            storageGets++;
            expect(request.headers['range'], 'bytes=0-${encrypted.length}');
            return http.Response.bytes(encrypted, 200);
          }),
        );
        final download = service.download(
          objectKey: 'user_opaque/objects/file',
          encryptionKey: key,
          preferProxy: true,
          maxPlaintextBytes: original.length,
        );
        if (corrupt) {
          await expectLater(
            download,
            throwsA(isA<SecretBoxAuthenticationError>()),
          );
        } else {
          final received = BytesBuilder();
          await for (final bytes in await download) {
            received.add(bytes);
          }
          expect(received.takeBytes(), original);
        }
        expect(storageGets, 1);
        expect(authorizations, 1);
      },
    );
  }

  test(
    'buffered encrypted download enforces limit without content length',
    () async {
      final service = WasabiStorageService.serverManaged(
        bucket: 'bucket',
        idTokenProvider: () async => 'firebase-token',
        authorizedObjectUri: Uri.parse('https://api.example/authorize'),
        serverManagedPrefixes: const ['user_opaque'],
        httpClient: MockClient.streaming((request, _) async {
          if (request.url.host == 'api.example') {
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'ok': true,
                    'url': 'https://storage.example/object',
                  }),
                ),
              ),
              200,
            );
          }
          return http.StreamedResponse(
            Stream.value(List<int>.filled(1024, 0)),
            200,
          );
        }),
      );
      await expectLater(
        service.download(
          objectKey: 'user_opaque/objects/file',
          encryptionKey: SecretKey(List<int>.filled(32, 7)),
          preferProxy: true,
          maxPlaintextBytes: 4,
        ),
        throwsA(isA<WasabiDownloadLimitException>()),
      );
    },
  );

  test(
    'company objects use live authorization for put, get, and delete',
    () async {
      final authorizedActions = <String>[];
      final storageMethods = <String>[];
      final client = MockClient((request) async {
        if (request.url.host == 'api.example') {
          expect(request.headers['authorization'], 'Bearer firebase-token');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final action = body['action'] as String;
          if (action == 'put') expect(body['contentLength'], 3);
          authorizedActions.add(action);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'ok': true,
              'url': 'https://storage.example/object?operation=$action',
            }),
            200,
          );
        }
        storageMethods.add(request.method);
        switch (request.method) {
          case 'PUT':
            expect(request.bodyBytes, Uint8List.fromList(<int>[1, 2, 3]));
            return http.Response('', 200, headers: const {'etag': 'etag'});
          case 'GET':
            expect(request.headers['range'], 'bytes=0-3');
            return http.Response.bytes(<int>[4, 5, 6], 200);
          case 'DELETE':
            return http.Response('', 204);
        }
        return http.Response('', 405);
      });
      final service = WasabiStorageService(
        accessKey: 'personal-access-key',
        secretKey: 'personal-secret-key',
        bucket: 'bucket',
        httpClient: client,
        browserUploadIdTokenProvider: () async => 'firebase-token',
        authorizedObjectUri: Uri.parse('https://api.example/authorize'),
        serverManagedPrefixes: const <String>[
          'company_1234567890abcdef1234567890ab',
        ],
      );
      const key = 'company_1234567890abcdef1234567890ab/shared/file.bin';

      await service.upload(
        objectKey: key,
        stream: Stream<List<int>>.value(<int>[1, 2, 3]),
        length: 3,
        payloadAlreadyEncrypted: true,
      );
      final downloadStream = await service.download(
        objectKey: key,
        maxPlaintextBytes: 3,
      );
      final downloadedBuilder = BytesBuilder(copy: false);
      await for (final chunk in downloadStream) {
        downloadedBuilder.add(chunk);
      }
      final downloaded = downloadedBuilder.takeBytes();
      await service.deleteObject(key);

      expect(downloaded, Uint8List.fromList(<int>[4, 5, 6]));
      expect(authorizedActions, <String>['put', 'get', 'delete']);
      expect(storageMethods, <String>['PUT', 'GET', 'DELETE']);
    },
  );

  test(
    'authorized downloads reject an oversized object before buffering',
    () async {
      var storageGets = 0;
      final service = WasabiStorageService.serverManaged(
        bucket: 'bucket',
        idTokenProvider: () async => 'firebase-token',
        authorizedObjectUri: Uri.parse('https://api.example/authorize'),
        serverManagedPrefixes: const <String>['user_opaque'],
        httpClient: MockClient((request) async {
          if (request.url.host == 'api.example') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'ok': true,
                'url': 'https://storage.example/object',
              }),
              200,
            );
          }
          storageGets += 1;
          expect(request.headers['range'], 'bytes=0-4');
          return http.Response.bytes(
            <int>[1, 2, 3, 4, 5],
            206,
            headers: const <String, String>{'content-range': 'bytes 0-4/5'},
          );
        }),
      );

      await expectLater(
        service.download(
          objectKey: 'user_opaque/objects/aa/bb/opaque',
          maxPlaintextBytes: 4,
        ),
        throwsA(isA<WasabiDownloadLimitException>()),
      );
      expect(storageGets, 1);
    },
  );

  test(
    'encrypted authorized downloads reject oversized ciphertext early',
    () async {
      final algorithm = EncryptionService.instance.fileContentAlgorithm;
      const maxPlaintextBytes = 4;
      final oversizedEncryptedLength =
          maxPlaintextBytes +
          algorithm.nonceLength +
          algorithm.macAlgorithm.macLength +
          1;
      final service = WasabiStorageService.serverManaged(
        bucket: 'bucket',
        idTokenProvider: () async => 'firebase-token',
        authorizedObjectUri: Uri.parse('https://api.example/authorize'),
        serverManagedPrefixes: const <String>['user_opaque'],
        httpClient: MockClient((request) async {
          if (request.url.host == 'api.example') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'ok': true,
                'url': 'https://storage.example/object',
              }),
              200,
            );
          }
          expect(
            request.headers['range'],
            'bytes=0-${algorithm.nonceLength - 1}',
          );
          return http.Response.bytes(
            List<int>.filled(algorithm.nonceLength, 0),
            206,
            headers: <String, String>{
              'content-range':
                  'bytes 0-${algorithm.nonceLength - 1}/$oversizedEncryptedLength',
            },
          );
        }),
      );

      await expectLater(
        service.download(
          objectKey: 'user_opaque/objects/aa/bb/opaque',
          encryptionKey: SecretKey(List<int>.filled(32, 7)),
          maxPlaintextBytes: maxPlaintextBytes,
        ),
        throwsA(isA<WasabiDownloadLimitException>()),
      );
    },
  );

  test(
    'browser proxy download bounds decoded bytes without direct fallback',
    () async {
      var requestCount = 0;
      final service = WasabiStorageService(
        accessKey: 'legacy-access-key',
        secretKey: 'legacy-secret-key',
        bucket: 'bucket',
        browserUploadIdTokenProvider: () async => 'firebase-token',
        browserDownloadProxyUri: Uri.parse(
          'https://api.example/proxy-download',
        ),
        httpClient: MockClient((request) async {
          requestCount += 1;
          expect(request.method, 'POST');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'bytesBase64': base64Encode(<int>[1, 2, 3, 4, 5]),
            }),
            200,
          );
        }),
      );

      await expectLater(
        service.download(
          objectKey: 'legacy/opaque.bin',
          preferProxy: true,
          maxPlaintextBytes: 4,
        ),
        throwsA(isA<WasabiDownloadLimitException>()),
      );
      expect(requestCount, 1);
    },
  );

  test(
    'personal objects work without provider credentials or provider error bodies',
    () async {
      final authorizedActions = <String>[];
      final authorizedContentTypes = <String>[];
      final storageContentTypes = <String>[];
      final client = MockClient((request) async {
        if (request.url.host == 'api.example') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final action = body['action'] as String;
          authorizedActions.add(action);
          authorizedContentTypes.add(body['contentType'] as String);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'ok': true,
              'url': 'https://storage.example/object?operation=$action',
            }),
            200,
          );
        }
        if (request.method == 'PUT') {
          storageContentTypes.add(request.headers['content-type'] ?? '');
          return http.Response(
            '<ProviderError>internal provider detail</ProviderError>',
            503,
          );
        }
        return http.Response('', 405);
      });
      final service = WasabiStorageService.serverManaged(
        bucket: 'bucket',
        idTokenProvider: () async => 'firebase-token',
        authorizedObjectUri: Uri.parse('https://api.example/authorize'),
        serverManagedPrefixes: const <String>['user_opaque'],
        httpClient: client,
      );

      expect(service.isConfigured, isTrue);
      expect(service.accessKey, isEmpty);
      expect(service.secretKey, isEmpty);

      await expectLater(
        service.upload(
          objectKey: 'user_opaque/files/file.bin',
          stream: Stream<List<int>>.value(<int>[1, 2, 3]),
          length: 3,
          contentType: 'application/pdf',
          encryptionKey: SecretKey(List<int>.filled(32, 7)),
        ),
        throwsA(
          isA<WasabiStorageException>()
              .having(
                (error) => error.message,
                'message',
                contains('temporarily unavailable'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('internal provider detail')),
              ),
        ),
      );
      expect(authorizedActions, <String>['put']);
      expect(authorizedContentTypes, <String>['application/octet-stream']);
      expect(storageContentTypes, <String>['application/octet-stream']);
    },
  );

  test('authorization errors do not expose backend response bodies', () async {
    final service = WasabiStorageService.serverManaged(
      bucket: 'bucket',
      idTokenProvider: () async => 'firebase-token',
      authorizedObjectUri: Uri.parse('https://api.example/authorize'),
      serverManagedPrefixes: const <String>['user_opaque'],
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'error': <String, dynamic>{
              'status': 'PERMISSION_DENIED',
              'message': 'host=private.example object=user_opaque/private.jpg',
            },
            'detail': 'token=secret',
          }),
          403,
        ),
      ),
    );

    await expectLater(
      service.upload(
        objectKey: 'user_opaque/objects/aa/bb/opaque',
        stream: Stream<List<int>>.value(<int>[1, 2, 3]),
        length: 3,
        payloadAlreadyEncrypted: true,
      ),
      throwsA(
        isA<WasabiStorageException>()
            .having(
              (error) => error.message,
              'safe recovery',
              contains('not allowed'),
            )
            .having(
              (error) => error.message,
              'provider host',
              isNot(contains('private.example')),
            )
            .having(
              (error) => error.message,
              'object detail',
              isNot(contains('private.jpg')),
            ),
      ),
    );
  });

  test('refuses an upload without an encryption guarantee', () async {
    var requestCount = 0;
    final service = WasabiStorageService.serverManaged(
      bucket: 'bucket',
      idTokenProvider: () async => 'firebase-token',
      authorizedObjectUri: Uri.parse('https://api.example/authorize'),
      serverManagedPrefixes: const <String>['user_opaque'],
      httpClient: MockClient((request) async {
        requestCount += 1;
        return http.Response('', 500);
      }),
    );

    await expectLater(
      service.upload(
        objectKey: 'user_opaque/objects/aa/bb/opaque',
        stream: Stream<List<int>>.value(<int>[1, 2, 3]),
        length: 3,
        contentType: 'text/plain',
      ),
      throwsA(
        isA<WasabiStorageException>().having(
          (error) => error.message,
          'message',
          contains('client-side encryption'),
        ),
      ),
    );
    expect(requestCount, 0);
  });

  test('refuses ambiguous double-encryption instructions', () async {
    final service = WasabiStorageService.serverManaged(
      bucket: 'bucket',
      idTokenProvider: () async => 'firebase-token',
      authorizedObjectUri: Uri.parse('https://api.example/authorize'),
      serverManagedPrefixes: const <String>['user_opaque'],
      httpClient: MockClient((request) async => http.Response('', 500)),
    );

    await expectLater(
      service.upload(
        objectKey: 'user_opaque/objects/aa/bb/opaque',
        stream: Stream<List<int>>.value(<int>[1, 2, 3]),
        length: 3,
        encryptionKey: SecretKey(List<int>.filled(32, 9)),
        payloadAlreadyEncrypted: true,
      ),
      throwsA(
        isA<WasabiStorageException>().having(
          (error) => error.message,
          'message',
          contains('ambiguous'),
        ),
      ),
    );
  });

  test(
    'storage logs omit item fingerprints, names, sizes, and MIME types',
    () async {
      final messages = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          messages.add(message);
        }
      };
      final service = WasabiStorageService.serverManaged(
        bucket: 'bucket',
        idTokenProvider: () async => 'firebase-token',
        authorizedObjectUri: Uri.parse('https://api.example/authorize'),
        serverManagedPrefixes: const <String>['user_opaque'],
        httpClient: MockClient((request) async {
          if (request.url.host == 'api.example') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'ok': true,
                'url': 'https://storage.example/object',
              }),
              200,
            );
          }
          return http.Response('', 200);
        }),
      );
      const legacyKey = 'user_opaque/My Drive/Taxes/private-tax-return.pdf';

      try {
        await service.upload(
          objectKey: legacyKey,
          stream: Stream<List<int>>.value(<int>[1, 2, 3]),
          length: 3,
          contentType: 'application/pdf',
          payloadAlreadyEncrypted: true,
        );
      } finally {
        debugPrint = originalDebugPrint;
      }

      final output = messages.join('\n');
      expect(output, contains('Preparing a client-encrypted upload.'));
      expect(output, isNot(contains('obj-')));
      expect(output, isNot(contains('user_opaque')));
      expect(output, isNot(contains(legacyKey)));
      expect(output, isNot(contains('private-tax-return.pdf')));
      expect(output, isNot(contains('application/pdf')));
      expect(output, isNot(contains('3 bytes')));
    },
  );
}
