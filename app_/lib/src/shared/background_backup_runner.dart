import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';
import 'firebase_environment_bootstrap.dart';
import 'folder_backup_platform_policy.dart';
import 'persistent_folder_access.dart';
import '../authentication/login_password_vault.dart';
import '../authentication/account_bound_token.dart';
import '../privacy/local_private_cache.dart';
import '../privacy/privacy_redaction.dart';
import '../security/encryption_service.dart';
import '../security/workspace_metadata_encryption_service.dart';
import '../storage/drive_repository.dart';
import '../storage/folder_document_writer.dart';
import '../desktop_drive/firestore_drive_backend.dart';
import '../storage/transfer_journal.dart';
import '../storage/upload_source_snapshot.dart';
import '../storage/backup_upload_checkpoint.dart';
import '../storage/file_identity.dart';
import '../storage/image_thumbnail_service.dart';
import '../storage/storage_home_prefix.dart';
import '../storage/upload_metadata_service.dart';
import '../storage/upload_coordinator.dart';
import '../storage/wasabi_provisioning_service.dart';
import '../storage/wasabi_storage_service.dart';
import 'configured_firestore.dart';
import 'user_activity.dart';
import 'notification_service.dart';
import 'native_cloud_registration.dart';
import 'ios_photo_library.dart';
import 'platform_io.dart';
import 'release_runtime_config.dart';

part 'background_backup_types.dart';

class BackgroundBackupRunner {
  /// Restore the same protected session used by backups before reading
  /// account-scoped Explorer consent in its separate worker process.
  static Future<bool> ensureNativeDriveAuthentication() async {
    await ensureFirebaseInitialized();
    final auth = FirebaseAuth.instanceFor(app: Firebase.app());
    return await _ensureBackgroundAuth(auth) != null;
  }

