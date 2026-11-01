import 'dart:convert';
import 'package:cloud_storage/src/privacy/local_private_cache.dart';
import 'package:cloud_storage/src/share/file_request_resumable_upload.dart';
import 'package:cloud_storage/src/share/public_transfer_failure.dart';
import 'package:cloud_storage/src/storage/transfer_journal.dart';
import 'package:cloud_storage/src/storage/upload_coordinator.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Keys implements LocalPrivateCacheKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  for (final lost in ['authorize', 'uploads/complete', 'complete', 'expired']) {
    test(
      'public encrypted upload recovers lost $lost response after restart',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final codec = LocalPrivateCacheCodec(keyStore: _Keys());
        Future<TransferJournal> openJournal() => TransferJournal.open(
          preferences: preferences,
          uid: 'request-fixture',
          scope: 'test',
          codec: codec,
        );
        var journal = await openJournal();
        final clientIds = <String>[];
        var lostResponse = false;
        var expiryReported = false;
        var uploaded = false;
        var puts = 0;
        List<int>? ciphertext;
        final client = MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), false);
          if (request.method == 'PUT') {
            puts++;
            expect(
              request.headers['x-amz-meta-upload-session'],
              'session-fixture',
            );
            ciphertext = request.bodyBytes;
            return http.Response('', 200, headers: {'etag': 'etag'});
          }
          expect(request.body, isNot(contains('private-file.txt')));
          final op = request.url.path.split('/capability/').last;
          final body = jsonDecode(request.body) as Map;
          if (op == 'authorize') {
            clientIds.add(body['clientUploadId'] as String);
            if (lost == 'expired' && lostResponse && !expiryReported) {
              expiryReported = true;
              return http.Response('{"code":"upload_expired"}', 410);
            }
          }
          if (op == 'uploads/complete') uploaded = true;
          if ((op == lost || (lost == 'expired' && op == 'uploads/status')) &&
              !lostResponse) {
            lostResponse = true;
            return http.Response('{}', 503);
          }
          return http.Response(
            jsonEncode(switch (op) {
              'authorize' => {
                'sessionId': 'session-fixture',
                'objectKey': 'opaque-object',
                'uploadId': 'upload-fixture',
              },
              'uploads/status' => {
                'status': uploaded ? 'uploaded' : 'uploading',
                'parts': [],
              },
              'uploads/urls' => {
                'parts': [
                  {
                    'url': 'https://storage.test/object',
                    'headers': {'x-amz-meta-upload-session': 'session-fixture'},
                  },
                ],
              },
              _ => {'ok': true},
            }),
            op == 'complete' ? 201 : 200,
          );
        });
        final plain = List<int>.generate(100000, (i) => i % 251);
        final key = SecretKey(List.filled(32, 7));
        Future<void> upload() => uploadResumableFileRequest(
          api: FileRequestSessionApi(
            client: client,
            baseUri: Uri.parse('https://api.test/'),
            requestToken: 'capability',
          ),
          coordinator: UploadCoordinator(),
          journal: journal,
          key: key,
          name: 'private-file.txt',
          contentType: 'text/plain',
          length: plain.length,
          openRead: () => Stream.value(plain),
        );
        await expectLater(upload(), throwsA(isA<PublicTransferException>()));
        final oldNonce = journal.entries.single.uploadCheckpoint?['nonce'];
        journal.dispose();
        journal = await openJournal();
        await upload();
        expect(clientIds.toSet().length, lost == 'expired' ? 2 : 1);
        expect(puts, 1);
        expect(
          journal.entries.where(
            (entry) => entry.state == TransferJournalState.completed,
          ),
          hasLength(1),
        );
        final bytes = ciphertext!;
        if (lost == 'expired') {
          expect(
            journal.entries.where(
              (entry) => entry.state == TransferJournalState.canceled,
            ),
            hasLength(1),
          );
          expect(base64Encode(bytes.sublist(0, 16)), isNot(oldNonce));
        }
        final algorithm = AesCtr.with256bits(macAlgorithm: Hmac.sha256());
        expect(
          await algorithm.decrypt(
            SecretBox(
              bytes.sublist(16, bytes.length - 32),
              nonce: bytes.sublist(0, 16),
              mac: Mac(bytes.sublist(bytes.length - 32)),
            ),
            secretKey: key,
          ),
          plain,
        );
        journal.dispose();
        client.close();
      },
    );
  }
}
