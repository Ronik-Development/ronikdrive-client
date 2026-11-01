import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class ConfiguredFirestore {
  ConfiguredFirestore._();

  static final Set<String> _configuredInstances = <String>{};

  static FirebaseFirestore instanceFor({
    required FirebaseApp app,
    String? databaseId,
  }) {
    final firestore = FirebaseFirestore.instanceFor(
      app: app,
      databaseId: databaseId,
    );
    _configureForCurrentPlatform(firestore);
    return firestore;
  }

  static void _configureForCurrentPlatform(FirebaseFirestore firestore) {
    final windows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (!kIsWeb && !windows) {
      return;
    }

    final cacheKey = '${firestore.app.name}|${firestore.databaseId}';
    if (!_configuredInstances.add(cacheKey)) {
      return;
    }

    if (windows) {
      // UI and detached backup workers run in separate processes. Firestore's
      // LevelDB persistence is exclusive and crashes on a shared database lock.
      // Encrypted app-managed offline files remain independent of this cache.
      firestore.settings = const Settings(persistenceEnabled: false);
      return;
    }
    firestore.settings = const Settings(
      webExperimentalForceLongPolling: true,
      webExperimentalLongPollingOptions: WebExperimentalLongPollingOptions(
        timeoutDuration: Duration(seconds: 15),
      ),
    );
  }
}
