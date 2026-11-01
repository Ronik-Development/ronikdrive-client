import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../privacy/privacy_debug_logging.dart';
import 'background_backup_runner.dart';
import 'desktop_worker_lifecycle.dart';
import '../desktop_drive/desktop_drive_runtime.dart';
import 'platform_io.dart';
import 'persistent_folder_access.dart';

const String _periodicSyncUniqueName = 'periodic-sync-task';
const String _periodicSyncTaskName = 'syncData';
const String _desktopWorkerArgument = '--background-backup-worker';
const String _driveWorkerArgument = '--desktop-drive-worker';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    installPrivacySafeDebugPrint();

    // Apple delivers the BGTaskScheduler identifier, not Android's taskName.
    if (task != _periodicSyncTaskName && task != _periodicSyncUniqueName) {
      return true;
    }

    await BackgroundBackupRunner.runScheduledSync(
      trigger: 'mobile-workmanager',
      notifyOnFailure: true,
    );
    return true;
  });
}

class BackgroundService {
  static bool _workmanagerInitialized = false;
  static Timer? _foregroundHeartbeatTimer;
  static DateTime? _lastDesktopSpawnAttemptAt;
  static DateTime? _lastDriveSpawnAttemptAt;

  static bool get supportsDetachedDesktopWorker {
    if (kIsWeb) {
      return false;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      default:
        return false;
    }
  }

  static bool isDesktopWorkerInvocation(List<String> args) {
    if (!supportsDetachedDesktopWorker) {
      return false;
    }
    return args.contains(_desktopWorkerArgument) ||
        args.contains(_driveWorkerArgument);
  }

  static Future<void> initialize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS) ||
        _workmanagerInitialized) {
      return;
    }

    await Workmanager().initialize(callbackDispatcher);
    _workmanagerInitialized = true;
  }

  static Future<void> registerPeriodicSync() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    await Workmanager().registerPeriodicTask(
      _periodicSyncUniqueName,
      _periodicSyncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> startForegroundHeartbeat() async {
    if (kIsWeb || _foregroundHeartbeatTimer != null) {
      return;
    }

    await BackgroundBackupRunner.writeForegroundHeartbeat();
    _foregroundHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(BackgroundBackupRunner.writeForegroundHeartbeat()),
    );
  }

  static Future<void> ensureNativeDriveWorkerRunning() async {
    if (kIsWeb ||
        !kReleaseMode ||
        defaultTargetPlatform != TargetPlatform.windows ||
        !DesktopDriveRuntime.supported) {
      return;
    }
    final now = DateTime.now();
    if (_lastDriveSpawnAttemptAt != null &&
        now.difference(_lastDriveSpawnAttemptAt!) <
            const Duration(seconds: 30)) {
      return;
    }
    _lastDriveSpawnAttemptAt = now;
    try {
      await Process.start(
        Platform.resolvedExecutable,
        const [_driveWorkerArgument],
        workingDirectory: Directory.current.path,
        mode: ProcessStartMode.detached,
      );
    } catch (error) {
      BackgroundBackupRunner.logFailure(
        'worker',
        'native_drive_worker_start',
        error,
      );
    }
  }

  static Future<void> ensureDesktopWorkerRunning() async {
    // Explorer has its own lease: an older backup worker must not prevent it
    // from starting, and enabling Explorer must not change backup preferences.
    await ensureNativeDriveWorkerRunning();
    if (!supportsDetachedDesktopWorker) {
      return;
    }

    // A detached desktop worker keeps the built executable open on Windows.
    // In debug/profile builds that prevents Flutter from relinking the runner
    // on the next launch, which surfaces as LNK1104 on cloud_storage.exe.
    if (!kReleaseMode) {
      return;
    }

    final now = DateTime.now();
    if (_lastDesktopSpawnAttemptAt != null &&
        now.difference(_lastDesktopSpawnAttemptAt!) <
            const Duration(seconds: 10)) {
      return;
    }

    if (await BackgroundBackupRunner.isDesktopWorkerAlive()) {
      return;
    }

    _lastDesktopSpawnAttemptAt = now;

    try {
      final executable = Platform.resolvedExecutable;
      if (executable.trim().isEmpty) {
        return;
      }

      await Process.start(
        executable,
        const <String>[_desktopWorkerArgument],
        workingDirectory: Directory.current.path,
        mode: ProcessStartMode.detached,
      );
    } catch (error) {
      BackgroundBackupRunner.logFailure(
        'worker',
        'desktop_worker_start',
        error,
      );
    }
  }

  static Future<void> runDesktopWorker({bool nativeDriveOnly = false}) async {
    if (!supportsDetachedDesktopWorker) {
      return;
    }

    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    var exitCode = 0;
    try {
      await runWithDesktopWorkerLease(() async {
        if (!nativeDriveOnly) return _DesktopBackgroundBackupWorker().run();
        try {
          while (await DesktopDriveRuntime.refresh()) {
            await Future<void>.delayed(const Duration(seconds: 10));
          }
        } finally {
          await DesktopDriveRuntime.stop();
        }
      }, nativeDrive: nativeDriveOnly);
    } catch (error) {
      exitCode = 1;
      BackgroundBackupRunner.logFailure('worker', 'desktop_worker_exit', error);
    }
    // Returning from Dart main does not terminate a native Flutter runner.
    // Do not leave an invisible, idle process locking the installed executable.
    finishDesktopWorker(exitCode);
  }
}

