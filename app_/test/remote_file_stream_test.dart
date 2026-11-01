import 'dart:async';
import 'dart:io';
import 'package:cloud_storage/src/home/migration/remote_file_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  for (final limit in [3, 4]) {
    test('unknown-size stream enforces maximum $limit', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = http.Client();
      addTearDown(() async {
        client.close();
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.add([1, 2, 3, 4]);
        await request.response.close();
      });
      final result = readRemoteFileStream(
        client: client,
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:${server.port}/export'),
        headers: {},
        expectedLength: null,
        maximumLength: limit,
      ).fold<int>(0, (count, bytes) => count + bytes.length);
      if (limit == 3) {
        await expectLater(result, throwsStateError);
      } else {
        expect(await result, 4);
      }
    });
  }
  test('provider bytes arrive before the download finishes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = http.Client();
    final finish = Completer<void>();
    addTearDown(() async {
      if (!finish.isCompleted) finish.complete();
      client.close();
      await server.close(force: true);
    });
    server.listen((request) async {
      request.response.bufferOutput = false;
      request.response.contentLength = 131072;
      request.response.add(List.filled(65536, 1));
      await request.response.flush();
      await finish.future;
      request.response.add(List.filled(65536, 2));
      await request.response.close();
    });
    final iterator = StreamIterator(
      readRemoteFileStream(
        client: client,
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:${server.port}/file'),
        headers: {},
        expectedLength: 131072,
      ),
    );
    expect(await iterator.moveNext().timeout(const Duration(seconds: 2)), true);
    expect(iterator.current, isNotEmpty);
    expect(iterator.current.every((byte) => byte == 1), true);
    var received = iterator.current.length;
    finish.complete();
    while (await iterator.moveNext()) {
      received += iterator.current.length;
    }
    expect(received, 131072);
  });

  for (final declaredLength in [true, false]) {
    test(
      'rejects ${declaredLength ? 'declared' : 'actual'} changed length',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = http.Client();
        addTearDown(() async {
          client.close();
          await server.close(force: true);
        });
        server.listen((request) async {
          if (declaredLength) request.response.contentLength = 2;
          request.response.add([1, 2]);
          await request.response.close();
        });
        await expectLater(
          readRemoteFileStream(
            client: client,
            method: 'GET',
            uri: Uri.parse('http://127.0.0.1:${server.port}/file'),
            headers: {},
            expectedLength: 4,
          ).drain<void>(),
          throwsStateError,
        );
      },
    );
  }
}
