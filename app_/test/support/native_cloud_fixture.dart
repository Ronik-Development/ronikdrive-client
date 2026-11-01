import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:cloud_storage/src/linux_cloud/native_auth_session.dart';
import 'package:cloud_storage/src/linux_cloud/native_auth_transport.dart';
import 'package:cloud_storage/src/linux_cloud/native_firebase_auth.dart';
import 'package:cloud_storage/src/linux_cloud/native_firebase_core.dart';
import 'package:cloud_storage/src/linux_cloud/native_firebase_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryNativeSessionStore implements NativeSessionStore {
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

/// Synthetic server and keyring for testing the real public FlutterFire API.
/// Never sends network requests, creates real accounts or sends emails.
class NativeCloudFixture {
  static int _sequence = 0;
  static const projectId = 'demo-native-core';
  final previousCore = FirebasePlatform.instance;
  final previousCorePacking = Firebase.delegatePackingProperty;
  final previousAuth = FirebaseAuthPlatform.instance;
  final previousFunctions = FirebaseFunctionsPlatform.instance;
  final store = MemoryNativeSessionStore();
  final sessions = <String, NativeAuthSession>{};
  final requests = <http.Request>[];
  String nextSignInUid = 'existing-web-customer';
  String? displayName;
  FutureOr<http.Response> Function(http.Request)? functionHandler;
  late final MockClient client = MockClient(_handle);
  late final NativeFirebaseCore core;
  late final NativeFirebaseFunctions functionsRoot;
  late final FirebaseApp app;
  FirebaseAuth get auth => FirebaseAuth.instanceFor(app: app);

  static String token(String uid) =>
      '${base64Url.encode(utf8.encode('{"alg":"none"}'))}.${base64Url.encode(utf8.encode(jsonEncode({
        'sub': uid,
        'aud': projectId,
        'iss': 'https://securetoken.google.com/$projectId',
        'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'auth_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'firebase': {'sign_in_provider': 'password'},
      })))}.synthetic-signature';
  static String tokenUid(String token) =>
      (jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(token.split('.')[1])),
                ),
              )
              as Map)['sub']
          as String;
  static http.Response json(Object? data, [int status = 200]) =>
      http.Response(jsonEncode(data), status);
  Map<String, Object?> _grant(String uid) => {
    'localId': uid,
    'idToken': token(uid),
    'refreshToken': 'refresh-$uid',
    'expiresIn': '3600',
  };

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (request.url.path.endsWith('accounts:lookup')) {
      final uid = tokenUid(
        (jsonDecode(request.body) as Map)['idToken'] as String,
      );
      return json({
        'users': [
          {
            'localId': uid,
            'email': '$uid@example.test',
            'emailVerified': true,
            if (displayName != null) 'displayName': displayName,
            'providerUserInfo': [
              {
                'providerId': 'password',
                'rawId': uid,
                'email': '$uid@example.test',
              },
            ],
            'createdAt': '1700000000000',
            'lastLoginAt': '1700000100000',
          },
        ],
      });
    }
    if (request.url.path.endsWith('accounts:signInWithPassword') ||
        request.url.path.endsWith('accounts:signUp') ||
        request.url.path.endsWith('accounts:signInWithCustomToken')) {
      return json(_grant(nextSignInUid));
    }
    if (request.url.path.endsWith('/token')) {
      return json(
        _grant(
          request.bodyFields['refresh_token']!.substring('refresh-'.length),
        ),
      );
    }
    if (request.url.path.endsWith('accounts:update')) {
      final body = jsonDecode(request.body) as Map;
      if (body['oobCode'] != null) return json({});
      if (body.containsKey('displayName')) {
        displayName = body['displayName'] as String?;
      }
      if (body['deleteAttribute'] is List &&
          (body['deleteAttribute'] as List).contains('DISPLAY_NAME')) {
        displayName = null;
      }
      return json(_grant(tokenUid(body['idToken'] as String)));
    }
    if (request.url.path.endsWith('accounts:sendOobCode') ||
        request.url.path.endsWith('accounts:delete')) {
      return json({});
    }
    if (request.url.path.endsWith('accounts:resetPassword')) {
      return json({'email': 'test@example.test'});
    }
    return await functionHandler?.call(request) ??
        json({
          'result': {'ok': true},
        });
  }

  Future<void> initialize({bool emulator = false}) async {
    functionsRoot = NativeFirebaseFunctions(
      sessionFor: (name) => sessions[name]!,
      clientFactory: () => client,
    );
    core = NativeFirebaseCore(
      initializeServices: (app) async {
        final session = NativeAuthSession(
          projectId: app.options.projectId,
          appId: app.options.appId,
          appName: app.name,
          transport: NativeAuthTransport(
            apiKey: app.options.apiKey,
            client: client,
            emulatorPort: emulator ? 9099 : null,
          ),
          store: store,
          automaticallyRefresh: false,
        );
        sessions[app.name] = session;
        await session.restore();
      },
      disposeServices: (name) async {
        functionsRoot.disposeApp(name);
        await sessions.remove(name)?.dispose();
      },
    );
    FirebasePlatform.instance = core;
    Firebase.delegatePackingProperty = core;
    FirebaseAuthPlatform.instance = NativeFirebaseAuth(
      sessionFor: (name) => sessions[name]!,
    );
    FirebaseFunctionsPlatform.instance = functionsRoot;
    app = await Firebase.initializeApp(
      name: 'native-adapter-test-${_sequence++}',
      options: const FirebaseOptions(
        apiKey: 'synthetic-public-key',
        appId: 'synthetic-app-id',
        messagingSenderId: '123',
        projectId: projectId,
      ),
    );
  }

  Future<void> dispose() async {
    await app.delete();
    client.close();
    FirebasePlatform.instance = previousCore;
    Firebase.delegatePackingProperty = previousCorePacking;
    FirebaseAuthPlatform.instance = previousAuth;
    FirebaseFunctionsPlatform.instance = previousFunctions;
  }
}
