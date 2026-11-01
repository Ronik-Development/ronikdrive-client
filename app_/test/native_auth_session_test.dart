import 'dart:async';
import 'dart:convert';

import 'package:cloud_storage/src/linux_cloud/native_auth_session.dart';
import 'package:cloud_storage/src/linux_cloud/native_auth_transport.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _now = DateTime.utc(2026, 10, 17, 12);
String _jwt(
  String uid, {
  String project = 'demo-native',
  int lifetime = 3600,
}) =>
    '${base64Url.encode(utf8.encode('{"alg":"none"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'aud': project, 'iss': 'https://securetoken.google.com/$project', 'exp': _now.add(Duration(seconds: lifetime)).millisecondsSinceEpoch ~/ 1000})))}.test-only';

Map<String, Object> _grant(String uid, {String? refresh, String? token}) => {
  'localId': uid,
  'idToken': token ?? _jwt(uid),
  'refreshToken': refresh ?? 'refresh-$uid',
  'expiresIn': '3600',
};

class _Store implements NativeSessionStore {
  final values = <String, String>{};
  bool failWrite = false;
  Completer<void>? blockWrite;
  Completer<void>? writeStarted;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('OS keyring diagnostic must stay private');
    final block = blockWrite;
    blockWrite = null;
    if (block != null) {
      writeStarted?.complete();
      await block.future;
    }
    values[key] = value;
  }
}

Matcher _code(String code) =>
    isA<FirebaseAuthException>().having((e) => e.code, 'code', code);
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);
http.Response _lookup(http.Request request) {
  final token = (jsonDecode(request.body) as Map)['idToken'] as String;
  final uid =
      (jsonDecode(
            utf8.decode(
              base64Url.decode(base64Url.normalize(token.split('.')[1])),
            ),
          )
          as Map)['sub'];
  return _json({
    'users': [
      {'localId': uid, 'email': '$uid@example.test', 'emailVerified': true},
    ],
  });
}

NativeAuthSession _session(
  _Store store,
  MockClient client, {
  String project = 'demo-native',
  String appId = 'native-test',
  String? projectNumber,
  int? emulatorPort,
}) => NativeAuthSession(
  projectId: project,
  projectNumber: projectNumber,
  appId: appId,
  appName: '[DEFAULT]',
  transport: NativeAuthTransport(
    apiKey: 'test-public-key',
    client: client,
    emulatorPort: emulatorPort,
  ),
  store: store,
  now: () => _now,
  automaticallyRefresh: false,
);