class _DesktopBackgroundBackupWorker {
  static const Duration _configRefreshInterval = Duration(seconds: 30);
  static const Duration _eventDebounceInterval = Duration(seconds: 3);

  final Completer<void> _closed = Completer<void>();
  final Map<String, StreamSubscription<FileSystemEvent>> _watchers =
      <String, StreamSubscription<FileSystemEvent>>{};
  final Map<String, FolderAccessLease> _folderLeases = {};
  final Map<String, BackgroundBackupWatchConfig> _watcherConfigurations = {};
  Future<bool>? _watcherRefresh;
  final Map<String, Timer> _eventDebouncers = <String, Timer>{};
  final Set<String> _pendingForcedPaths = <String>{};

  Timer? _heartbeatTimer;
  Timer? _configRefreshTimer;
  Timer? _fallbackScanTimer;
  Future<void>? _activeSync;
  bool _pendingFullSync = false;
  bool _stopping = false;

  bool get _supportsNativeDirectoryWatch =>
      // Dart inotify cannot watch recursively on Linux. The existing periodic
      // recursive scanner handles Linux without missing nested changes behind
      // a seemingly active root-only watcher.
      defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> run() async {
    await BackgroundBackupRunner.writeDesktopWorkerHeartbeat();
    final hasConfigs = await _refreshWatchers();
    await BackgroundService.ensureNativeDriveWorkerRunning();
    final hasNativeDrive =
        defaultTargetPlatform != TargetPlatform.windows &&
        await DesktopDriveRuntime.refresh();
    if (!hasConfigs && !hasNativeDrive) {
      await _shutdown(reason: 'no watch configs available at startup');
      return;
    }

    // Initial uploads can take longer than the heartbeat freshness window.
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(BackgroundBackupRunner.writeDesktopWorkerHeartbeat()),
    );

    final initialForcedPaths = _watchers.isEmpty
        ? null
        : _watchers.keys.toSet();
    await _runSync(
      trigger: 'desktop-worker-start',
      forcedConfigPaths: initialForcedPaths,
      notifyOnFailure: true,
    );

    _configRefreshTimer = Timer.periodic(
      _configRefreshInterval,
      (_) => unawaited(_handleConfigRefresh()),
    );
    _fallbackScanTimer = Timer.periodic(
      BackgroundBackupRunner.backupResyncInterval,
      (_) => unawaited(
        _runSync(trigger: 'desktop-worker-periodic', notifyOnFailure: true),
      ),
    );

