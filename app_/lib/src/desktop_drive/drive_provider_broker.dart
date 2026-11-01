import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'drive_provider_protocol.dart';

/// Per-session authenticated loopback transport for OS providers. It is never
/// published on a network interface, and does not accept browser requests.
/// The token is random, ephemeral and unrelated to any cloud credential.
class DriveProviderBroker {
  DriveProviderBroker(this.backend);
  final DriveProviderBackend backend;
  static const maximumFileBytes = 64 * 1024 * 1024;
  static const maximumMetadataBytes = 64 * 1024;
  HttpServer? _server;
  String? _token;
  int _generation = 0;
  int _active = 0;
  bool _started = false;
  final _responses = <HttpResponse>{};

  Future<({int port, String token})> start() async {
    if (_started) throw StateError('Provider already started.');
    _started = true;
    final generation = _generation;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (generation != _generation) {
      await server.close(force: true);
      throw StateError('Provider stopped.');
    }
    server.idleTimeout = const Duration(seconds: 30);
    _server = server;
    _token = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    server.listen(
      (request) => unawaited(_handle(request).catchError((Object _) {})),
      onError: (_) {},
    );
    return (port: server.port, token: _token!);
  }

  Future<void> stop() async {
    _generation++;
    backend.invalidate();
    _token = null;
    final server = _server;
    _server = null;
    // Force-close connections so queued native completions cannot receive
    // a response after logout/account switching.
    await server?.close(force: true);
    _responses.clear();
  }

