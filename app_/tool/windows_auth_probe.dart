// Diagnostic entry point: no real credentials, account creation, or remote writes.
// Uses a separate Firebase app so the normal app's session is left alone.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'package:cloud_storage/firebase_options.dart';
import 'package:cloud_storage/src/authentication/password_sign_in.dart';
import 'package:cloud_storage/src/authentication/account_identity_stream.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final clock = Stopwatch()..start();
  void phase(String value) =>
      debugPrint('[auth-probe] ${clock.elapsedMilliseconds}ms $value');
  const remote = bool.fromEnvironment('RONIK_AUTH_PROBE_REMOTE');
  phase('initializing');
  try {
    final app = await Firebase.initializeApp(
      name: remote ? 'ronik-auth-probe' : 'ronik-auth-loopback-probe',
      options: remote
          ? DefaultFirebaseOptions.currentPlatform
          : const FirebaseOptions(
              apiKey: 'fake-api-key',
              appId: 'fake-app-id',
              messagingSenderId: '123',
              projectId: 'demo-ronik-auth-probe',
            ),
    ).timeout(const Duration(seconds: 15));
    final auth = FirebaseAuth.instanceFor(app: app);
    if (!remote) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      String encode(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token =
          '${encode({'alg': 'none', 'typ': 'JWT'})}.${encode({
            'iss': 'https://securetoken.google.com/demo-ronik-auth-probe',
            'aud': 'demo-ronik-auth-probe',
            'auth_time': now,
            'user_id': 'probe-user',
            'sub': 'probe-user',
            'iat': now,
            'exp': now + 3600,
            'email': 'probe@example.invalid',
            'email_verified': false,
            'firebase': {'identities': {}, 'sign_in_provider': 'password'},
          })}.';
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        phase('loopback-request');
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('accounts:lookup') ||
            request.uri.path.endsWith('getAccountInfo')) {
          request.response.write(
            jsonEncode({
              'users': [
                {
                  'localId': 'probe-user',
                  'email': 'probe@example.invalid',
                  'emailVerified': false,
                  'displayName': 'Synthetic probe',
                  'createdAt': '${now * 1000}',
                  'lastLoginAt': '${now * 1000}',
                  'providerUserInfo': [
                    {
                      'providerId': 'password',
                      'rawId': 'probe@example.invalid',
                      'email': 'probe@example.invalid',
                    },
                  ],
                },
              ],
            }),
          );
          await request.response.close();
          return;
        }
        if (body.contains('probe-wrong-password')) {
          request.response.statusCode = 400;
          request.response.write(
            jsonEncode({
              'error': {'code': 400, 'message': 'INVALID_PASSWORD'},
            }),
          );
          await request.response.close();
          return;
        }
        request.response.write(
          jsonEncode({
            'kind': 'identitytoolkit#VerifyPasswordResponse',
            'localId': 'probe-user',
            'email': 'probe@example.invalid',
            'displayName': 'Synthetic probe',
            'registered': true,
            'idToken': token,
            'refreshToken': 'fake-refresh-token',
            'expiresIn': '3600',
          }),
        );
        await request.response.close();
      });
      await auth.useAuthEmulator('127.0.0.1', server.port);
    }
    final rechecks = StreamController<void>.broadcast();
    final signedInEvent = Completer<void>();
    final signedOutEvent = Completer<void>();
    String? boundAccount;
    var observedSignIn = false;
    final identitySubscription =
        accountIdentityStream<User>(
          current: () => auth.currentUser,
          identity: (user) => user.uid,
          changes: auth.authStateChanges(),
          rechecks: rechecks.stream,
          bindAccount: (id) => boundAccount = id,
        ).listen((user) {
          if (boundAccount != user?.uid) {
            throw StateError('Account binding order');
          }
          if (user != null && !observedSignIn) {
            observedSignIn = true;
            signedInEvent.complete();
          } else if (user == null &&
              observedSignIn &&
              !signedOutEvent.isCompleted) {
            signedOutEvent.complete();
          }
        });
    phase('request-start');
    await (remote
            ? signInWithPassword(
                auth: auth,
                email:
                    'ronik-probe-${DateTime.now().microsecondsSinceEpoch}@example.invalid',
                password: 'deliberately-invalid-probe-password',
              )
            : auth.signInWithEmailAndPassword(
                email:
                    'ronik-probe-${DateTime.now().microsecondsSinceEpoch}@example.invalid',
                password: 'deliberately-invalid-probe-password',
              ))
        .timeout(const Duration(seconds: 30));
    phase(remote ? 'unexpected-success' : 'success-response-received');
    if (!remote) {
      await signedInEvent.future.timeout(const Duration(seconds: 5));
      phase('account-signin-event-observed');
      phase('reauthenticate-start');
      final credential = await auth.currentUser!
          .reauthenticateWithCredential(
            EmailAuthProvider.credential(
              email: 'probe@example.invalid',
              password: 'synthetic-probe-password',
            ),
          )
          .timeout(const Duration(seconds: 5));
      if (credential.user?.uid != 'probe-user') {
        throw StateError('Reauthentication returned an unexpected user.');
      }
      phase('reauthenticate-success-response-received');
      try {
        await auth.currentUser!
            .reauthenticateWithCredential(
              EmailAuthProvider.credential(
                email: 'probe@example.invalid',
                password: 'probe-wrong-password',
              ),
            )
            .timeout(const Duration(seconds: 5));
        throw StateError('Incorrect password was accepted.');
      } on FirebaseAuthException catch (error) {
        if (error.code != 'wrong-password' &&
            error.code != 'invalid-credential') {
          rethrow;
        }
        phase('reauthenticate-invalid-password-rejected');
      }
    }
    if (!remote) {
      await auth.signOut();
      await signedOutEvent.future.timeout(const Duration(seconds: 5));
      phase('account-signout-event-observed');
    }
    await identitySubscription.cancel();
    await rechecks.close();
    await Future<void>.delayed(const Duration(seconds: 3));
    exit(remote ? 2 : 0);
  } on FirebaseAuthException catch (error) {
    // Codes only: never SDK error messages, identifiers, or tokens.
    phase('response-code=${error.code}');
    // Only this synthetic, isolated probe may print an SDK error description.
    phase('probe-error=${error.message}');
    await Future<void>.delayed(const Duration(seconds: 3));
    exit(remote ? 0 : 5);
  } on TimeoutException {
    phase('timeout');
    exit(3);
  } catch (error) {
    phase('failure-type=${error.runtimeType}');
    exit(4);
  }
}
