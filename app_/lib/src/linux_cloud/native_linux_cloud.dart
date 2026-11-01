import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

import 'native_auth_session.dart';
import 'native_auth_transport.dart';
import 'native_firebase_auth.dart';
import 'native_firebase_core.dart';
import 'native_firebase_firestore.dart';
import 'native_firebase_functions.dart';
import 'native_firestore_codec.dart';

/// Must be registered once in each Linux UI/worker isolate, before any access
/// to Firebase or FieldValue in each UI/worker isolate.
class NativeLinuxCloud {
  NativeLinuxCloud({
    NativeSessionStore store = const KeyringNativeSessionStore(),
    this.authEmulatorPort,
    this.firestoreEmulatorPort,
    this.automaticallyRefresh = true,
  }) : _store = store {
    if ((authEmulatorPort == null) != (firestoreEmulatorPort == null)) {
      throw ArgumentError(
        'Auth and Firestore emulator authorities must be configured together.',
      );
    }
    for (final port in [authEmulatorPort, firestoreEmulatorPort]) {
      if (port != null && (port < 1 || port > 65535)) {
        throw ArgumentError('Invalid loopback emulator port.');
      }
    }
    firestore = NativeFirebaseFirestore(
      sessionFor: _session,
      emulatorPort: firestoreEmulatorPort,
    );
    functions = NativeFirebaseFunctions(sessionFor: _session);
    auth = NativeFirebaseAuth(sessionFor: _session);
    core = NativeFirebaseCore(
      initializeServices: (app) async {
        if (authEmulatorPort != null &&
            !app.options.projectId.startsWith('demo-')) {
          throw FirebaseException(
            plugin: 'core',
            code: 'invalid-options',
            message: 'Local native emulators require a demo project.',
          );
        }
        final session = NativeAuthSession(
          projectId: app.options.projectId,
          projectNumber: authEmulatorPort == null
              ? app.options.messagingSenderId
              : null,
          appId: app.options.appId,
          appName: app.name,
          transport: NativeAuthTransport(
            apiKey: app.options.apiKey,
            emulatorPort: authEmulatorPort,
          ),
          store: _store,
          automaticallyRefresh: automaticallyRefresh,
        );
        _sessions[app.name] = session;
        await session.restore();
      },
      disposeServices: (name) async {
        // Close sockets/listeners before disposing the shared user-token source.
        await firestore.disposeApp(name);
        functions.disposeApp(name);
        await _sessions.remove(name)?.dispose();
      },
    );
  }

  final NativeSessionStore _store;
  final int? authEmulatorPort;
  final int? firestoreEmulatorPort;
  final bool automaticallyRefresh;
  final _sessions = <String, NativeAuthSession>{};
  late final NativeFirebaseCore core;
  late final NativeFirebaseAuth auth;
  late final NativeFirebaseFirestore firestore;
  late final NativeFirebaseFunctions functions;
  bool _registered = false;

  NativeAuthSession _session(String name) =>
      _sessions[name] ??
      (throw FirebaseException(
        plugin: 'core',
        code: 'no-app',
        message:
            'Initialize the native application before using cloud services.',
      ));

  void register() {
    if (_registered) return;
    if (FirebasePlatform.instance.apps.isNotEmpty) {
      throw StateError(
        'Native cloud adapters must be registered before Firebase initialization.',
      );
    }
    FirebasePlatform.instance = core;
    FirebaseAuthPlatform.instance = auth;
    FirebaseFirestorePlatform.instance = firestore;
    FirebaseFunctionsPlatform.instance = functions;
    FieldValueFactoryPlatform.instance = NativeFieldValueFactory();
    _registered = true;
  }
}