void main() {
  test(
    'sign-in uses the server UID and stores only a refresh credential in the keyring',
    () async {
      final store = _Store();
      final session = _session(
        store,
        MockClient((request) async {
          expect(request.followRedirects, false);
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'identitytoolkit.googleapis.com');
          if (request.url.path.endsWith(':lookup')) return _lookup(request);
          expect(jsonDecode(request.body)['password'], 'test-password');
          return _json(_grant('existing-web-customer'));
        }),
      );
      addTearDown(session.dispose);
      final identity = await session.signIn(
        'customer@example.test',
        'test-password',
      );
      expect(identity.uid, 'existing-web-customer');
      expect(identity.account['emailVerified'], true);
      final saved = jsonDecode(store.values[session.storageKey]!);
      expect(saved, {
        'schema': 1,
        'uid': 'existing-web-customer',
        'refreshToken': 'refresh-existing-web-customer',
      });
      expect(store.values.values.single, isNot(contains('test-password')));
      expect(store.values.values.single, isNot(contains(_jwt(identity.uid))));
      expect(await session.idToken(forUid: identity.uid), _jwt(identity.uid));
    },
  );

  test(
    'restoration refreshes and looks up the same account before publishing it',
    () async {
      final store = _Store();
      final calls = <String>[];
      final session = _session(
        store,
        MockClient((request) async {
          calls.add(request.url.host);
          if (request.url.path.endsWith(':lookup')) return _lookup(request);
          expect(request.bodyFields['refresh_token'], 'old-refresh');
          return _json({
            'user_id': 'web-user',
            'project_id': '1234567890',
            'id_token': _jwt('web-user'),
            'refresh_token': 'rotated-refresh',
          });
        }),
        projectNumber: '1234567890',
      );
      addTearDown(session.dispose);
      store.values[session.storageKey] = jsonEncode({
        'schema': 1,
        'uid': 'web-user',
        'refreshToken': 'old-refresh',
      });
      expect(session.currentIdentity, null);
      expect((await session.restore())?.uid, 'web-user');
      expect(calls, [
        'securetoken.googleapis.com',
        'identitytoolkit.googleapis.com',
      ]);
      expect(
        jsonDecode(store.values[session.storageKey]!)['refreshToken'],
        'rotated-refresh',
      );
    },
  );

  test(
    'project, application and emulator sessions have separate keyring keys',
    () async {
      final store = _Store();
      final client = MockClient(
        (_) async => throw StateError('No network expected'),
      );
      final sessions = [
        _session(store, client),
        _session(store, client, project: 'another-project'),
        _session(store, client, appId: 'another-app'),
        _session(store, client, emulatorPort: 9099),
      ];
      for (final session in sessions) {
        addTearDown(session.dispose);
      }
      expect(sessions.map((e) => e.storageKey).toSet(), hasLength(4));
      for (final session in sessions) {
        expect(await session.restore(), null);
      }
    },
  );

  for (final returnedProject in ['9876543210', 'different-project-id']) {
    test(
      'refresh rejects a mismatched or malformed project number: $returnedProject',
      () async {
        final store = _Store();
        var lookups = 0;
        final session = _session(
          store,
          MockClient((request) async {
            if (request.url.path.endsWith(':lookup')) {
              lookups++;
              return _lookup(request);
            }
            return _json({
              'user_id': 'web-user',
              'project_id': returnedProject,
              'id_token': _jwt('web-user'),
              'refresh_token': 'rotated-refresh',
            });
          }),
          projectNumber: '1234567890',
        );
        addTearDown(session.dispose);
        store.values[session.storageKey] = jsonEncode({
          'schema': 1,
          'uid': 'web-user',
          'refreshToken': 'old-refresh',
        });
        await expectLater(
          session.restore(),
          throwsA(_code('invalid-user-token')),
        );
        expect(session.currentIdentity, null);
        expect(lookups, 0);
      },
    );
  }

  for (final tokenCase in [
    'different-project',
    'different-user',
    'expired',
    'malformed',
  ]) {
    test(
      'rejects $tokenCase token before establishing an account session',
      () async {
        final store = _Store();
        final token = switch (tokenCase) {
          'different-project' => _jwt('user', project: 'foreign-project'),
          'different-user' => _jwt('other-user'),
          'expired' => _jwt('user', lifetime: -1),
          _ => 'malformed-private-token',
        };
        var calls = 0;
        final session = _session(
          store,
          MockClient((_) async {
            calls++;
            return _json(_grant('user', token: token));
          }),
        );
        addTearDown(session.dispose);
        await expectLater(
          session.signIn('user@example.test', 'test-password'),
          throwsA(_code('invalid-user-token')),
        );
        expect(session.currentIdentity, null);
        expect(store.values, isEmpty);
        expect(calls, 1);
      },
    );
  }

  test(
    'lookup cannot replace the user identified by the issued token',
    () async {
      final store = _Store();
      final session = _session(
        store,
        MockClient(
          (request) async => request.url.path.endsWith(':lookup')
              ? _json({
                  'users': [
                    {'localId': 'another-user'},
                  ],
                })
              : _json(_grant('user')),
        ),
      );
      addTearDown(session.dispose);
      await expectLater(
        session.signIn('user@example.test', 'test-password'),
        throwsA(_code('invalid-user-token')),
      );
      expect(store.values, isEmpty);
    },
  );

  test(
    'a locked keyring prevents successful persistent sign-in and hides OS details',
    () async {
      final store = _Store()..failWrite = true;
      final session = _session(
        store,
        MockClient(
          (request) async => request.url.path.endsWith(':lookup')
              ? _lookup(request)
              : _json(_grant('user')),
        ),
      );
      addTearDown(session.dispose);
      await expectLater(
        session.signIn('user@example.test', 'test-password'),
        throwsA(_code('keychain-error')),
      );
      expect(session.currentIdentity, null);
      expect(store.values, isEmpty);
    },
  );

  test('sign-out wins over an in-flight sign-in response', () async {
    final reply = Completer<http.Response>();
    final store = _Store();
    final session = _session(store, MockClient((_) => reply.future));
    addTearDown(session.dispose);
    final pending = session.signIn('user@example.test', 'test-password');
    final rejected = expectLater(pending, throwsA(_code('user-token-expired')));
    await session.signOut();
    reply.complete(_json(_grant('user')));
    await rejected;
    expect(session.currentIdentity, null);
    expect(store.values, isEmpty);
  });

  test(
    'sign-out also wins when an account keyring write is already awaiting',
    () async {
      final store = _Store();
      final block = Completer<void>();
      store.blockWrite = block;
      store.writeStarted = Completer<void>();
      final session = _session(
        store,
        MockClient(
          (request) async => request.url.path.endsWith(':lookup')
              ? _lookup(request)
              : _json(_grant('user')),
        ),
      );
      addTearDown(session.dispose);
      final pending = session.signIn('user@example.test', 'test-password');
      final rejected = expectLater(
        pending,
        throwsA(_code('user-token-expired')),
      );
      await store.writeStarted!.future;
      final logout = session.signOut();
      block.complete();
      await Future.wait([rejected, logout]);
      expect(session.currentIdentity, null);
      expect(store.values, isEmpty);
    },
  );

  test(
    'a stale user reference cannot obtain tokens or mutate the replacement account',
    () async {
      var current = 'first';
      final session = _session(
        _Store(),
        MockClient(
          (request) async => request.url.path.endsWith(':lookup')
              ? _lookup(request)
              : _json(_grant(current)),
        ),
      );
      addTearDown(session.dispose);
      await session.signIn('first@example.test', 'test-password');
      current = 'second';
      await session.signIn('second@example.test', 'test-password');
      await expectLater(
        session.idToken(forUid: 'first'),
        throwsA(_code('user-token-expired')),
      );
      await expectLater(
        session.accountRequest('first', 'update', {
          'displayName': 'wrong account',
        }),
        throwsA(_code('user-token-expired')),
      );
      expect(session.currentIdentity?.uid, 'second');
    },
  );

  test('concurrent forced token refreshes share one request', () async {
    var refreshes = 0;
    final reply = Completer<http.Response>();
    final session = _session(
      _Store(),
      MockClient((request) async {
        if (request.url.path.endsWith(':lookup')) return _lookup(request);
        if (request.url.host == 'securetoken.googleapis.com') {
          refreshes++;
          return reply.future;
        }
        return _json(_grant('user'));
      }),
    );
    addTearDown(session.dispose);
    await session.signIn('user@example.test', 'test-password');
    final first = session.idToken(forceRefresh: true);
    final second = session.idToken(forceRefresh: true);
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 1);
    reply.complete(_json(_grant('user', refresh: 'rotated')));
    expect(await Future.wait([first, second]), [_jwt('user'), _jwt('user')]);
  });

  test(
    'revoked refresh credentials clear the session and keyring record',
    () async {
      final store = _Store();
      final session = _session(
        store,
        MockClient((request) async {
          if (request.url.path.endsWith(':lookup')) return _lookup(request);
          if (request.url.host == 'securetoken.googleapis.com') {
            return _json({
              'error': {'message': 'INVALID_REFRESH_TOKEN'},
            }, 400);
          }
          return _json(_grant('user'));
        }),
      );
      addTearDown(session.dispose);
      await session.signIn('user@example.test', 'test-password');
      await expectLater(
        session.idToken(forceRefresh: true),
        throwsA(_code('user-token-expired')),
      );
      expect(session.currentIdentity, null);
      expect(store.values, isEmpty);
    },
  );

  test(
    'temporary refresh network failures preserve the stored credential',
    () async {
      final store = _Store();
      final session = _session(
        store,
        MockClient((request) async {
          if (request.url.path.endsWith(':lookup')) return _lookup(request);
          if (request.url.host == 'securetoken.googleapis.com') {
            throw http.ClientException('private network diagnostic');
          }
          return _json(_grant('user'));
        }),
      );
      addTearDown(session.dispose);
      await session.signIn('user@example.test', 'test-password');
      await expectLater(
        session.idToken(forceRefresh: true),
        throwsA(_code('network-request-failed')),
      );
      expect(session.currentIdentity?.uid, 'user');
      expect(store.values, isNotEmpty);
    },
  );

  test(
    'malformed keyring records are removed without any network request',
    () async {
      final store = _Store();
      final session = _session(
        store,
        MockClient((_) async => throw StateError('No network expected')),
      );
      addTearDown(session.dispose);
      store.values[session.storageKey] = 'not-json';
      await expectLater(
        session.restore(),
        throwsA(_code('invalid-user-token')),
      );
      expect(store.values, isEmpty);
    },
  );

  for (final responseCase in [
    'redirect',
    'oversized',
    'malformed',
    'provider-error',
    'rate-limit',
  ]) {
    test(
      'transport safely rejects $responseCase without exposing provider response text',
      () async {
        final transport = NativeAuthTransport(
          apiKey: 'public-test-key',
          client: MockClient((request) async {
            expect(request.followRedirects, false);
            return switch (responseCase) {
              'redirect' => http.Response(
                '',
                302,
                headers: {'location': 'https://untrusted.example.test'},
              ),
              'oversized' => http.Response('x' * (1024 * 1024 + 1), 200),
              'malformed' => http.Response('private provider detail', 200),
              'rate-limit' => http.Response('private provider detail', 429),
              _ => _json({
                'error': {
                  'message': 'UNKNOWN_SECRET_PROVIDER_DETAIL token=password',
                },
              }, 400),
            };
          }),
        );
        addTearDown(transport.close);
        try {
          await transport.account('signInWithPassword', {
            'email': 'test@example.test',
            'password': 'test-password',
          });
          fail('Expected rejection');
        } on FirebaseAuthException catch (error) {
          expect(error.toString(), isNot(contains('private provider detail')));
          expect(
            error.toString(),
            isNot(contains('UNKNOWN_SECRET_PROVIDER_DETAIL')),
          );
          expect(error.toString(), isNot(contains('test-password')));
        }
      },
    );
  }

  test(
    'emulator credential requests are restricted to loopback and explicit auth paths',
    () async {
      final transport = NativeAuthTransport(
        apiKey: 'public-test-key',
        emulatorPort: 9099,
        client: MockClient((request) async {
          expect(request.url.host, '127.0.0.1');
          expect(request.url.port, 9099);
          expect(
            request.url.path,
            '/identitytoolkit.googleapis.com/v1/accounts:sendOobCode',
          );
          return _json({});
        }),
      );
      addTearDown(transport.close);
      await transport.account('sendOobCode', {
        'requestType': 'PASSWORD_RESET',
        'email': 'test@example.test',
      });
      expect(
        () => transport.account('../other-endpoint', {}),
        throwsArgumentError,
      );
    },
  );
}
