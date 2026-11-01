import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'service_environment.dart';
import 'native_cloud_registration.dart';

class FirebaseEnvironmentBootstrap {
  const FirebaseEnvironmentBootstrap._();

  static const String emulatorHost = '127.0.0.1';
  static const int authEmulatorPort = 9099;
  static const int firestoreEmulatorPort = 8080;
  static const int functionsEmulatorPort = 5001;

  static final Map<String, Future<void>> _configurations = {};

  static Future<FirebaseApp> initialize({
    required FirebaseOptions productionDefaults,
  }) async {
    registerNativeCloudForCurrentPlatform();
    final options = ServiceEnvironmentConfig.firebaseOptions(
      productionDefaults,
    );
    final app = Firebase.apps.isEmpty
        ? await Firebase.initializeApp(options: options)
        : Firebase.app();
    await configure(app);
    return app;
  }

  static Future<void> configure(FirebaseApp app) => _configure(app, () async {
    await FirebaseAuth.instanceFor(
      app: app,
    ).useAuthEmulator(emulatorHost, authEmulatorPort);
    FirebaseFirestore.instanceFor(
      app: app,
    ).useFirestoreEmulator(emulatorHost, firestoreEmulatorPort);
    FirebaseFunctions.instanceFor(
      app: app,
      region: 'europe-west1',
    ).useFunctionsEmulator(emulatorHost, functionsEmulatorPort);
  });

  @visibleForTesting
  static Future<void> configureForTesting(
    FirebaseApp app,
    Future<void> Function() configureLocalEmulators,
  ) => _configure(app, configureLocalEmulators);

  static Future<void> _configure(
    FirebaseApp app,
    Future<void> Function() configureLocalEmulators,
  ) async {
    ServiceEnvironmentPolicy.validateFirebaseProject(
      environment: ServiceEnvironmentConfig.current,
      projectId: app.options.projectId,
    );
    if (!ServiceEnvironmentConfig.usesLocalEmulators) return;
    final pending = _configurations[app.name];
    if (pending != null) return pending;
    final configuration = Future<void>.sync(configureLocalEmulators);
    _configurations[app.name] = configuration;
    try {
      await configuration;
    } catch (_) {
      // Concurrent callers share the attempt. Only successful configurations
      // remain cached, so startup Retry can recover from a plugin failure.
      if (identical(_configurations[app.name], configuration)) {
        _configurations.remove(app.name);
      }
      rethrow;
    }
  }
}
