import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/agent_access/local_access_server.dart';
import 'package:cloud_storage/src/desktop_drive/drive_provider_protocol.dart';

class MemoryBackend implements DriveProviderBackend {
  bool revoked = false, failIntegrity = false, moved = false;
  int writes = 0, reads = 0;
  int fileSize = 5;
  Completer<Uint8List>? pending;
  Completer<ProviderItem>? pendingItem;
  int itemCalls = 0;
  final root = ProviderItem(
    id: 'd:allowed',
    parentId: 'root',
    name: 'Allowed',
    version: '1',
    directory: true,
    size: 0,
  );
  ProviderItem get file => ProviderItem(
    id: 'f:file',
    parentId: moved ? 'd:outside' : root.id,
    name: 'hello.txt',
    version: '1',
    directory: false,
    size: fileSize,
  );
  void check() {
    if (revoked) throw const ProviderFailure('unauthorized');
  }

  @override
  void invalidate() => revoked = true;
  @override
  Future<ProviderItem> item(String id) async {
    check();
    itemCalls++;
    if (pendingItem != null) return pendingItem!.future;
    return id == root.id ? root : file;
  }

  @override
  Future<List<ProviderItem>> list(String parentId) async {
    check();
    return parentId == root.id && !moved ? [file] : [];
  }

  @override
  Future<Uint8List> read(String id, String version) async {
    check();
    reads++;
    if (failIntegrity) throw StateError('PRIVATE integrity data');
    return pending?.future ?? Uint8List.fromList(utf8.encode('hello'));
  }

  @override
  Future<ProviderItem> create(
    String parentId,
    String name,
    bool directory,
    Uint8List contents,
  ) async {
    writes++;
    return file;
  }

  @override
  Future<ProviderItem> update(
    String id,
    String version,
    String? parentId,
    String? name,
    Uint8List? contents,
  ) async {
    writes++;
    return file;
  }

  @override
  Future<void> recycle(String id, String version) async {
    writes++;
  }
}

class MovingFolderBackend extends MemoryBackend {
  final listing = Completer<List<ProviderItem>>();
  bool listingStarted = false, folderMoved = false;
  final folder = ProviderItem(
    id: 'd:nested',
    parentId: 'd:allowed',
    name: 'nested',
    version: '1',
    directory: true,
    size: 0,
  );
  @override
  Future<List<ProviderItem>> list(String parentId) async {
    check();
    if (parentId == root.id) return folderMoved ? [] : [folder];
    listingStarted = true;
    return listing.future;
  }
}