    await _closed.future;
  }

  Future<void> _handleConfigRefresh() async {
    if (_stopping) {
      return;
    }

    await BackgroundBackupRunner.writeDesktopWorkerHeartbeat();
    final hasConfigs = await _refreshWatchers();
    final hasNativeDrive =
        defaultTargetPlatform != TargetPlatform.windows &&
        await DesktopDriveRuntime.refresh();
    if (!hasConfigs && !hasNativeDrive) {
      await _shutdown(reason: 'all background watch configs were removed');
    }
  }

  Future<bool> _refreshWatchers() => _watcherRefresh ??= _refreshWatchersOnce()
      .whenComplete(() => _watcherRefresh = null);

  Future<bool> _refreshWatchersOnce() async {
    if (_stopping) return false;
    List<BackgroundBackupWatchConfig> configs;
    try {
      configs = await BackgroundBackupRunner.loadEnabledWatchConfigs();
    } catch (error) {
      BackgroundBackupRunner.logFailure('watch', 'watcher_refresh', error);
      return _watchers.isNotEmpty;
    }

    if (_stopping) return false;
    final nextByNormalized = <String, BackgroundBackupWatchConfig>{
      for (final config in configs) config.normalizedLocalPath: config,
    };

    final stalePaths = _watchers.keys
        .where(
          (path) =>
              !nextByNormalized.containsKey(path) ||
              _watcherConfigurations[path]?.accountScope !=
                  nextByNormalized[path]?.accountScope ||
              _watcherConfigurations[path]?.accessBookmark !=
                  nextByNormalized[path]?.accessBookmark,
        )
        .toList(growable: false);
    for (final path in stalePaths) {
      await _watchers.remove(path)?.cancel();
      await _folderLeases.remove(path)?.close();
      _watcherConfigurations.remove(path);
      _eventDebouncers.remove(path)?.cancel();
    }

    for (final entry in nextByNormalized.entries) {
      if (_watchers.containsKey(entry.key)) {
        continue;
      }

      FolderAccessLease? lease;
      var retained = false;
      try {
        lease = await PersistentFolderAccess.acquire(
          path: entry.value.localPath,
          bookmark: entry.value.accessBookmark,
        );
        if (_stopping) continue;
        final directory = Directory(entry.value.localPath);
        final watcherLabel = BackgroundBackupRunner.localItemDebugLabel(
          entry.value.normalizedLocalPath,
        );
        if (!await directory.exists() || _stopping) {
          continue;
        }

        if (!_supportsNativeDirectoryWatch) {
          if (kDebugMode) {
            debugPrint(
              'Skipping native backup watcher for $watcherLabel; periodic scans '
              'remain active.',
            );
          }
          continue;
        }

        try {
          _watchers[entry.key] = directory.watch(recursive: true).listen((
            event,
          ) {
            if (_shouldReactToEvent(event)) {
              _queueSync(entry.value.normalizedLocalPath);
            }
          }, onError: (_) => _queueSync(entry.value.normalizedLocalPath));
          _folderLeases[entry.key] = lease;
          _watcherConfigurations[entry.key] = entry.value;
          retained = true;
        } catch (error) {
          BackgroundBackupRunner.logFailure(
            'watch',
            'watcher_start',
            error,
            itemReference: watcherLabel,
          );
        }
      } on FolderAccessException catch (error) {
        BackgroundBackupRunner.logFailure('watch', 'folder_access', error);
      } finally {
        if (!retained) await lease?.close();
      }
    }

    return nextByNormalized.isNotEmpty;
  }

  bool _shouldReactToEvent(FileSystemEvent event) {
    if (event is FileSystemMoveEvent) {
      return true;
    }
    if (event is FileSystemDeleteEvent) {
      return true;
    }
    if (event is FileSystemCreateEvent) {
      return !event.isDirectory;
    }
    if (event is FileSystemModifyEvent) {
      return !event.isDirectory;
    }
    return !event.isDirectory;
  }

  void _queueSync(String normalizedPath) {
    if (_stopping) {
      return;
    }

    _eventDebouncers.remove(normalizedPath)?.cancel();
    _eventDebouncers[normalizedPath] = Timer(_eventDebounceInterval, () {
      _eventDebouncers.remove(normalizedPath);
      unawaited(
        _runSync(
          trigger: 'desktop-worker-watch',
          forcedConfigPaths: <String>{normalizedPath},
          notifyOnFailure: false,
        ),
      );
    });
  }

  Future<void> _runSync({
    required String trigger,
    Set<String>? forcedConfigPaths,
    required bool notifyOnFailure,
  }) async {
    if (_stopping) {
      return;
    }

    if (_activeSync != null) {
      if (forcedConfigPaths == null) {
        _pendingFullSync = true;
      } else if (!_pendingFullSync) {
        _pendingForcedPaths.addAll(forcedConfigPaths);
      }
      return;
    }

    final completer = Completer<void>();
    _activeSync = completer.future;
    try {
      var nextTrigger = trigger;
      var nextForcedPaths = forcedConfigPaths;
      var nextNotifyOnFailure = notifyOnFailure;

      while (!_stopping) {
        await BackgroundBackupRunner.writeDesktopWorkerHeartbeat();
        await BackgroundBackupRunner.runScheduledSync(
          trigger: nextTrigger,
          forcedConfigPaths: nextForcedPaths,
          notifyOnFailure: nextNotifyOnFailure,
        );

        if (_pendingFullSync) {
          _pendingFullSync = false;
          nextTrigger = 'desktop-worker-pending-full';
          nextForcedPaths = null;
          nextNotifyOnFailure = true;
          continue;
        }

        if (_pendingForcedPaths.isNotEmpty) {
          nextTrigger = 'desktop-worker-pending-watch';
          nextForcedPaths = Set<String>.from(_pendingForcedPaths);
          _pendingForcedPaths.clear();
          nextNotifyOnFailure = false;
          continue;
        }

        break;
      }
    } finally {
      _activeSync = null;
      completer.complete();
    }
  }

  Future<void> _shutdown({String? reason}) async {
    if (_stopping) {
      return;
    }
    _stopping = true;
    await DesktopDriveRuntime.stop();

    if (kDebugMode && reason != null && reason.trim().isNotEmpty) {
      debugPrint('Stopping the desktop background worker.');
    }

    _heartbeatTimer?.cancel();
    _configRefreshTimer?.cancel();
    _fallbackScanTimer?.cancel();

    for (final timer in _eventDebouncers.values) {
      timer.cancel();
    }
    _eventDebouncers.clear();

    final watchers = _watchers.values.toList(growable: false);
    _watchers.clear();
    for (final watcher in watchers) {
      await watcher.cancel();
    }
    final leases = _folderLeases.values.toList(growable: false);
    _folderLeases.clear();
    _watcherConfigurations.clear();
    for (final lease in leases) {
      await lease.close();
    }

    if (!_closed.isCompleted) {
      _closed.complete();
    }
  }
}
