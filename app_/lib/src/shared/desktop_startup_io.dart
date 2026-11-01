import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'desktop_startup_linux_entry.dart';

class DesktopStartup {
  static const _channel = MethodChannel('ronikcloud/startup');
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'RonikCloudBackup';
  static bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<File> _linuxEntry() async {
    final configured = Platform.environment['XDG_CONFIG_HOME'];
    final userHome = Platform.environment['HOME'];
    final root = configured != null && p.isAbsolute(configured)
        ? configured
        : userHome == null
        ? null
        : p.join(userHome, '.config');
    if (root == null) {
      throw StateError('Cannot locate the user configuration directory.');
    }
    return File(p.join(root, 'autostart', 'com.ronikcloud.backup.desktop'));
  }

  static String get _windowsCommand =>
      '"${Platform.resolvedExecutable}" --background-backup-worker';

  static Future<bool> isEnabled() async {
    if (Platform.isWindows) {
      final result = await Process.run('reg.exe', [
        'query',
        _runKey,
        '/v',
        _valueName,
      ]);
      return result.exitCode == 0 &&
          result.stdout.toString().contains(_windowsCommand);
    }
    if (Platform.isLinux) {
      final entry = await _linuxEntry();
      return await entry.exists() &&
          await entry.readAsString() ==
              linuxBackupStartupEntry(Platform.resolvedExecutable);
    }
    if (Platform.isMacOS) {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    }
    return false;
  }

  // Called only by an explicit user action. Never register silently at startup.
  static Future<void> setEnabled(bool enabled) async {
    if (Platform.isWindows) {
      if (!enabled && !await isEnabled()) return;
      final args = enabled
          ? [
              'add',
              _runKey,
              '/v',
              _valueName,
              '/t',
              'REG_SZ',
              '/d',
              _windowsCommand,
              '/f',
            ]
          : ['delete', _runKey, '/v', _valueName, '/f'];
      final result = await Process.run('reg.exe', args);
      if (result.exitCode != 0) {
        throw StateError('Windows could not update the startup setting.');
      }
      return;
    }
    if (Platform.isLinux) {
      final entry = await _linuxEntry();
      if (enabled) {
        await entry.parent.create(recursive: true);
        await entry.writeAsString(
          linuxBackupStartupEntry(Platform.resolvedExecutable),
          flush: true,
        );
      } else if (await entry.exists()) {
        await entry.delete();
      }
      return;
    }
    if (Platform.isMacOS) {
      await _channel.invokeMethod<void>('setEnabled', enabled);
      return;
    }
    throw UnsupportedError('Startup is managed by the operating system.');
  }
}
