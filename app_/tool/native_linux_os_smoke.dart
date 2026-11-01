import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_storage/firebase_options.dart';
import 'package:cloud_storage/src/privacy/local_offline_vault.dart';
import 'package:cloud_storage/src/privacy/local_private_cache.dart';
import 'package:cloud_storage/src/shared/background_backup_runner.dart';
import 'package:cloud_storage/src/shared/desktop_startup.dart';
import 'package:cloud_storage/src/shared/desktop_worker_lifecycle.dart';
import 'package:cloud_storage/src/shared/firebase_environment_bootstrap.dart';
import 'package:cloud_storage/src/shared/persistent_folder_access.dart';
import 'package:cloud_storage/src/shared/service_environment.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _workerLease(String phase, Directory support) async {
  final ready = File(p.join(support.path, 'synthetic-worker-ready'));
  final release = File(p.join(support.path, 'synthetic-worker-release'));
  if (phase == 'lease-hold') {
    var entered = false;
    await runWithDesktopWorkerLease(() async {
      entered = true;
      await ready.writeAsString('ready', flush: true);
      while (!await release.exists()) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    if (!entered) throw StateError('The holder did not acquire its lease.');
  } else {
    while (!await ready.exists()) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    var entered = false;
    await runWithDesktopWorkerLease(() async => entered = true);
    if (entered) {
      throw StateError('Concurrent worker acquired an existing lease.');
    }
    await release.writeAsString('release', flush: true);
  }
  stdout.writeln('NATIVE_LINUX_OS_WORKER_LEASE_OK');
}

// A compiled GTK executable, not a widget-test mock: the two invocations share
// only the real libsecret credential in an isolated CI desktop session. All
// network requests use the demo Auth/Firestore emulators configured by bootstrap.
Future<void> main(List<String> arguments) async {
  var stage = 'configuration';
  final deadline = Timer(const Duration(seconds: 40), () {
    stderr.writeln('NATIVE_LINUX_OS_TIMEOUT');
    exit(1);
  });
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final phases = arguments
        .where((argument) => argument != '--background-backup-worker')
        .toList();
    final temporary = Platform.environment['RUNNER_TEMP'];
    final configuration = Platform.environment['XDG_CONFIG_HOME'];
    if (!Platform.isLinux ||
        ServiceEnvironmentConfig.current != ServiceEnvironment.local ||
        Platform.environment['CI'] != 'true' ||
        temporary == null ||
        configuration == null ||
        !p.isWithin(temporary, configuration) ||
        phases.length != 1 ||
        !const [
          'seed',
          'restore',
          'lease-hold',
          'lease-probe',
        ].contains(phases.single)) {
      throw StateError('Invalid isolated smoke configuration.');
    }
    final phase = phases.single;
    final support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    if (phase.startsWith('lease-')) {
      stage = phase;
      await _workerLease(phase, support);
      deadline.cancel();
      exit(0);
    }
    stage = 'bootstrap';
    var app = await FirebaseEnvironmentBootstrap.initialize(
      productionDefaults: DefaultFirebaseOptions.linux,
    );
    if (app.options.projectId != ServiceEnvironmentPolicy.localProjectId) {
      throw StateError('A demo project is required.');
    }
    var auth = FirebaseAuth.instanceFor(app: app);
    const email = 'native-keyring-smoke@example.test';
    if (phase == 'seed') {
      stage = 'seed';
      if (auth.currentUser != null) {
        throw StateError('The test keyring must start empty.');
      }
      final user = (await auth.createUserWithEmailAndPassword(
        email: email,
        password: 'synthetic-local-keyring-smoke-21',
      )).user!;
      final timestamp = DateTime.now().toUtc().toIso8601String();
      stage = 'profile-write';
      await FirebaseFirestore.instanceFor(
        app: app,
      ).doc('users/${user.uid}').set({
        'profilePrivacyVersion': 1,
        'createdAt': timestamp,
        'currentPeriodEnd': 'pending',
        'capacity': 'pending',
        'subscriptionStatus': 'pending',
        'legalVersion': '2026-06-12',
        'termsAcceptedAt': timestamp,
        'privacyAcknowledgedAt': timestamp,
        'acceptableUseAcceptedAt': timestamp,
        'cancellationRefundAcknowledgedAt': timestamp,
        'dataRetentionAcknowledgedAt': timestamp,
        'subprocessorsAcknowledgedAt': timestamp,
        'legalAcceptanceSource': 'signup',
      });
      stage = 'native-file-backup';
      final folder = Directory(
        p.join(support.path, 'synthetic-selected-folder'),
      );
      final nested = Directory(p.join(folder.path, 'nested'));
      await nested.create(recursive: true);
      await File(
        p.join(nested.path, 'synthetic.txt'),
      ).writeAsString('synthetic-file');
      await PersistentFolderAccess.withAccess(
        path: folder.path,
        action: () async {
          final entries = await folder
              .list(recursive: true, followLinks: false)
              .toList();
          if (entries.whereType<File>().length != 1) {
            throw StateError('Recursive folder enumeration failed.');
          }
        },
      );
      final preferences = await SharedPreferences.getInstance();
      await LocalPrivateCachePreferences(
        preferences: preferences,
        uid: user.uid,
        scope: app.options.projectId,
      ).write(
        baseKey: BackgroundBackupRunner.backupConfigsPrefKey,
        namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
        value: jsonEncode([
          {
            'localPath': folder.path,
            'remoteFolder': 'Synthetic backup',
            'enabled': true,
            'photoLibrary': false,
          },
        ]),
      );
      stage = 'offline-vault';
      final vault = LocalOfflineVault(
        uid: user.uid,
        scope: app.options.projectId,
      );
      await vault.encryptStream(
        plaintext: Stream.value(utf8.encode('synthetic-offline-content')),
        destination: File(p.join(support.path, 'synthetic.rdoffline')),
        objectKey: 'synthetic-object',
      );
      stage = 'opt-in-startup';
      if (await DesktopStartup.isEnabled()) {
        throw StateError('The isolated startup configuration must be empty.');
      }
      await DesktopStartup.setEnabled(true);
      // Dispose memory and sockets without signing out. The next OS process
      // must recover the session from libsecret rather than shared Dart state.
      await app.delete();
      stdout.writeln('NATIVE_LINUX_OS_SEED_OK');
    } else {
      stage = 'restore';
      final user = auth.currentUser;
      if (user == null || user.email != email) {
        throw StateError('The OS credential did not restore.');
      }
      final profile = await FirebaseFirestore.instanceFor(
        app: app,
      ).doc('users/${user.uid}').get();
      if (!profile.exists ||
          profile.data()?['subscriptionStatus'] != 'pending' ||
          (await user.getIdToken(true))?.isNotEmpty != true) {
        throw StateError('The restored user could not access their profile.');
      }
      stage = 'backup-restoration';
      final configs = await BackgroundBackupRunner.loadEnabledWatchConfigs();
      if (configs.length != 1 ||
          configs.single.localPath !=
              p.join(support.path, 'synthetic-selected-folder')) {
        throw StateError('Encrypted backup configuration did not restore.');
      }
      stage = 'offline-vault-restoration';
      final vault = LocalOfflineVault(
        uid: user.uid,
        scope: app.options.projectId,
      );
      final content = await vault.readBytes(
        source: File(p.join(support.path, 'synthetic.rdoffline')),
        objectKey: 'synthetic-object',
        maximumBytes: 1024,
      );
      if (utf8.decode(content) != 'synthetic-offline-content') {
        throw StateError('The encrypted offline file did not restore.');
      }
      content.fillRange(0, content.length, 0);
      await vault.forgetKey();
      stage = 'startup-restoration';
      if (!await DesktopStartup.isEnabled()) {
        throw StateError('Explicit startup consent did not persist.');
      }
      await DesktopStartup.setEnabled(false);
      if (await DesktopStartup.isEnabled()) {
        throw StateError('Startup consent could not be withdrawn.');
      }
      stage = 'persistent-sign-out';
      await auth.signOut();
      await app.delete();
      app = await FirebaseEnvironmentBootstrap.initialize(
        productionDefaults: DefaultFirebaseOptions.linux,
      );
      auth = FirebaseAuth.instanceFor(app: app);
      if (auth.currentUser != null) {
        throw StateError('Sign-out did not remove the persistent credential.');
      }
      await app.delete();
      stdout.writeln('NATIVE_LINUX_OS_RESTORE_OK');
    }
    deadline.cancel();
    exit(0);
  } catch (_) {
    // Never print SDK errors, account data, refresh tokens or keyring contents.
    deadline.cancel();
    stderr.writeln('NATIVE_LINUX_OS_FAILED:$stage');
    exit(1);
  }
}
