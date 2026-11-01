import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../privacy/local_private_cache.dart';
import '../shared/background_backup_runner.dart';
import 'drive_provider_broker.dart';

class DesktopDriveRuntime {
  // Native preview must pass signed end-to-end validation before release
  // builders enable this flag. Consent is additionally required per account.
  static bool get supported =>
      (Platform.isWindows || Platform.isMacOS) &&
      const bool.fromEnvironment('ENABLE_DESKTOP_DRIVE', defaultValue: false);
  static const _channel = MethodChannel('ronikcloud/desktop-drive');
  static DriveProviderBroker? _broker;
  static Map<String, Object>? _configuration;
  static bool _refreshing = false;
  static Timer? _timer;
  static String? _activeUid;
  static String get _scope {
    final app = Firebase.app();
    return app.options.projectId.trim().isNotEmpty
        ? app.options.projectId.trim()
        : app.name;
  }

  static String? get _uid =>
      FirebaseAuth.instanceFor(app: Firebase.app()).currentUser?.uid;
  static Future<LocalPrivateCachePreferences?> _cache() async {
    final uid = _uid;
    if (uid == null) return null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return LocalPrivateCachePreferences(
      preferences: preferences,
      uid: uid,
      scope: _scope,
    );
  }

  static Future<bool> isEnabled() async {
    if (!supported) return false;
    final cache = await _cache();
    if (cache == null) return false;
    final read = await cache.read(
      baseKey: LocalPrivateCacheCodec.desktopDrivePreferenceKey,
      namespace: LocalPrivateCacheCodec.desktopDriveNamespace,
    );
    return read.value == 'standard-os-access-v1';
  }

  static Future<String> status() async {
    final cache = await _cache();
    if (cache == null) return 'paused';
    return (await cache.read(
          baseKey: LocalPrivateCacheCodec.desktopDriveStatusPreferenceKey,
          namespace: LocalPrivateCacheCodec.desktopDriveStatusNamespace,
        )).value ??
        'starting';
  }

  static Future<void> _status(String value) async {
    final cache = await _cache();
    await cache?.write(
      baseKey: LocalPrivateCacheCodec.desktopDriveStatusPreferenceKey,
      namespace: LocalPrivateCacheCodec.desktopDriveStatusNamespace,
      value: value,
    );
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!supported) {
      throw UnsupportedError('Native drive preview is unavailable.');
    }
    final cache = await _cache();
    if (cache == null) throw StateError('Sign in required.');
    await cache.write(
      baseKey: LocalPrivateCacheCodec.desktopDrivePreferenceKey,
      namespace: LocalPrivateCacheCodec.desktopDriveNamespace,
      value: enabled ? 'standard-os-access-v1' : null,
    );
    await _status(enabled ? 'starting' : 'paused');
  }

  static Future<void> openFolder() async {
    if (!Platform.isWindows ||
        !await isEnabled() ||
        !{'connected', 'syncing', 'needs-attention'}.contains(await status())) {
      throw StateError('Explorer is not connected.');
    }
    final uid = _uid;
    if (uid == null) throw StateError('Sign in required.');
    final domain = sha256
        .convert(utf8.encode('native-drive-v1\n$_scope\n$uid'))
        .toString();
    await _channel.invokeMethod<void>('openFolder', {'domain': domain});
  }

  /// Called only by an OS-locked background worker. The visible
  /// Flutter window never starts a second provider for the same account.
  static Future<bool> refresh() async {
    if (!supported) return false;
    if (_refreshing) return _broker != null;
    _refreshing = true;
    var enabled = false;
    try {
      if (!await BackgroundBackupRunner.ensureNativeDriveAuthentication()) {
        await stop();
        return false;
      }
      enabled = await isEnabled();
      if (!enabled || (_activeUid != null && _activeUid != _uid)) await stop();
      if (!enabled) return false;
      if (_broker == null) {
        final uid = _uid;
        final backend = await BackgroundBackupRunner.createNativeDriveBackend(
          stillEnabled: () async => _uid == uid && await isEnabled(),
        );
        if (backend == null) {
          await _status('paused');
          return true;
        }
        // Ensure the account/key/catalogue can actually be read before
        // registering anything with the operating system.
        final rootItems = await backend.list('root');
        final broker = DriveProviderBroker(backend);
        final endpoint = await broker.start();
        _broker = broker;
        _activeUid = uid;
        _configuration = {
          'domain': sha256
              .convert(utf8.encode('native-drive-v1\n$_scope\n$uid'))
              .toString(),
          'port': endpoint.port,
          'token': endpoint.token,
          'rootItems': jsonEncode({
            'items': rootItems.map((item) => item.toJson()).toList(),
          }),
        };
        await _channel.invokeMethod<Object?>('start', _configuration);
        _timer ??= Timer.periodic(
          const Duration(seconds: 10),
          (_) => unawaited(refresh()),
        );
      } else {
        // Fresh keychain checks detect lock/sign-out in another process.
        await _broker!.backend.item('root');
        final nativeStatus = await _channel.invokeMethod<String>(
          'heartbeat',
          _configuration,
        );
        if (Platform.isWindows && nativeStatus != null) {
          await _status(nativeStatus);
          return true;
        }
      }
      await _status('connected');
    } catch (_) {
      await stop();
      try {
        await _status('paused');
      } catch (_) {
        /* Keychain locked. */
      }
    } finally {
      _refreshing = false;
    }
    return enabled;
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final configuration = _configuration;
    _configuration = null;
    _activeUid = null;
    final broker = _broker;
    _broker = null;
    // Close broker connections FIRST so CfDisconnectSyncRoot cannot wait on
    // an HTTP callback whose Dart isolate is blocked in the native call.
    await broker?.stop();
    if (configuration != null) {
      try {
        await _channel.invokeMethod<void>('stop', configuration);
      } catch (_) {
        /* Revoked broker token already prevents new reads. */
      }
    }
  }
}
