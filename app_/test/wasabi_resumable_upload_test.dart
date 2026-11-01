import 'dart:convert';
import 'package:cloud_storage/src/storage/upload_coordinator.dart';
import 'package:cloud_storage/src/storage/wasabi_storage_service.dart';
import 'package:cloud_storage/src/storage/secure_upload_checkpoint.dart';
import 'package:cloud_storage/src/storage/multipart_upload_checkpoint_sink.dart';
import 'package:cloud_storage/src/storage/upload_cipher.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Checkpoints implements ResumableUploadCheckpointSink {
  final values = <String, Map<String, dynamic>>{};
  @override
  Map<String, dynamic>? uploadCheckpoint(String id) => values[id];
  @override
  Future<void> saveUploadCheckpoint(
    String id,
    Map<String, dynamic> value,
  ) async {
    values[id] = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }
}

void main() {
  test(
    'secure shard restart reuses ciphertext after a lost completion response',
    () async {
      final journal = _Checkpoints();
      final key = SecretKey(List.filled(32, 7));
      final plain = List<int>.generate(100000, (i) => i % 251);
      final uploaded = <List<int>>[];
      var providerComplete = false;
      final service = WasabiStorageService.serverManaged(
        bucket: 'bucket',
        authorizedObjectUri: Uri.parse('https://api.test/authorize'),
        idTokenProvider: () async => 'token',
        serverManagedPrefixes: ['user'],
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            uploaded.add(request.bodyBytes);
            return http.Response('', 200, headers: {'etag': 'saved'});
          }
          final operation = request.url.pathSegments.last;
          if (operation == 'complete' && !providerComplete) {
            providerComplete = true;
            return http.Response('{}', 503);
          }
          return http.Response(
            jsonEncode(switch (operation) {
              'start' => {'sessionId': 'shard-session'},
              'status' => {
                'status': providerComplete ? 'uploaded' : 'uploading',
                'parts': [],
              },
              'urls' => {
                'parts': [
                  {'url': 'https://storage.test/object'},
                ],
              },
              _ => {'ok': true},
            }),
            200,
          );
        }),
      );
      Future<void> attempt() async {
        final parent = await SecureUploadCheckpoint.open(
          sink: journal,
          parentId: 'parent',
          objectKey: 'user/objects/file',
          fingerprint: 'same-source',
          newNonce: () => List.filled(16, 3),
        );
        final chunks = await encryptUploadStream(
          Stream.value(plain),
          key,
          parent.nonce,
        ).toList();
        final encrypted = chunks.expand((chunk) => chunk).toList();
        await service.upload(
          objectKey: 'user/objects/file.parts/opaque',
          stream: Stream.value(encrypted),
          length: encrypted.length,
          payloadAlreadyEncrypted: true,
          transferId: 'parent:shard:0',
          checkpointSink: parent,
          sourceFingerprint: 'same-source',
        );
      }

      await expectLater(attempt(), throwsA(isA<UploadFailure>()));
      await attempt();
      expect(uploaded, hasLength(1));
      final bytes = uploaded.single;
      expect(
        await AesCtr.with256bits(macAlgorithm: Hmac.sha256()).decrypt(
          SecretBox(
            bytes.sublist(16, bytes.length - 32),
            nonce: bytes.sublist(0, 16),
            mac: Mac(bytes.sublist(bytes.length - 32)),
          ),
          secretKey: key,
        ),
        plain,
      );
      UploadCoordinator.instance.metadataCompleted('user/objects/file');
      expect(
        UploadCoordinator.instance.jobs.last.state,
        UploadJobState.completed,
      );
    },
    skip: !UploadCoordinator.enabled,
  );

  test(
    'flagged storage uploads encrypted parts directly and preserves decryption',
    () async {
      final bodies = <List<int>>[];
      final operations = <String>[];
      final plain = List<int>.generate(100000, (index) => index % 251);
      final key = SecretKey(List.filled(32, 7));
      final service = WasabiStorageService.serverManaged(
        bucket: 'bucket',
        authorizedObjectUri: Uri.parse('https://api.test/authorize'),
        idTokenProvider: () async => 'test-token',
        serverManagedPrefixes: ['user'],
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            expect(request.url.host, 'storage.test');
            expect(request.headers['x-amz-meta-upload-session'], 'session');
            bodies.add(request.bodyBytes);
            return http.Response('', 200, headers: {'etag': 'accepted'});
          }
          expect(request.bodyBytes.length, lessThan(2048));
          expect(request.url.path, contains('/storage/uploads/'));
          final operation = request.url.pathSegments.last;
          operations.add(operation);
          return http.Response(
            jsonEncode(switch (operation) {
              'start' => {'sessionId': 'session'},
              'status' => {'status': 'uploading', 'parts': []},
              'urls' => {
                'parts': [
                  {'url': 'https://storage.test/object', 'headers': {'x-amz-meta-upload-session': 'session'}},
                ],
              },
              _ => {'ok': true},
            }),
            200,
          );
        }),
      );
      await service.upload(
        objectKey: 'user/objects/opaque',
        stream: Stream.value(plain),
        length: plain.length,
        encryptionKey: key,
      );
      final encrypted = bodies.expand((part) => part).toList();
      expect(encrypted.length, plain.length + 48);
      final algorithm = AesCtr.with256bits(macAlgorithm: Hmac.sha256());
      expect(
        await algorithm.decrypt(
          SecretBox(
            encrypted.sublist(16, encrypted.length - 32),
            nonce: encrypted.sublist(0, 16),
            mac: Mac(encrypted.sublist(encrypted.length - 32)),
          ),
          secretKey: key,
        ),
        plain,
      );
      expect(operations, ['start', 'status', 'urls', 'complete']);
    },
    skip: !UploadCoordinator.enabled,
  );
}
