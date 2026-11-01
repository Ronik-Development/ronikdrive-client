import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_storage/src/share/file_request_metadata_envelope.dart';
import 'package:cloud_storage/src/share/file_request_upload_page.dart';

void main() {
  testWidgets('loads identity-free API metadata and decrypts title locally', (
    tester,
  ) async {
    final keyBytes = List<int>.generate(32, (index) => index + 3);
    final key = SecretKey(keyBytes);
    final encryptedTitle = await FileRequestMetadataEnvelope.sealTitle(
      title: 'Upload the signed agreement',
      key: key,
    );
    late http.Request observedRequest;
    final client = MockClient((request) async {
      observedRequest = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'privacyVersion': 2,
          'metadataFormat': fileRequestTitleMetadataFormat,
          'encryptedTitleBase64': encryptedTitle,
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(days: 2))
              .toIso8601String(),
          'maxFileBytes': 4096,
          'maxUploads': 3,
          'uploadCount': 0,
          'encryption': 'client-aes-ctr-hmac-sha256-v1',
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FileRequestUploadPage(
          token: 'request_token',
          apiBaseUri: Uri.parse('https://api.example.test/'),
          requestKeyBase64: base64Url.encode(keyBytes).replaceAll('=', ''),
          httpClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Upload the signed agreement'), findsOneWidget);
    expect(find.textContaining('encrypted locally'), findsOneWidget);
    expect(find.text('3 submissions remaining'), findsOneWidget);
    expect(find.textContaining('Available until around'), findsOneWidget);
    expect(
      observedRequest.url.toString(),
      'https://api.example.test/file-requests/request_token/metadata',
    );
    expect(observedRequest.method, 'POST');
    expect(observedRequest.body, '{}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing private fragment fails before metadata is requested', (
    tester,
  ) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FileRequestUploadPage(
          token: 'request_token',
          apiBaseUri: Uri.parse('https://api.example.test/'),
          requestKeyBase64: '',
          httpClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('missing its private encryption fragment'),
      findsOneWidget,
    );
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider error bodies are not rendered and load can retry', (
    tester,
  ) async {
    var calls = 0;
    final keyBytes = List<int>.generate(32, (index) => index + 7);
    final client = MockClient((request) async {
      calls += 1;
      return http.Response(
        jsonEncode(<String, String>{
          'detail':
              r'user@example.test C:\Users\person\private-photo.png token=secret',
        }),
        400,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FileRequestUploadPage(
          token: 'request_token',
          apiBaseUri: Uri.parse('https://api.example.test/'),
          requestKeyBase64: base64Url.encode(keyBytes).replaceAll('=', ''),
          httpClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be opened'), findsOneWidget);
    expect(find.text('Retry file request'), findsOneWidget);
    expect(find.textContaining('user@example.test'), findsNothing);
    expect(find.textContaining('private-photo.png'), findsNothing);
    expect(find.textContaining('token=secret'), findsNothing);

    await tester.tap(find.text('Retry file request'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temporarily reserved slots keep a safe retry path', (
    tester,
  ) async {
    final keyBytes = List<int>.generate(32, (index) => index + 9);
    final client = MockClient(
      (request) async => http.Response(
        r'{"detail":"user@example.test reserved private-photo.png"}',
        423,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FileRequestUploadPage(
          token: 'request_token',
          apiBaseUri: Uri.parse('https://api.example.test/'),
          requestKeyBase64: base64Url.encode(keyBytes).replaceAll('=', ''),
          httpClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('released automatically'), findsOneWidget);
    expect(find.text('Retry file request'), findsOneWidget);
    expect(find.textContaining('user@example.test'), findsNothing);
    expect(find.textContaining('private-photo.png'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown metadata format fails closed without legacy title', (
    tester,
  ) async {
    final keyBytes = List<int>.generate(32, (index) => index + 11);
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(<String, Object?>{
          'metadataFormat': 'future-or-provider-controlled-format',
          'title': 'private-acquisition-name',
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(days: 2))
              .toIso8601String(),
          'maxFileBytes': 4096,
          'maxUploads': 3,
          'uploadCount': 0,
        }),
        200,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FileRequestUploadPage(
          token: 'request_token',
          apiBaseUri: Uri.parse('https://api.example.test/'),
          requestKeyBase64: base64Url.encode(keyBytes).replaceAll('=', ''),
          httpClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('unsupported encryption metadata'),
      findsOneWidget,
    );
    expect(find.textContaining('private-acquisition-name'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
