import 'dart:async';

import 'package:cloud_storage/src/shared/firebase_environment_bootstrap.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _App extends Fake implements FirebaseApp {
  _App(this.name);
  @override
  final String name;
  @override
  FirebaseOptions get options => const FirebaseOptions(
    apiKey: 'synthetic',
    appId: 'synthetic',
    messagingSenderId: 'synthetic',
    projectId: 'demo-ronikdrive-local',
  );
}

void main() {
  test(
    'failed emulator setup retries and successful setup is cached',
    () async {
      final app = _App('retry-after-emulator-failure');
      var attempts = 0;
      Future<void> configure() async {
        if (++attempts == 1) throw StateError('synthetic plugin failure');
      }

      await expectLater(
        FirebaseEnvironmentBootstrap.configureForTesting(app, configure),
        throwsStateError,
      );
      await FirebaseEnvironmentBootstrap.configureForTesting(app, configure);
      await FirebaseEnvironmentBootstrap.configureForTesting(app, configure);
      expect(attempts, 2);
    },
  );

  test(
    'concurrent callers share a failed attempt and can retry together',
    () async {
      final app = _App('concurrent-emulator-configuration');
      final first = Completer<void>();
      var attempts = 0;
      Future<void> configure() {
        attempts++;
        return attempts == 1 ? first.future : Future<void>.value();
      }

      final a = FirebaseEnvironmentBootstrap.configureForTesting(
        app,
        configure,
      );
      final b = FirebaseEnvironmentBootstrap.configureForTesting(
        app,
        configure,
      );
      final expected = Future.wait([
        expectLater(a, throwsStateError),
        expectLater(b, throwsStateError),
      ]);
      first.completeError(StateError('synthetic plugin failure'));
      await expected;
      expect(attempts, 1);
      await Future.wait([
        FirebaseEnvironmentBootstrap.configureForTesting(app, configure),
        FirebaseEnvironmentBootstrap.configureForTesting(app, configure),
      ]);
      expect(attempts, 2);
    },
  );
}
