import 'dart:io';

import 'package:cloud_storage/src/shared/background_backup_runner.dart';
import 'package:cloud_storage/src/shared/background_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String section(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(start, greaterThanOrEqualTo(0), reason: startMarker);
  expect(end, greaterThan(start), reason: endMarker);
  return source.substring(start, end);
}

void expectGuardBefore(String body, String guard, String sideEffect) {
  final guardIndex = body.indexOf(guard);
  final effectIndex = body.indexOf(sideEffect);
  expect(guardIndex, greaterThanOrEqualTo(0), reason: guard);
  expect(effectIndex, greaterThan(guardIndex), reason: sideEffect);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'macOS startup failure preserves encrypted backup state',
    () async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
      const protectedConfig = 'opaque-account-encrypted-backup-config';
      SharedPreferences.setMockInitialValues({
        BackgroundBackupRunner.backupConfigsPrefKey: protectedConfig,
        BackgroundBackupRunner.backupBackgroundEnabledPrefKey: true,
      });

      final summary = await BackgroundBackupRunner.runScheduledSync(
        trigger: 'macos-gate-regression',
        forcedConfigPaths: {'/unavailable-selected-folder'},
      );
      // No native Firebase engine is registered in this unit-test process.
      // A supported platform must fail initialization without clearing config.
      expect(summary.initializationFailed, isTrue);
      expect(summary.uploadedFiles, 0);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(BackgroundBackupRunner.backupConfigsPrefKey),
        protectedConfig,
      );
      expect(
        preferences.getBool(
          BackgroundBackupRunner.backupBackgroundEnabledPrefKey,
        ),
        isTrue,
      );

      // Upgraded installations can still receive a worker argument from an older
      // process. It must remain classified as a worker, not open another window.
      expect(
        BackgroundService.isDesktopWorkerInvocation([
          '--background-backup-worker',
        ]),
        isTrue,
      );
    },
  );

  test('foreground backup gates selection, restored scans and watchers', () {
    final source = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();
    expectGuardBefore(
      section(
        source,
        'Future<void> _chooseAndAddBackupFolder(',
        'Future<void> _startBackupListener(',
      ),
      '!_supportsPersistentFolderBackups',
      'FilePicker.platform.getDirectoryPath(',
    );
    expectGuardBefore(
      section(
        source,
        'Future<void> _startBackupListener(',
        '_BackupFolderConfig? _backupConfigForLocalPath(',
      ),
      '!_canRunBackupConfig(config)',
      'Directory(config.localPath)',
    );
    expectGuardBefore(
      section(
        source,
        'Future<void> _runBackupNow(',
        'Future<_BackupFileResult> _handleBackupFile(',
      ),
      '!_canRunBackupConfig(config)',
      'Directory(config.localPath)',
    );
    expectGuardBefore(
      section(
        source,
        'Future<void> _activateConfiguredBackgroundBackups(',
        'Future<void> _maybeShowWorkspaceWalkthrough(',
      ),
      '!_canRunBackupConfig(config)',
      '_startBackupListener(config)',
    );
    expectGuardBefore(
      section(
        source,
        'void _updateBackupScanTimerState(',
        'void _runScheduledBackupScans(',
      ),
      '_canRunBackupConfig(config)',
      'Timer.periodic(',
    );
    expectGuardBefore(
      section(
        source,
        'void _runScheduledBackupScans(',
        'String _sanitizeFileName(',
      ),
      '!_canRunBackupConfig(config)',
      '_runBackupNow(config, quiet: true)',
    );

    final oneShotUpload = section(
      source,
      'Future<void> _pickAndUploadFolderWithinIntent(',
      'Future<List<_PreparedUploadFile>> _collectWebUploadItems(',
    );
    expect(oneShotUpload, contains('FilePicker.platform.getDirectoryPath('));
    expect(oneShotUpload, isNot(contains('_supportsPersistentFolderBackups')));
    expect(oneShotUpload, isNot(contains('_canRunBackupConfig')));
  });
}
