import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_storage/src/storage/upload_coordinator.dart';
import 'package:cloud_storage/src/storage/upload_part_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('signed session metadata reaches the HTTP server as a header', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = http.Client();
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    final received = Completer<String?>();
    server.listen((request) async {
      received.complete(request.headers.value('x-amz-meta-upload-session'));
      await request.drain<void>();
      request.response.headers.set('etag', 'test-etag');
      await request.response.close();
    });
    expect(
      await putUploadPart(
        client: client,
        url: Uri.parse('http://127.0.0.1:${server.port}/object'),
        bytes: Uint8List.fromList([1, 2, 3]),
        abortSignal: Completer<void>().future,
        headers: {'x-amz-meta-upload-session': 'fixture-session'},
      ),
      'test-etag',
    );
    expect(await received.future, 'fixture-session');
  });
  for (final timeout in [false, true]) {
    test(
      'real HTTP ${timeout ? 'timeout' : 'cancellation'} aborts only its request',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = http.Client();
        addTearDown(() async {
          client.close();
          await server.close(force: true);
        });
        final received = Completer<void>();
        server.listen((request) async {
          await request.drain<void>();
          if (request.uri.path == '/blocked') {
            received.complete();
            // Deliberately never respond: only transport abort can finish this.
          } else {
            request.response.write('available');
            await request.response.close();
          }
        });
        final base = Uri.parse('http://127.0.0.1:${server.port}');
        final abort = Completer<void>();
        final pending = putUploadPart(
          client: client,
          url: base.resolve('/blocked'),
          bytes: Uint8List.fromList([1, 2, 3]),
          abortSignal: abort.future,
          timeout: timeout
              ? const Duration(milliseconds: 200)
              : const Duration(minutes: 1),
        );
        final result = expectLater(
          pending,
          throwsA(
            isA<UploadFailure>().having(
              (failure) => failure.code,
              'safe failure',
              timeout ? 'unavailable' : 'canceled',
            ),
          ),
        );
        await received.future;
        if (!timeout) abort.complete();
        await result.timeout(const Duration(seconds: 3));
        expect((await client.get(base.resolve('/other'))).body, 'available');
      },
    );
  }
}
