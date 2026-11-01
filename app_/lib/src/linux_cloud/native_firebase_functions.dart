import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import 'native_auth_session.dart';

class NativeFirebaseFunctions extends FirebaseFunctionsPlatform {
  NativeFirebaseFunctions({
    required this.sessionFor,
    FirebaseApp? app,
    String region = 'europe-west1',
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       super(app, region);
  final NativeAuthSession Function(String) sessionFor;
  final http.Client Function() _clientFactory;
  final _delegates = <String, NativeFirebaseFunctions>{};
  http.Client? _client;
  http.Client get client => _client ??= _clientFactory();
  NativeAuthSession get session => sessionFor(app!.name);

  @override
  FirebaseFunctionsPlatform delegateFor({
    FirebaseApp? app,
    required String region,
  }) {
    if (app == null || !RegExp(r'^[a-z]+-[a-z]+[0-9]{1,2}$').hasMatch(region)) {
      throw FirebaseFunctionsException(
        code: 'invalid-argument',
        message: 'Invalid native callable configuration.',
      );
    }
    return _delegates.putIfAbsent(
      '${app.name}|$region',
      () => NativeFirebaseFunctions(
        sessionFor: sessionFor,
        app: app,
        region: region,
        clientFactory: _clientFactory,
      ),
    );
  }

  @override
  HttpsCallablePlatform httpsCallable(
    String? origin,
    String name,
    HttpsCallableOptions options,
  ) => _NativeCallable(this, origin, name, options, null);
  @override
  HttpsCallablePlatform httpsCallableWithUri(
    String? origin,
    Uri uri,
    HttpsCallableOptions options,
  ) => _NativeCallable(this, origin, null, options, uri);

  void disposeApp(String name) {
    final keys = _delegates.entries
        .where((entry) => entry.value.app?.name == name)
        .map((entry) => entry.key)
        .toList();
    for (final key in keys) {
      _delegates.remove(key)?._client?.close();
    }
  }
}

class _NativeCallable extends HttpsCallablePlatform {
  _NativeCallable(
    super.functions,
    super.origin,
    super.name,
    super.options,
    super.uri,
  );
  NativeFirebaseFunctions get native => functions as NativeFirebaseFunctions;
  FirebaseFunctionsException _failure(String code) =>
      FirebaseFunctionsException(
        code: code,
        message: 'The cloud request could not be completed.',
      );

  Uri _endpoint() {
    final project = native.app!.options.projectId;
    final host = '${native.region}-$project.cloudfunctions.net';
    if (uri case final direct?) {
      if (origin != null ||
          direct.scheme != 'https' ||
          direct.host != host ||
          direct.userInfo.isNotEmpty ||
          direct.hasQuery ||
          direct.hasFragment ||
          direct.pathSegments.length != 1 ||
          direct.port != 443) {
        throw _failure('invalid-argument');
      }
      if (!RegExp(
        r'^[A-Za-z][A-Za-z0-9_-]{0,127}$',
      ).hasMatch(direct.pathSegments.single)) {
        throw _failure('invalid-argument');
      }
      return direct;
    }
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,127}$').hasMatch(name!)) {
      throw _failure('invalid-argument');
    }
    if (origin == null) return Uri.https(host, '/$name');
    final local = Uri.tryParse(origin!);
    if (native.session.transport.emulatorPort == null ||
        local == null ||
        local.scheme != 'http' ||
        !const {'127.0.0.1', 'localhost'}.contains(local.host) ||
        local.port != 5001 ||
        local.userInfo.isNotEmpty ||
        local.hasQuery ||
        local.hasFragment ||
        !const {'', '/'}.contains(local.path)) {
      throw _failure('invalid-argument');
    }
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: 5001,
      path: '/$project/${native.region}/$name',
    );
  }

  @override
  Future<dynamic> call([dynamic parameters]) async {
    final endpoint = _endpoint();
    if (options.limitedUseAppCheckToken) throw _failure('failed-precondition');
    if (options.webAbortSignal != null) throw _failure('invalid-argument');
    if (options.timeout <= Duration.zero ||
        options.timeout > const Duration(minutes: 10)) {
      throw _failure('invalid-argument');
    }
    final String body;
    try {
      body = jsonEncode({'data': _encode(parameters)});
    } catch (_) {
      throw _failure('invalid-argument');
    }
    final uid = native.session.currentIdentity?.uid;
    final token = uid == null
        ? null
        : await native.session.idToken(forUid: uid);
    if (uid != native.session.currentIdentity?.uid) throw _failure('cancelled');
    final abort = Completer<void>();
    final timer = Timer(options.timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    final request =
        http.AbortableRequest('POST', endpoint, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['Content-Type'] = 'application/json'
          ..body = body;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    try {
      return await (() async {
        final response = await native.client.send(request);
        final bytes = <int>[];
        await for (final part in response.stream) {
          if (bytes.length + part.length > 8 * 1024 * 1024) {
            if (!abort.isCompleted) abort.complete();
            throw _failure('resource-exhausted');
          }
          bytes.addAll(part);
        }
        if (uid != native.session.currentIdentity?.uid) {
          throw _failure('cancelled');
        }
        if (response.statusCode >= 300 && response.statusCode < 400) {
          throw _failure('unavailable');
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) throw _failure('internal');
        if (decoded['error'] case final Map error) {
          final status = error['status'];
          final code = status is String
              ? status.toLowerCase().replaceAll('_', '-')
              : 'internal';
          if (!const {
            'cancelled',
            'unknown',
            'invalid-argument',
            'deadline-exceeded',
            'not-found',
            'already-exists',
            'permission-denied',
            'resource-exhausted',
            'failed-precondition',
            'aborted',
            'out-of-range',
            'unimplemented',
            'internal',
            'unavailable',
            'data-loss',
            'unauthenticated',
          }.contains(code)) {
            throw _failure('internal');
          }
          throw FirebaseFunctionsException(
            code: code,
            message: 'The cloud request could not be completed.',
            details: _decode(error['details']),
          );
        }
        if (response.statusCode != 200) {
          throw _failure(switch (response.statusCode) {
            401 => 'unauthenticated',
            403 => 'permission-denied',
            429 => 'resource-exhausted',
            _ => 'internal',
          });
        }
        if (decoded.containsKey('result')) return _decode(decoded['result']);
        if (decoded.containsKey('data')) return _decode(decoded['data']);
        throw _failure('internal');
      })().timeout(options.timeout);
    } on FirebaseFunctionsException {
      rethrow;
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw _failure('deadline-exceeded');
    } on http.ClientException {
      throw _failure('unavailable');
    } on FormatException {
      throw _failure('internal');
    } finally {
      timer.cancel();
    }
  }

  static Object? _encode(Object? value) {
    if (value == null || value is String || value is bool) return value;
    if (value is int) {
      return value.abs() <= 9007199254740991
          ? value
          : {
              '@type': 'type.googleapis.com/google.protobuf.Int64Value',
              'value': '$value',
            };
    }
    if (value is double && value.isFinite) return value;
    if (value is List) return value.map(_encode).toList();
    if (value is Map) {
      if (value.keys.any((key) => key is! String)) {
        throw const FormatException('Callable map keys must be strings.');
      }
      return value.map<String, Object?>(
        (key, item) => MapEntry(key as String, _encode(item)),
      );
    }
    throw const FormatException('Unsupported callable value.');
  }

  static Object? _decode(Object? value) {
    if (value is List) return value.map(_decode).toList();
    if (value is Map) {
      if (const {
        'type.googleapis.com/google.protobuf.Int64Value',
        'type.googleapis.com/google.protobuf.UInt64Value',
      }.contains(value['@type'])) {
        final integer = int.tryParse('${value['value']}');
        if (integer == null) {
          throw const FormatException('Invalid callable integer.');
        }
        return integer;
      }
      return value.map((key, item) => MapEntry(key, _decode(item)));
    }
    return value;
  }
}
