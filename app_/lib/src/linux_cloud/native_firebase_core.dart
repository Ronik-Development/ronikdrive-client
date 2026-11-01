import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

/// Dart-side app lifecycle for Linux, without native method channels or
/// automatic administrator credential discovery.
class NativeFirebaseCore extends FirebasePlatform {
  NativeFirebaseCore({
    required this.initializeServices,
    required this.disposeServices,
  });
  final Future<void> Function(FirebaseAppPlatform) initializeServices;
  final Future<void> Function(String) disposeServices;
  final Map<String, _NativeApp> _apps = {};
  final Map<String, Future<FirebaseAppPlatform>> _initializing = {};

  @override
  List<FirebaseAppPlatform> get apps => List.unmodifiable(
    _apps.values.where((app) => !_initializing.containsKey(app.name)),
  );

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) =>
      (_initializing.containsKey(name) ? null : _apps[name]) ??
      (throw FirebaseException(
        plugin: 'core',
        code: 'no-app',
        message: 'Initialize Firebase before using cloud services.',
      ));

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final appName = name ?? defaultFirebaseAppName;
    if (options == null) {
      throw FirebaseException(
        plugin: 'core',
        code: 'no-options',
        message: 'Native Firebase options are required.',
      );
    }
    final existing = _apps[appName];
    if (existing != null) {
      if (existing.options != options) {
        throw FirebaseException(
          plugin: 'core',
          code: 'duplicate-app',
          message: 'The app name already has different Firebase options.',
        );
      }
      return _initializing[appName] ?? existing;
    }
    final created = _NativeApp(appName, options, this);
    _apps[appName] = created;
    final operation = () async {
      try {
        await initializeServices(created);
        return created;
      } catch (_) {
        _apps.remove(appName);
        await disposeServices(appName);
        rethrow;
      } finally {
        _initializing.remove(appName);
      }
    }();
    _initializing[appName] = operation;
    return operation;
  }

  Future<void> _delete(_NativeApp app) async {
    if (!identical(_apps[app.name], app)) return;
    await disposeServices(app.name);
    _apps.remove(app.name);
  }
}

class _NativeApp extends FirebaseAppPlatform {
  _NativeApp(super.name, super.options, this._core);
  final NativeFirebaseCore _core;
  @override
  bool get isAutomaticDataCollectionEnabled => false;
  @override
  Future<void> setAutomaticDataCollectionEnabled(bool enabled) async {
    if (enabled) {
      throw UnsupportedError(
        'Native Linux adapters do not provide automatic data collection.',
      );
    }
  }

  @override
  Future<void> setAutomaticResourceManagementEnabled(bool enabled) async {}
  @override
  Future<void> delete() => _core._delete(this);
}