void main() {
  test(
    'cannot start after revocation while folder lookup is pending',
    () async {
      final backend = MemoryBackend();
      backend.pendingItem = Completer<ProviderItem>();
      final server = LocalAccessServer(
        backend,
        backend.root.id,
        LocalAccessProtocol.mcp,
      );
      final started = server.start();
      final rejected = expectLater(started, throwsStateError);
      await server.stop();
      backend.pendingItem!.complete(backend.root);
      await rejected;
      await expectLater(server.start(), throwsStateError);
    },
  );
  for (final protocol in LocalAccessProtocol.values) {
    test('${protocol.name} withholds listing of a moved folder', () async {
      final backend = MovingFolderBackend();
      final server = LocalAccessServer(backend, backend.root.id, protocol);
      final endpoint = await server.start();
      final client = HttpClient();
      try {
        final req = await client.openUrl(
          protocol == LocalAccessProtocol.mcp ? 'POST' : 'PROPFIND',
          Uri.parse(
            protocol == LocalAccessProtocol.mcp
                ? endpoint.url
                : '${endpoint.url}nested/',
          ),
        );
        req.headers.set('Authorization', 'Bearer ${endpoint.token}');
        req.headers.set('Depth', '1');
        if (protocol == LocalAccessProtocol.mcp) {
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'tools/call',
              'params': {
                'name': 'list_files',
                'arguments': {'path': '/nested'},
              },
            }),
          );
        }
        final response = req.close().then((r) => utf8.decoder.bind(r).join());
        while (!backend.listingStarted) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        backend.folderMoved = true;
        backend.listing.complete([
          ProviderItem(
            id: 'f:secret',
            parentId: 'd:nested',
            name: 'PRIVATE.txt',
            version: '1',
            directory: false,
            size: 1,
          ),
        ]);
        expect(await response, isNot(contains('PRIVATE')));
      } finally {
        client.close(force: true);
        await server.stop();
      }
    });
    group(protocol.name, () {
      late MemoryBackend backend;
      late LocalAccessServer server;
      late ({String url, String token}) endpoint;
      late HttpClient client;
      setUp(() async {
        backend = MemoryBackend();
        server = LocalAccessServer(backend, backend.root.id, protocol);
        endpoint = await server.start();
        client = HttpClient();
      });
      tearDown(() async {
        client.close(force: true);
        await server.stop();
      });
      Future<({int status, String body})> request(
        String method, {
        String? path,
        Object? body,
        Map<String, String> headers = const {},
      }) async {
        final uri = Uri.parse(endpoint.url);
        final req = await client.openUrl(
          method,
          path == null ? uri : uri.replace(path: path),
        );
        req.headers.set('Authorization', 'Bearer ${endpoint.token}');
        req.headers.set('Accept', 'application/json, text/event-stream');
        req.headers.set(
          'MCP-Protocol-Version',
          LocalAccessServer.protocolVersion,
        );
        for (final e in headers.entries) {
          req.headers.set(e.key, e.value);
        }
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(body is String ? body : jsonEncode(body));
        }
        final response = await req.close();
        return (
          status: response.statusCode,
          body: await utf8.decoder.bind(response).join(),
        );
      }

      Object call(String name, String path) => {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': name,
          'arguments': {'path': path},
        },
      };
      Future<({int status, String body})> read() =>
          protocol == LocalAccessProtocol.mcp
          ? request('POST', body: call('read_text', '/hello.txt'))
          : request('GET', path: '/dav/hello.txt');
      test('reads authenticated contents', () async {
        final r = await read();
        expect(r.status, 200);
        expect(r.body, contains('hello'));
      });
      test('denies backend authorization revoked before read', () async {
        backend.revoked = true;
        final r = await read();
        expect(r.body, isNot(contains('hello')));
        expect(backend.reads, 0);
      });
      test('rejects large files before download', () async {
        backend.fileSize = LocalAccessServer.maxBytes + 1;
        expect((await read()).body, isNot(contains('hello')));
        expect(backend.reads, 0);
      });
      test('rejects the other protocol endpoint', () async {
        final r = await request(
          'POST',
          path: protocol == LocalAccessProtocol.mcp ? '/dav/' : '/mcp',
          body: call('read_text', '/hello.txt'),
        );
        expect(r.status, 404);
        expect(backend.reads, 0);
      });
      test('bounds request size and request rate', () async {
        // An oversized unread body may close the socket before HTTP headers
        // are delivered. Both outcomes fail closed without draining attacker data.
        final oversized =
            await request(
              protocol == LocalAccessProtocol.mcp ? 'POST' : 'PROPFIND',
              headers: {'Depth': '0'},
              body: 'x' * 16385,
            ).then(
              (r) => r.status,
              onError: (Object e) {
                if (e is HttpException || e is SocketException) return 0;
                throw e;
              },
            );
        expect([0, 400], contains(oversized));
        for (var i = 0; i < 120; i++) {
          await request('GET');
        }
        expect((await request('GET')).status, 429);
        expect(backend.reads, 0);
      });
      test('rejects missing capability, origin and DNS rebinding', () async {
        for (final headers in [
          {'Authorization': 'Bearer wrong'},
          {'Origin': 'https://evil.example'},
          {'Host': 'evil.example'},
          {'Sec-Fetch-Site': 'same-origin'},
        ]) {
          final r = await request(
            'POST',
            body: call('read_text', '/hello.txt'),
            headers: headers,
          );
          expect([401, 403], contains(r.status));
          expect(r.body, isNot(contains('hello')));
        }
        expect(backend.reads, 0);
      });
      test('does not expose mutation methods', () async {
        final r = protocol == LocalAccessProtocol.mcp
            ? await request('POST', body: call('delete_file', '/hello.txt'))
            : await request('DELETE', path: '/dav/hello.txt');
        expect(backend.writes, 0);
        expect(r.body, isNot(contains('hello')));
        if (protocol == LocalAccessProtocol.webdav) expect(r.status, 405);
      });
      test('withholds contents after integrity failure', () async {
        backend.failIntegrity = true;
        final r = await read();
        expect(r.body, isNot(contains('hello')));
        expect(r.body, isNot(contains('PRIVATE')));
      });
      test('withholds contents moved outside scope during read', () async {
        backend.pending = Completer<Uint8List>();
        final response = read();
        while (backend.reads == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        backend.moved = true;
        backend.pending!.complete(Uint8List.fromList(utf8.encode('hello')));
        expect((await response).body, isNot(contains('hello')));
      });
      test('revokes in-flight response', () async {
        backend.pending = Completer<Uint8List>();
        final response = read().then((r) => r.body, onError: (_) => 'closed');
        while (backend.reads == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await server.stop();
        backend.pending!.complete(Uint8List.fromList(utf8.encode('hello')));
        expect(await response, isNot(contains('hello')));
      });
      if (protocol == LocalAccessProtocol.mcp) {
        test('MCP initialization and tool discovery', () async {
          for (final method in ['initialize', 'tools/list', 'ping']) {
            final r = await request(
              'POST',
              body: {'jsonrpc': '2.0', 'id': 7, 'method': method, 'params': {}},
            );
            expect(r.status, 200);
            expect(jsonDecode(r.body)['id'], 7);
          }
          expect(
            (await request(
              'POST',
              body: {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            )).status,
            202,
          );
          expect((await request('GET')).status, 405);
        });
        test('rejects traversal and unadvertised arguments', () async {
          for (final path in [
            '/../hello.txt',
            '/%2e%2e/hello.txt',
            '/d:outside/hello.txt',
          ]) {
            final r = await request('POST', body: call('read_text', path));
            expect(jsonDecode(r.body)['result']['isError'], true);
          }
          expect(backend.reads, 0);
        });
      } else {
        test('WebDAV rejects writes and traversal', () async {
          for (final method in [
            'PUT',
            'MKCOL',
            'MOVE',
            'COPY',
            'PROPPATCH',
            'LOCK',
            'UNLOCK',
          ]) {
            expect((await request(method, path: '/dav/hello.txt')).status, 405);
          }
          final traversal = await request('GET', path: '/dav/%2e%2e/hello.txt');
          expect(traversal.body, isNot(contains('hello')));
          expect(backend.reads, 0);
          expect(backend.writes, 0);
        });
        test(
          'WebDAV ranges use authenticated contents and respect validators',
          () async {
            for (final range in [
              'bytes=0-1',
              'bytes=-2',
              'bytes=3-',
              'bytes=0-99',
            ]) {
              final r = await request(
                'GET',
                path: '/dav/hello.txt',
                headers: {'Range': range},
              );
              expect(r.status, 206);
              expect(
                r.body,
                {
                  'bytes=0-1': 'he',
                  'bytes=-2': 'lo',
                  'bytes=3-': 'lo',
                  'bytes=0-99': 'hello',
                }[range],
              );
            }
            final full = await request(
              'GET',
              path: '/dav/hello.txt',
              headers: {'Range': 'bytes=0-1', 'If-Range': '"old"'},
            );
            expect(full.status, 200);
            expect(full.body, 'hello');
            final count = backend.reads;
            for (final range in [
              'bytes=8-9',
              'bytes=3-1',
              'bytes=-0',
              'bytes=0-1,3-4',
            ]) {
              expect(
                (await request(
                  'GET',
                  path: '/dav/hello.txt',
                  headers: {'Range': range},
                )).status,
                416,
              );
            }
            expect(backend.reads, count);
            expect(
              (await request(
                'GET',
                path: '/dav/hello.txt',
                headers: {'If-None-Match': 'W/"MQ=="'},
              )).status,
              304,
            );
            expect(
              (await request(
                'GET',
                path: '/dav/hello.txt',
                headers: {'If-Match': '"old"'},
              )).status,
              412,
            );
            expect(backend.reads, count);
            backend.failIntegrity = true;
            final failed = await request(
              'GET',
              path: '/dav/hello.txt',
              headers: {'Range': 'bytes=0-1'},
            );
            expect(failed.status, 503);
            expect(failed.body, isEmpty);
          },
        );
        test('WebDAV Basic authentication and finite-depth XML', () async {
          final r = await request(
            'PROPFIND',
            headers: {
              'Depth': '1',
              'Authorization':
                  'Basic ${base64Encode(utf8.encode('ronikcloud:${endpoint.token}'))}',
            },
          );
          expect(r.status, 207);
          expect(r.body, contains('/dav/hello.txt'));
          expect(
            (await request('PROPFIND', headers: {'Depth': 'infinity'})).status,
            403,
          );
        });
        test('XML entities rejected and unknown properties reported', () async {
          final r = await request(
            'PROPFIND',
            headers: {'Depth': '0'},
            body:
                '<!DOCTYPE x [<!ENTITY x SYSTEM "file:///secret">]><propfind xmlns="DAV:"><allprop/></propfind>',
          );
          expect(r.status, 400);
          final p = await request(
            'PROPFIND',
            headers: {'Depth': '0'},
            body:
                '<propfind xmlns="DAV:"><prop><displayname/><unknown/></prop></propfind>',
          );
          expect(p.status, 207);
          expect(p.body, contains('404 Not Found'));
          expect(p.body, contains('Shared folder'));
        });
      }
    });
  }
}
