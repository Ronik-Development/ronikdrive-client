import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_storage/src/security/encryption_service.dart';
import 'package:cloud_storage/src/share/password_share_page.dart';
import 'package:cloud_storage/src/share/share_link_security.dart';
import 'package:cloud_storage/src/share/share_metadata_envelope.dart';
import 'package:cloud_storage/src/share/share_link_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Uint8List salt;
  late String envelope;
  late SecretKey correctKey;

  setUpAll(() async {
    salt = Uint8List.fromList(List<int>.generate(16, (index) => index + 1));
    correctKey = SecretKey(
      Uint8List.fromList(List<int>.generate(32, (index) => index)),
    );
    envelope = await ShareMetadataEnvelope.seal(
      fileName: 'confidential-board-report.pdf',
      contentType: 'application/pdf',
      key: correctKey,
    );
  });

  testWidgets(
    'wrong password is rejected from protected metadata before file egress',
    (tester) async {
      var metadataRequests = 0;
      var downloadRequests = 0;
      final wrongKey = SecretKey(Uint8List(32)..fillRange(0, 32, 77));
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/metadata')) {
          metadataRequests += 1;
          return http.Response(
            jsonEncode(<String, Object>{
              'ok': true,
              'saltBase64': base64Encode(salt),
              'kdf': 'pbkdf2-hmac-sha256',
              'iterations': EncryptionService.pbkdf2Iterations,
              'algorithm': 'aes-ctr-hmac-sha256',
              'accessMode': 'password',
              'metadataFormat': shareMetadataEnvelopeFormat,
              'encryptedMetadataBase64': envelope,
              'expiresAt': '2099-08-09T12:00:00.000Z',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/download')) {
          downloadRequests += 1;
          return http.Response('{}', 500);
        }
        return http.Response('{}', 404);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: PasswordSharePage(
            token: 'share-token',
            apiBaseUri: Uri.parse('https://api.example.test/'),
            httpClient: client,
            keyDeriver: ({required password, required salt}) async => wrongKey,
          ),
        ),
      );
      for (var attempt = 0; attempt < 20; attempt += 1) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Password-protected file').evaluate().isNotEmpty) {
          break;
        }
      }

      expect(metadataRequests, 1);
      expect(downloadRequests, 0);
      expect(find.text('Password-protected file'), findsOneWidget);
      expect(find.textContaining('confidential-board-report'), findsNothing);

      await tester.enterText(find.byType(TextField), 'wrong-password');
      await tester.tap(find.text('Decrypt and download'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(downloadRequests, 0);
      final visibleTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList(growable: false);
      expect(
        visibleTexts,
        contains('That password could not decrypt this file.'),
      );
      expect(find.textContaining('confidential-board-report'), findsNothing);
    },
  );

  testWidgets('correct password sends a token-scoped download proof', (
    tester,
  ) async {
    const token = 'proof-protected-share';
    final expectedProof = await deriveShareDownloadProof(
      shareKey: correctKey,
      token: token,
    );
    Map<String, dynamic>? downloadBody;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/metadata')) {
        return http.Response(
          jsonEncode(<String, Object>{
            'ok': true,
            'saltBase64': base64Encode(salt),
            'kdf': 'pbkdf2-hmac-sha256',
            'iterations': EncryptionService.pbkdf2Iterations,
            'algorithm': 'aes-ctr-hmac-sha256',
            'accessMode': 'password',
            'metadataFormat': shareMetadataEnvelopeFormat,
            'encryptedMetadataBase64': envelope,
            'downloadProofFormat': shareDownloadProofFormat,
            'expiresAt': '2099-08-09T12:00:00.000Z',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/download')) {
        downloadBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, Object>{
            'ok': true,
            'bytesBase64': base64Encode(const <int>[1, 2, 3]),
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PasswordSharePage(
          token: token,
          apiBaseUri: Uri.parse('https://api.example.test/'),
          httpClient: client,
          keyDeriver: ({required password, required salt}) async => correctKey,
        ),
      ),
    );
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Password-protected file').evaluate().isNotEmpty) {
        break;
      }
    }

    await tester.enterText(find.byType(TextField), 'correct-password');
    await tester.tap(find.text('Decrypt and download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(downloadBody?['token'], token);
    expect(downloadBody?['accessProofBase64'], expectedProof);
  });

  testWidgets('provider error bodies are hidden and metadata load can retry', (
    tester,
  ) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      return http.Response(
        jsonEncode(<String, String>{
          'error':
              r'user@example.test C:\Users\person\board-plan.pdf token=secret',
        }),
        500,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PasswordSharePage(
          token: 'share-token',
          apiBaseUri: Uri.parse('https://api.example.test/'),
          httpClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(find.text('Retry shared file'), findsOneWidget);
    expect(find.textContaining('user@example.test'), findsNothing);
    expect(find.textContaining('board-plan.pdf'), findsNothing);
    expect(find.textContaining('token=secret'), findsNothing);

    await tester.tap(find.text('Retry shared file'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'complete private link decrypts locally and waits for manual download without transmitting its key',
    (tester) async {
      const token = 'synthetic-password-free-share';
      final link = await ShareLinkCrypto.completeLink(
        Uri.parse('https://share.example.test/share/$token'),
        correctKey,
      );
      final requests = <http.Request>[];
      final plaintext = Uint8List.fromList(
        utf8.encode('synthetic encrypted share contents'),
      );
      final encrypted = await EncryptionService.instance.encryptData(
        plaintext,
        correctKey,
      );
      List<int>? saved;
      String? savedName;
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/metadata')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'kdf': 'none',
              'iterations': 0,
              'algorithm': 'aes-ctr-hmac-sha256',
              'accessMode': 'link',
              'metadataFormat': shareMetadataEnvelopeFormat,
              'encryptedMetadataBase64': envelope,
              'downloadProofFormat': shareDownloadProofFormat,
              'expiresAt': '2099-08-09T12:00:00.000Z',
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'ok': true, 'bytesBase64': base64Encode(encrypted)}),
          200,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PasswordSharePage(
            token: token,
            linkFragment: link.fragment,
            apiBaseUri: Uri.parse('https://api.example.test/'),
            httpClient: client,
            fileSaver: (bytes, name) async {
              saved = bytes;
              savedName = name;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('confidential-board-report.pdf'), findsOneWidget);
      expect(requests, hasLength(1));
      expect(saved, isNull);
      await tester.tap(find.text('Decrypt and download'));
      await tester.pumpAndSettle();
      expect(saved, plaintext);
      expect(savedName, 'confidential-board-report.pdf');
      expect(requests, hasLength(2));
      final download = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(download.keys.toSet(), {'token', 'accessProofBase64'});
      expect(
        download['accessProofBase64'],
        await deriveShareDownloadProof(shareKey: correctKey, token: token),
      );
      for (final request in requests) {
        final captured = '${request.url}\n${request.headers}\n${request.body}';
        expect(captured, isNot(contains(link.fragment)));
        expect(captured, isNot(contains(link.fragment.substring(4))));
        expect(captured, isNot(contains('confidential-board-report')));
        expect(captured, isNot(contains('synthetic encrypted share contents')));
      }
    },
  );
  for (final (caseIndex, fragment) in [
    '',
    'key=invalid',
    'key=${'A' * 43}',
  ].indexed) {
    testWidgets(
      'missing, malformed or wrong link key cannot fetch encrypted payload case $caseIndex',
      (tester) async {
        var downloads = 0;
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/download')) downloads++;
          return http.Response(
            jsonEncode({
              'ok': true,
              'kdf': 'none',
              'iterations': 0,
              'algorithm': 'aes-ctr-hmac-sha256',
              'accessMode': 'link',
              'metadataFormat': shareMetadataEnvelopeFormat,
              'encryptedMetadataBase64': envelope,
              'downloadProofFormat': shareDownloadProofFormat,
              'expiresAt': '2099-08-09T12:00:00.000Z',
            }),
            200,
          );
        });
        await tester.pumpWidget(
          MaterialApp(
            home: PasswordSharePage(
              token: 'synthetic-share',
              linkFragment: fragment,
              apiBaseUri: Uri.parse('https://api.example.test/'),
              httpClient: client,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(downloads, 0);
        expect(find.text('Decrypt and download'), findsNothing);
        expect(find.textContaining('confidential-board-report'), findsNothing);
        expect(find.text('Retry shared file'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
