import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/desktop_drive/drive_provider_broker.dart';
import 'package:cloud_storage/src/desktop_drive/drive_provider_protocol.dart';

class TestBackend implements DriveProviderBackend {
  bool invalidated = false;
  int calls = 0;
  Completer<Uint8List>? pending;
  final entry = ProviderItem(
    id: 'f:test',
    parentId: 'root',
    name: 'Test.txt',
    version: '1',
    directory: false,
    size: 3,
  );
  @override
  void invalidate() {
    invalidated = true;
  }

  @override
  Future<List<ProviderItem>> list(String parentId) async {
    calls++;
    return [entry];
  }

  @override
  Future<ProviderItem> item(String id) async => entry;
  @override
  Future<Uint8List> read(String id, String version) async {
    calls++;
    if (version != '1') throw const ProviderFailure('conflict');
    return pending?.future ?? Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<ProviderItem> create(
    String parentId,
    String name,
    bool directory,
    Uint8List contents,
  ) async => entry;
  @override
  Future<ProviderItem> update(
    String id,
    String version,
    String? parentId,
    String? name,
    Uint8List? contents,
  ) async => entry;
  @override
  Future<void> recycle(String id, String version) async {
    throw StateError('SECRET object path password');
  }
}

void main() {
  late TestBackend backend;
  late DriveProviderBroker broker;
  late ({int port, String token}) endpoint;
  late HttpClient client;
  setUp(() async {
    backend = TestBackend();
    broker = DriveProviderBroker(backend);
    endpoint = await broker.start();
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await broker.stop();
  });
  Future<({int status, String body})> request(
    String path,
    Map<String, Object> body, {
    String? token,
    String? origin,
  }) async {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${endpoint.port}/v1/$path'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('Authorization', 'Bearer ${token ?? endpoint.token}');
    if (origin != null) request.headers.set('Origin', origin);
    request.write(jsonEncode(body));
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  }

  test('authorized native request enumerates metadata', () async {
    final result = await request('list', {'parentId': 'root'});
    expect(result.status, 200);
    expect(result.body, contains('Test.txt'));
  });
  test('wrong token and browser origin cannot reach the backend', () async {
    expect(
      (await request('list', {'parentId': 'root'}, token: 'wrong')).status,
      401,
    );
    expect(
      (await request('list', {
        'parentId': 'root',
      }, origin: 'https://example.com')).status,
      401,
    );
    expect(backend.calls, 0);
  });
  test(
    'request cannot inject object keys, file paths or arbitrary operations',
    () async {
      expect(
        (await request('read', {
          'id': 'f:test',
          'version': '1',
          'objectKey': 'secret',
        })).status,
        400,
      );
      expect((await request('../credentials', {})).status, 400);
      expect(backend.calls, 0);
    },
  );
  test(
    'stale version is a conflict and internal errors are redacted',
    () async {
      expect(
        (await request('read', {'id': 'f:test', 'version': 'old'})).status,
        409,
      );
      final result = await request('recycle', {'id': 'f:test', 'version': '1'});
      expect(result.status, 503);
      expect(result.body, '{"error":"unavailable"}');
    },
  );
  test('shutdown invalidates an in-flight read before disclosure', () async {
    backend.pending = Completer<Uint8List>();
    final pending = request('read', {'id': 'f:test', 'version': '1'});
    final outcome = pending.then<Object>(
      (result) => result,
      onError: (Object error) => error,
    );
    while (backend.calls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await broker.stop();
    expect(backend.invalidated, true);
    backend.pending!.complete(Uint8List.fromList(utf8.encode('private-body')));
    final result = await outcome;
    if (result is ({int status, String body})) {
      expect(result.status, isNot(200));
      expect(result.body, isNot(contains('private-body')));
    } else {
      expect(result, isA<Exception>());
    }
  });
}