  bool _authorized(HttpRequest request) {
    final expected = _token;
    final supplied = request.headers.value(HttpHeaders.authorizationHeader);
    if (expected == null ||
        supplied == null ||
        request.headers.value('host') != '127.0.0.1:${_server?.port}' ||
        request.headers.value('origin') != null ||
        request.headers.value('sec-fetch-site') != null ||
        request.headers.value('forwarded') != null ||
        request.headers.value('x-forwarded-host') != null ||
        request.connectionInfo?.remoteAddress.isLoopback != true) {
      return false;
    }
    final wanted = 'Bearer $expected';
    if (supplied.length != wanted.length) return false;
    var difference = 0;
    for (var i = 0; i < wanted.length; i++) {
      difference |= wanted.codeUnitAt(i) ^ supplied.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final generation = _generation;
    var admitted = false;
    final plaintextBuffers = <Uint8List>[];
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    try {
      if (!_authorized(request)) throw const ProviderFailure('unauthorized');
      if (request.method != 'POST' ||
          request.uri.query.isNotEmpty ||
          request.headers.contentType?.mimeType != 'application/json') {
        throw const ProviderFailure('invalid');
      }
      if (_active >= 4) throw const ProviderFailure('busy');
      _active++;
      admitted = true;
      _responses.add(response);
      final body = BytesBuilder(copy: false);
      // Content is base64 in the bounded protocol; uploads over the limit are
      // rejected explicitly and remain local, never truncated or marked synced.
      final limit =
          request.uri.path == '/v1/create' || request.uri.path == '/v1/update'
          ? ((maximumFileBytes * 4) ~/ 3) + maximumMetadataBytes
          : maximumMetadataBytes;
      if (request.contentLength > limit) {
        throw const ProviderFailure('too-large');
      }
      await for (final chunk in request.timeout(const Duration(seconds: 30))) {
        if (body.length + chunk.length > limit) {
          throw const ProviderFailure('too-large');
        }
        body.add(chunk);
      }
      final decoded = jsonDecode(utf8.decode(body.takeBytes()));
      if (decoded is! Map<String, dynamic>) {
        throw const ProviderFailure('invalid');
      }
      final data = decoded;
      if (generation != _generation || _token == null) {
        throw const ProviderFailure('unauthorized');
      }
      String requiredString(String key) {
        final value = data[key];
        if (value is! String || value.isEmpty || value.length > 2048) {
          throw const ProviderFailure('invalid');
        }
        return value;
      }

      String? optionalString(String key) =>
          data.containsKey(key) ? requiredString(key) : null;
      Uint8List? contents() {
        if (!data.containsKey('contents')) return null;
        final value = data['contents'];
        if (value is! String) throw const ProviderFailure('invalid');
        final result = base64Decode(value);
        plaintextBuffers.add(result);
        if (result.length > maximumFileBytes) {
          throw const ProviderFailure('too-large');
        }
        return result;
      }

      void allow(Set<String> fields) {
        if (data.keys.any((key) => !fields.contains(key))) {
          throw const ProviderFailure('invalid');
        }
      }

      Object? result;
      Uint8List? bytes;
      switch (request.uri.path) {
        case '/v1/list':
          allow({'parentId'});
          result = {
            'items': (await backend.list(
              requiredString('parentId'),
            )).map((item) => item.toJson()).toList(),
          };
        case '/v1/item':
          allow({'id'});
          result = (await backend.item(requiredString('id'))).toJson();
        case '/v1/read':
          allow({'id', 'version'});
          bytes = await backend.read(
            requiredString('id'),
            requiredString('version'),
          );
          plaintextBuffers.add(bytes);
          if (bytes.length > maximumFileBytes) {
            throw const ProviderFailure('too-large');
          }
        case '/v1/create':
          allow({'parentId', 'name', 'directory', 'contents', 'requestId'});
          if (data['directory'] is! bool) {
            throw const ProviderFailure('invalid');
          }
          final requestId = optionalString('requestId');
          if (requestId != null) {
            if (backend is! RecoverableDriveCreates) {
              throw const ProviderFailure('unavailable');
            }
            result =
                (await (backend as RecoverableDriveCreates).createWithRequestId(
                  requestId,
                  requiredString('parentId'),
                  requiredString('name'),
                  data['directory'] as bool,
                  contents() ?? Uint8List(0),
                )).toJson();
          } else {
            result = (await backend.create(
              requiredString('parentId'),
              requiredString('name'),
              data['directory'] as bool,
              contents() ?? Uint8List(0),
            )).toJson();
          }
        case '/v1/update':
          allow({'id', 'version', 'parentId', 'name', 'contents'});
          result = (await backend.update(
            requiredString('id'),
            requiredString('version'),
            optionalString('parentId'),
            optionalString('name'),
            contents(),
          )).toJson();
        case '/v1/recycle':
          allow({'id', 'version'});
          await backend.recycle(
            requiredString('id'),
            requiredString('version'),
          );
          result = {'ok': true};
        default:
          throw const ProviderFailure('invalid');
      }
      if (generation != _generation || _token == null) {
        throw const ProviderFailure('unauthorized');
      }
      if (bytes != null) {
        response.headers.contentType = ContentType.binary;
        response.contentLength = bytes.length;
        response.add(bytes);
      } else {
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(result));
      }
      await response.flush();
    } catch (error) {
      final code = error is ProviderFailure
          ? error.code
          : error is FormatException
          ? 'invalid'
          : 'unavailable';
      response.statusCode = switch (code) {
        'unauthorized' => 401,
        'not-found' => 404,
        'conflict' => 409,
        'invalid' => 400,
        'too-large' => 413,
        'read-only' => 403,
        'busy' => 429,
        _ => 503,
      };
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'error': switch (response.statusCode) {
            401 => 'unauthorized',
            404 => 'not-found',
            409 => 'conflict',
            400 => 'invalid',
            413 => 'too-large',
            403 => 'read-only',
            429 => 'busy',
            _ => 'unavailable',
          },
        }),
      );
    } finally {
      for (final bytes in plaintextBuffers) {
        bytes.fillRange(0, bytes.length, 0);
      }
      if (admitted) _active--;
      _responses.remove(response);
      try {
        await response.close();
      } catch (_) {
        /* Client canceled. */
      }
    }
  }
}