  static Future<FirestoreDriveBackend?> createNativeDriveBackend({
    required Future<bool> Function() stillEnabled,
  }) async {
    await ensureFirebaseInitialized();
    final auth = FirebaseAuth.instanceFor(app: Firebase.app());
    final user = await _ensureBackgroundAuth(auth);
    if (user == null) return null;
    final firestore = ConfiguredFirestore.instanceFor(app: auth.app);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool(passphraseRequiredPrefKey) == true) return null;
    final session = await _BackgroundBackupSession.create(
      user: user,
      auth: auth,
      firestore: firestore,
      driveRepository: DriveRepository(firestore: firestore),
      prefs: prefs,
      backupConfigs: {},
      fingerprints: {},
      scanFrequency: _BackgroundBackupScanFrequency.fromStorageKey(null),
    );
    if (session == null) return null;
    final expectedKey = base64Encode(await session.secretKey.extractBytes());
    final journal = await TransferJournal.open(
      preferences: prefs,
      uid: user.uid,
      scope: _localPrivateCacheScope(auth.app),
    );
    return FirestoreDriveBackend(
      firestore: firestore,
      auth: auth,
      uid: user.uid,
      key: session.secretKey,
      storage: session.storageService,
      ownerPrefix: session.objectKeyOwnerPrefix,
      metadata: session.uploadMetadataService,
      journal: journal,
      authorized: () async {
        await prefs.reload();
        return auth.currentUser?.uid == user.uid &&
            prefs.getBool(passphraseRequiredPrefKey) != true &&
            await stillEnabled() &&
            await LoginPasswordVault.instance.matchesPersistedStandardKey(
              expectedEmail: user.email,
              expectedKey: expectedKey,
            );
      },
    );
  }

  static const String backupConfigsPrefKey =
      LocalPrivateCacheCodec.backupConfigsPreferenceKey;
  static const String backupSignaturesPrefKey =
      LocalPrivateCacheCodec.backupFingerprintsPreferenceKey;
  static const String backupScanRatePrefKey = 'workspace_backup_scan_rate_v1';
  static const String backupBackgroundEnabledPrefKey =
      'workspace_backup_background_enabled_v1';
  static const String backupBackgroundPreferenceSetPrefKey =
      'workspace_backup_background_pref_set_v1';
  static const String passphraseRequiredPrefKey =
      'workspace_passphrase_required_v1';

  static const String foregroundHeartbeatPrefKey =
      'workspace_foreground_heartbeat_v1';
  static const String desktopWorkerHeartbeatPrefKey =
      'workspace_desktop_backup_worker_heartbeat_v1';

  static const Duration foregroundHeartbeatFreshness = Duration(seconds: 45);
  static const Duration desktopWorkerHeartbeatFreshness = Duration(seconds: 90);
  static const Duration backupResyncInterval = Duration(minutes: 15);
  static const String backupFingerprintOrphanBucket = '__orphan__';
  static const String _heartbeatDirectoryName = 'runtime';
  static const String _foregroundHeartbeatFileName = 'foreground_heartbeat.txt';
  static const String _desktopWorkerHeartbeatFileName =
      'desktop_worker_heartbeat.txt';
  static final List<int> _localDiagnosticKey = List<int>.unmodifiable(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );

  static void log(String scope, String message) {
    if (!kDebugMode) {
      return;
    }
    final timestamp = DateTime.now().toIso8601String();
    debugPrint(
      redactDiagnosticText('[RonikCloud.bg][$scope][$timestamp] $message'),
    );
  }

  static String errorCategory(Object error) {
    if (error is WasabiConfigurationException) return 'configuration';
    if (error is FirebaseAuthException) return 'authentication';
    if (error is FirebaseException) {
      final code = error.code.trim().toLowerCase();
      if (code == 'permission-denied') return 'authorization';
      if (code == 'unauthenticated') return 'authentication';
      if (code == 'unavailable' || code == 'deadline-exceeded') {
        return 'network';
      }
      return 'cloud';
    }
    if (error is FileSystemException) return 'filesystem';
    if (error is TimeoutException) return 'timeout';
    if (error is FormatException) return 'format';
    if (error is ArgumentError) return 'invalid-input';
    final type = error.runtimeType.toString().toLowerCase();
    if (type.contains('socket') || type.contains('network')) return 'network';
    if (type.contains('filesystem') || type.contains('file')) {
      return 'filesystem';
    }
    return 'operational';
  }

  static void logFailure(
    String scope,
    String event,
    Object error, {
    String? itemReference,
  }) {
    final normalizedEvent = event
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safeEvent = normalizedEvent.isEmpty ? 'unspecified' : normalizedEvent;
    final referenceCandidate = itemReference?.trim();
    final safeReference =
        referenceCandidate != null &&
            RegExp(r'^local-item-[a-f0-9]{12}$').hasMatch(referenceCandidate)
        ? referenceCandidate
        : null;
    log(
      scope,
      'event=$safeEvent category=${errorCategory(error)}'
      '${safeReference == null || safeReference.isEmpty ? '' : ' item=$safeReference'}.',
    );
  }

  static const Map<String, String> _contentTypeByExtension = <String, String>{
    'bmp': 'image/bmp',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'json': 'application/json',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'zip': 'application/zip',
  };

  static String thumbnailObjectKey({
    required String ownerPrefix,
    required String objectKey,
  }) => thumbnailStorageObjectKey(objectKey, fallbackPrefix: ownerPrefix);

  static String localItemDebugLabel(String value, {List<int>? diagnosticKey}) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'local-item-empty';
    }
    final key = diagnosticKey ?? _localDiagnosticKey;
    if (key.length < 16) {
      throw ArgumentError.value(
        diagnosticKey,
        'diagnosticKey',
        'Diagnostic keys must contain at least 16 bytes.',
      );
    }
    final digest = Hmac(sha256, key)
        .convert(utf8.encode('ronikdrive-local-diagnostic-v1\n$normalized'))
        .toString();
    return 'local-item-${digest.substring(0, 12)}';
  }

  static String opaqueObjectKey({required String ownerPrefix, Random? random}) {
    final normalizedOwner = ownerPrefix.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalizedOwner.isEmpty) {
      throw ArgumentError.value(ownerPrefix, 'ownerPrefix');
    }
    final secureRandom = random ?? Random.secure();
    final token = base64Url
        .encode(List<int>.generate(16, (_) => secureRandom.nextInt(256)))
        .replaceAll('=', '');
    return '$normalizedOwner/objects/'
        '${token.substring(0, 2).toLowerCase()}/'
        '${token.substring(2, 4).toLowerCase()}/$token';
  }

  @Deprecated('Use opaqueObjectKey().')
  static String opaqueBackupObjectKey({
    required String ownerPrefix,
    Random? random,
  }) {
    return opaqueObjectKey(ownerPrefix: ownerPrefix, random: random);
  }

  static Future<void> ensureFirebaseInitialized() async {
    registerNativeCloudForCurrentPlatform();
    if (Firebase.apps.isNotEmpty) {
      return;
    }
    await FirebaseEnvironmentBootstrap.initialize(
      productionDefaults: DefaultFirebaseOptions.currentPlatform,
    );
  }

  static Future<void> writeForegroundHeartbeat() async {
    try {
      final file = await _heartbeatFile(_foregroundHeartbeatFileName);
      await file.writeAsString(
        DateTime.now().millisecondsSinceEpoch.toString(),
        flush: true,
      );
    } catch (error) {
      logFailure('runtime', 'foreground_heartbeat_write', error);
    }
  }

  static Future<void> writeDesktopWorkerHeartbeat() async {
    try {
      final file = await _heartbeatFile(_desktopWorkerHeartbeatFileName);
      await file.writeAsString(
        DateTime.now().millisecondsSinceEpoch.toString(),
        flush: true,
      );
    } catch (error) {
      logFailure('runtime', 'desktop_heartbeat_write', error);
    }
  }

  static Future<bool> isForegroundAppActive() async {
    final heartbeat = await _readHeartbeat(
      _foregroundHeartbeatFileName,
      legacyPreferenceKey: foregroundHeartbeatPrefKey,
    );
    if (heartbeat == null || heartbeat <= 0) {
      return false;
    }
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(heartbeat),
    );
    return age <= foregroundHeartbeatFreshness;
  }

  static Future<bool> isDesktopWorkerAlive() async {
    final heartbeat = await _readHeartbeat(
      _desktopWorkerHeartbeatFileName,
      legacyPreferenceKey: desktopWorkerHeartbeatPrefKey,
    );
    if (heartbeat == null || heartbeat <= 0) {
      return false;
    }
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(heartbeat),
    );
    return age <= desktopWorkerHeartbeatFreshness;
  }

  static Future<File> _heartbeatFile(String fileName) async {
    dynamic baseDirectory;
    try {
      baseDirectory = await getApplicationSupportDirectory();
    } catch (_) {
      baseDirectory = await getTemporaryDirectory();
    }

    final heartbeatDirectory = Directory(
      p.join(baseDirectory.path, _heartbeatDirectoryName),
    );
    if (!await heartbeatDirectory.exists()) {
      await heartbeatDirectory.create(recursive: true);
    }

    return File(p.join(heartbeatDirectory.path, fileName));
  }

  static Future<int?> _readHeartbeat(
    String fileName, {
    required String legacyPreferenceKey,
  }) async {
    try {
      final file = await _heartbeatFile(fileName);
      if (await file.exists()) {
        final raw = (await file.readAsString()).trim();
        final parsed = int.tryParse(raw);
        if (parsed != null) {
          return parsed;
        }

        final modifiedAt = await file.lastModified();
        return modifiedAt.millisecondsSinceEpoch;
      }
    } catch (error) {
      logFailure('runtime', 'heartbeat_read', error);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getInt(legacyPreferenceKey);
    } catch (error) {
      logFailure('runtime', 'legacy_heartbeat_read', error);
      return null;
    }
  }

  static Future<BackgroundBackupSummary> runScheduledSync({
    String trigger = 'scheduled',
    Set<String>? forcedConfigPaths,
    bool notifyOnFailure = true,
  }) async {
    if (!supportsPersistentFolderBackups(
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
        ) &&
        !canRunPersistentBackupConfig(
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
          photoLibrary: true,
        )) {
      return const BackgroundBackupSummary(noEligibleConfigs: true);
    }
    UserActivityStore? activity;
    String? activityUid;
    try {
      log(
        'runner',
        'Starting background backup sync (trigger=$trigger, '
            'forcedConfigs=${forcedConfigPaths?.length ?? 0}).',
      );
      await ensureFirebaseInitialized();
      final notifications = NotificationService();

      if (await isForegroundAppActive()) {
        log(
          'runner',
          'Skipping background sync because the foreground app is active.',
        );
        return const BackgroundBackupSummary(
          skippedBecauseForegroundActive: true,
        );
      }

      final auth = FirebaseAuth.instanceFor(app: Firebase.app());
      final user = await _ensureBackgroundAuth(auth);
      if (user == null) {
        log('runner', 'Background sync could not authenticate a user session.');
        // No verified account: do not read another account's preferences or
        // route an alert to the previous user of this device.
        return const BackgroundBackupSummary(authRequired: true);
      }

      final firestore = ConfiguredFirestore.instanceFor(app: Firebase.app());
      final prefs = await SharedPreferences.getInstance();
      activityUid = user.uid;
      activity = UserActivityStore(
        prefs,
        uid: user.uid,
        scope: _localPrivateCacheScope(auth.app),
      );
      // The foreground app can change backup preferences in another process.
      await prefs.reload();
      final backgroundEnabled =
          await _readAccountScopedBoolPreference(
            prefs,
            backupBackgroundEnabledPrefKey,
            user.uid,
          ) ??
          true;
      if (!backgroundEnabled) {
        log('runner', 'Background sync is disabled in preferences.');
        return const BackgroundBackupSummary(backgroundDisabled: true);
      }

      final passphraseRequired =
          prefs.getBool(passphraseRequiredPrefKey) == true;
      if (passphraseRequired) {
        log(
          'runner',
          'Background sync is blocked because secure passphrase mode is enabled.',
        );
        await notifications.record(
          activity,
          ActivityKind.backgroundLocked,
          alert: notifyOnFailure,
          accountCurrent: () =>
              FirebaseAuth.instanceFor(app: Firebase.app()).currentUser?.uid ==
              activityUid,
        );
        return const BackgroundBackupSummary(unsupportedSecureMode: true);
      }

      final privateCache = LocalPrivateCachePreferences(
        preferences: prefs,
        uid: user.uid,
        scope: _localPrivateCacheScope(auth.app),
      );
      final backupCacheRead = await privateCache.read(
        baseKey: backupConfigsPrefKey,
        namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
      );
      if (backupCacheRead.temporarilyUnavailable) {
        log(
          'runner',
          'Background backup settings are waiting for the device keychain.',
        );
        await notifications.record(
          activity,
          ActivityKind.backgroundLocked,
          alert: notifyOnFailure,
          accountCurrent: () =>
              FirebaseAuth.instanceFor(app: Firebase.app()).currentUser?.uid ==
              activityUid,
        );
        return const BackgroundBackupSummary(initializationFailed: true);
      }
      final backupSignatureCacheRead = await privateCache.read(
        baseKey: backupSignaturesPrefKey,
        namespace: LocalPrivateCacheCodec.backupFingerprintsNamespace,
      );
      final scanRaw = await _readAccountScopedStringPreference(
        prefs,
        backupScanRatePrefKey,
        user.uid,
      );

      final backupConfigs = _decodeBackupConfigs(backupCacheRead.value);
      final enabledConfigs = backupConfigs.values
          .where(
            (config) =>
                config.enabled &&
                canRunPersistentBackupConfig(
                  isWeb: kIsWeb,
                  platform: defaultTargetPlatform,
                  photoLibrary: config.photoLibrary,
                  hasFolderBookmark: config.accessBookmark?.isNotEmpty == true,
                ),
          )
          .where(
            (config) =>
                forcedConfigPaths == null ||
                forcedConfigPaths.contains(
                  _normalizedLocalPath(config.localPath),
                ),
          )
          .toList(growable: false);
      if (enabledConfigs.isEmpty) {
        log('runner', 'No enabled background backup configs were found.');
        return const BackgroundBackupSummary(noEligibleConfigs: true);
      }

      final fingerprints = _decodeBackupFingerprints(
        backupSignatureCacheRead.value,
        backupConfigs.values,
      );
      final scanFrequency = _BackgroundBackupScanFrequency.fromStorageKey(
        scanRaw,
      );
      final session = await _BackgroundBackupSession.create(
        user: user,
        auth: auth,
        firestore: firestore,
        driveRepository: DriveRepository(firestore: firestore),
        prefs: prefs,
        backupConfigs: backupConfigs,
        fingerprints: fingerprints,
        scanFrequency: scanFrequency,
      );

      if (session == null) {
        log('runner', 'Background sync could not create a backup session.');
        await notifications.record(
          activity,
          ActivityKind.backgroundProblem,
          alert: notifyOnFailure,
          accountCurrent: () =>
              FirebaseAuth.instanceFor(app: Firebase.app()).currentUser?.uid ==
              activityUid,
        );
        return const BackgroundBackupSummary(initializationFailed: true);
      }

      await notifications.record(
        activity,
        ActivityKind.backgroundLocked,
        resolved: true,
        accountCurrent: () =>
            FirebaseAuth.instanceFor(app: Firebase.app()).currentUser?.uid ==
            activityUid,
      );
      final now = DateTime.now();
      final dueConfigs = enabledConfigs
          .where((config) {
            if (forcedConfigPaths != null) {
              return true;
            }
            final lastSynced = config.lastSynced;
            if (lastSynced == null || lastSynced.isAfter(now)) {
              return true;
            }
            final minimumInterval =
                scanFrequency.interval.compareTo(backupResyncInterval) >= 0
                ? scanFrequency.interval
                : backupResyncInterval;
            return now.difference(lastSynced) >= minimumInterval;
          })
          .toList(growable: false);

      if (dueConfigs.isEmpty) {
        log('runner', 'No background backup configs are due for syncing.');
        return const BackgroundBackupSummary(noEligibleConfigs: true);
      }

      var scannedFiles = 0;
      var uploadedFiles = 0;
      var failedFiles = 0;

      for (final config in dueConfigs) {
        final result = await session.syncConfig(config);
        scannedFiles += result.scannedFiles;
        uploadedFiles += result.uploadedFiles;
        failedFiles += result.failedFiles;
      }

      await session.persist();
      log(
        'runner',
        'Background sync finished: scanned=$scannedFiles, uploaded=$uploadedFiles, failed=$failedFiles.',
      );

      if (auth.currentUser?.uid == user.uid) {
        if (failedFiles > 0) {
          await notifications.record(
            activity,
            ActivityKind.backgroundProblem,
            alert: notifyOnFailure,
            accountCurrent: () =>
                FirebaseAuth.instanceFor(
                  app: Firebase.app(),
                ).currentUser?.uid ==
                activityUid,
          );
        } else if (forcedConfigPaths == null &&
            dueConfigs.length == enabledConfigs.length) {
          // A successful watched subset cannot clear failures in other folders.
          await notifications.record(
            activity,
            ActivityKind.backgroundProblem,
            resolved: true,
            accountCurrent: () =>
                FirebaseAuth.instanceFor(
                  app: Firebase.app(),
                ).currentUser?.uid ==
                activityUid,
          );
        }
      }

      return BackgroundBackupSummary(
        scannedFiles: scannedFiles,
        uploadedFiles: uploadedFiles,
        failedFiles: failedFiles,
      );
    } catch (error) {
      if (activity != null &&
          FirebaseAuth.instanceFor(app: Firebase.app()).currentUser?.uid ==
              activityUid) {
        await NotificationService().record(
          activity,
          ActivityKind.backgroundProblem,
          alert: notifyOnFailure,
          accountCurrent: () =>
              FirebaseAuth.instanceFor(app: Firebase.app()).currentUser?.uid ==
              activityUid,
        );
      }
      logFailure('runner', 'scheduled_sync', error);
      return const BackgroundBackupSummary(initializationFailed: true);
    }
  }

  static Future<List<BackgroundBackupWatchConfig>>
  loadEnabledWatchConfigs() async {
    if (!supportsPersistentFolderBackups(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      return const <BackgroundBackupWatchConfig>[];
    }
    await ensureFirebaseInitialized();
    final auth = FirebaseAuth.instanceFor(app: Firebase.app());
    final user = await _ensureBackgroundAuth(auth);
    if (user == null) {
      return const <BackgroundBackupWatchConfig>[];
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final backgroundEnabled =
        await _readAccountScopedBoolPreference(
          prefs,
          backupBackgroundEnabledPrefKey,
          user.uid,
        ) ??
        true;
    if (!backgroundEnabled ||
        prefs.getBool(passphraseRequiredPrefKey) == true) {
      return const <BackgroundBackupWatchConfig>[];
    }

    final backupCacheRead =
        await LocalPrivateCachePreferences(
          preferences: prefs,
          uid: user.uid,
          scope: _localPrivateCacheScope(auth.app),
        ).read(
          baseKey: backupConfigsPrefKey,
          namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
        );
    if (backupCacheRead.temporarilyUnavailable) {
      log(
        'watch',
        'Backup folder watches are waiting for the device keychain.',
      );
      return const <BackgroundBackupWatchConfig>[];
    }
    final configs = _decodeBackupConfigs(backupCacheRead.value);
    return configs.values
        .where(
          (config) =>
              config.enabled &&
              !config.photoLibrary &&
              canRunPersistentBackupConfig(
                isWeb: kIsWeb,
                platform: defaultTargetPlatform,
                photoLibrary: false,
                hasFolderBookmark: config.accessBookmark?.isNotEmpty == true,
              ),
        )
        .map(
          (config) => BackgroundBackupWatchConfig(
            localPath: config.localPath,
            normalizedLocalPath: _normalizedLocalPath(config.localPath),
            accessBookmark: config.accessBookmark,
            accountScope:
                '${_localPrivateCacheScope(auth.app)}\u0000${user.uid}',
          ),
        )
        .toList(growable: false);
  }

  static Future<User?> _ensureBackgroundAuth(FirebaseAuth auth) async {
    final current = auth.currentUser;
    if (current != null) {
      return auth.currentUser ?? current;
    }

    final credentials = await LoginPasswordVault.instance.restoreCredentials();
    final email = credentials.email;
    final password = credentials.password;
    if (email == null ||
        email.isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }

    try {
      final result = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException catch (error) {
      logFailure('auth', 'password_sign_in', error);
      return null;
    } catch (error) {
      logFailure('auth', 'password_sign_in', error);
      return null;
    }
  }

  static String _accountScopedPrefKey(String baseKey, String uid) {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) {
      return baseKey;
    }
    final safeUid = trimmedUid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${baseKey}_$safeUid';
  }

  static String _localPrivateCacheScope(FirebaseApp app) {
    try {
      final projectId = app.options.projectId.trim();
      if (projectId.isNotEmpty) {
        return projectId;
      }
    } catch (_) {
      // Firebase test doubles may not expose production app options.
    }
    try {
      final appName = app.name.trim();
      if (appName.isNotEmpty) {
        return appName;
      }
    } catch (_) {
      // Fall through to a deterministic local-only scope.
    }
    return 'local-firebase-app';
  }

  static Future<String?> _readAccountScopedStringPreference(
    SharedPreferences prefs,
    String baseKey,
    String uid,
  ) async {
    final scopedKey = _accountScopedPrefKey(baseKey, uid);
    final scopedValue = prefs.getString(scopedKey);
    if (scopedValue != null) {
      return scopedValue;
    }

    final legacyValue = prefs.getString(baseKey);
    if (legacyValue == null) {
      return null;
    }

    try {
      await prefs.setString(scopedKey, legacyValue);
      await prefs.remove(baseKey);
    } catch (error) {
      logFailure('privacy', 'string_preference_migration', error);
    }
    return legacyValue;
  }

  static Future<bool?> _readAccountScopedBoolPreference(
    SharedPreferences prefs,
    String baseKey,
    String uid,
  ) async {
    final scopedKey = _accountScopedPrefKey(baseKey, uid);
    if (prefs.containsKey(scopedKey)) {
      return prefs.getBool(scopedKey);
    }

    if (!prefs.containsKey(baseKey)) {
      return null;
    }

    final legacyValue = prefs.getBool(baseKey);
    try {
      if (legacyValue != null) {
        await prefs.setBool(scopedKey, legacyValue);
      }
      await prefs.remove(baseKey);
    } catch (error) {
      logFailure('privacy', 'boolean_preference_migration', error);
    }
    return legacyValue;
  }

  static Map<String, _BackgroundBackupConfig> _decodeBackupConfigs(
    String? raw,
  ) {
    final configs = <String, _BackgroundBackupConfig>{};
    if (raw == null || raw.trim().isEmpty) {
      return configs;
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      for (final entry in decoded) {
        final config = _BackgroundBackupConfig.fromJson(
          Map<String, dynamic>.from(entry as Map),
        );
        configs[config.localPath] = config;
      }
    } catch (error) {
      logFailure('privacy', 'backup_config_decode', error);
    }
    return configs;
  }

  static Map<String, Map<String, _BackgroundBackupFingerprint>>
  _decodeBackupFingerprints(
    String? raw,
    Iterable<_BackgroundBackupConfig> configs,
  ) {
    final nested = <String, Map<String, _BackgroundBackupFingerprint>>{};
    if (raw == null || raw.trim().isEmpty) {
      for (final config in configs) {
        final normalized = _normalizedLocalPath(config.localPath);
        if (normalized.isNotEmpty) {
          nested.putIfAbsent(
            normalized,
            () => <String, _BackgroundBackupFingerprint>{},
          );
        }
      }
      return nested;
    }

    try {
      final decoded = jsonDecode(raw);
      final configsPayload = decoded is Map ? decoded['configs'] : null;
      if (configsPayload is List) {
        for (final entry in configsPayload) {
          if (entry is! Map) {
            continue;
          }
          final rawPath = (entry['path'] as String?) ?? '';
          final normalizedConfig = _normalizedLocalPath(rawPath);
          if (normalizedConfig.isEmpty) {
            continue;
          }
          final bucket = nested.putIfAbsent(
            normalizedConfig,
            () => <String, _BackgroundBackupFingerprint>{},
          );
          final files = entry['files'];
          if (files is List) {
            for (final file in files) {
              if (file is! Map) {
                continue;
              }
              final fingerprint = _BackgroundBackupFingerprint.fromJson(
                Map<String, dynamic>.from(file),
              );
              final normalizedPath = _normalizedLocalPath(
                fingerprint.localPath,
              );
              bucket[normalizedPath] = fingerprint.copyWith(
                localPath: normalizedPath,
              );
            }
          }
        }

        final orphanPayload = decoded is Map ? decoded['orphans'] : null;
        if (orphanPayload is List) {
          final orphanBucket = nested.putIfAbsent(
            backupFingerprintOrphanBucket,
            () => <String, _BackgroundBackupFingerprint>{},
          );
          for (final entry in orphanPayload) {
            if (entry is! Map) {
              continue;
            }
            final fingerprint = _BackgroundBackupFingerprint.fromJson(
              Map<String, dynamic>.from(entry),
            );
            final normalizedPath = _normalizedLocalPath(fingerprint.localPath);
            orphanBucket[normalizedPath] = fingerprint.copyWith(
              localPath: normalizedPath,
            );
          }
        }
      } else {
        final flatFingerprints = <String, _BackgroundBackupFingerprint>{};
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is! Map) {
              continue;
            }
            final fingerprint = _BackgroundBackupFingerprint.fromJson(
              Map<String, dynamic>.from(entry),
            );
            final normalizedPath = _normalizedLocalPath(fingerprint.localPath);
            flatFingerprints[normalizedPath] = fingerprint.copyWith(
              localPath: normalizedPath,
            );
          }
        } else if (decoded is Map) {
          decoded.forEach((_, value) {
            if (value is! Map) {
              return;
            }
            final fingerprint = _BackgroundBackupFingerprint.fromJson(
              Map<String, dynamic>.from(value),
            );
            final normalizedPath = _normalizedLocalPath(fingerprint.localPath);
            flatFingerprints[normalizedPath] = fingerprint.copyWith(
              localPath: normalizedPath,
            );
          });
        }

        final configPaths = configs
            .map((config) => _normalizedLocalPath(config.localPath))
            .where((path) => path.isNotEmpty)
            .toList(growable: false);

        for (final entry in flatFingerprints.entries) {
          final path = entry.key;
          final fingerprint = entry.value;
          var assigned = false;
          for (final configPath in configPaths) {
            if (path == configPath ||
                path.startsWith('$configPath${p.separator}')) {
              final bucket = nested.putIfAbsent(
                configPath,
                () => <String, _BackgroundBackupFingerprint>{},
              );
              bucket[path] = fingerprint;
              assigned = true;
              break;
            }
          }
          if (!assigned) {
            final bucket = nested.putIfAbsent(
              backupFingerprintOrphanBucket,
              () => <String, _BackgroundBackupFingerprint>{},
            );
            bucket[path] = fingerprint;
          }
        }
      }
    } catch (error) {
      logFailure('privacy', 'backup_fingerprint_decode', error);
    }

    for (final config in configs) {
      final normalized = _normalizedLocalPath(config.localPath);
      if (normalized.isEmpty) {
        continue;
      }
      nested.putIfAbsent(
        normalized,
        () => <String, _BackgroundBackupFingerprint>{},
      );
    }
    return nested;
  }

  static String _normalizedLocalPath(String path) {
    final normalized = p.normalize(path);
    if (Platform.isWindows) {
      return normalized.toLowerCase();
    }
    return normalized;
  }

  static String normalizeBackupRelativePath(String relativePath) {
    final normalized = relativePath
        .split(RegExp(r'[\\/]+'))
        .where((segment) => segment.trim().isNotEmpty)
        .join('/');
    if (normalized.isEmpty) {
      return '';
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static String backupObjectKeyName(String backupPathHash) {
    final trimmed = backupPathHash.trim();
    if (trimmed.isEmpty) {
      return 'backup-file';
    }
    return 'backup-$trimmed';
  }

  static String sanitizeFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    return sanitized.trim();
  }

  static String sanitizePathSegment(String segment) {
    final sanitized = segment.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-');
    return sanitized.trim();
  }

  static String encodePathSegmentForObjectKey(
    String segment, {
    String fallback = 'segment',
  }) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) {
      final digest = sha1.convert(utf8.encode(fallback)).toString();
      return '$fallback-${digest.substring(0, 8)}';
    }

    final sanitized = trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-');
    if (sanitized.isEmpty) {
      final digest = sha1.convert(utf8.encode(trimmed)).toString();
      return '$fallback-${digest.substring(0, 8)}';
    }

    if (sanitized == trimmed) {
      return sanitized;
    }

    final digest = sha1.convert(utf8.encode(trimmed)).toString();
    return '$sanitized-${digest.substring(0, 8)}';
  }

  static List<String> normalizeRemoteFolderSegments(String folderName) {
    return folderName
        .split(RegExp(r'[\\/]+'))
        .map(sanitizePathSegment)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> objectKeyFolderSegments(String folderName) {
    return folderName
        .split(RegExp(r'[\\/]+'))
        .where((segment) => segment.trim().isNotEmpty)
        .map(
          (segment) =>
              encodePathSegmentForObjectKey(segment, fallback: 'folder'),
        )
        .toList(growable: false);
  }
}
