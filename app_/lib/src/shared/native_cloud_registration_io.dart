import 'dart:io';

import 'package:flutter/foundation.dart';

import '../linux_cloud/native_linux_cloud.dart';
import 'service_environment.dart';

NativeLinuxCloud? _linuxCloud;

/// Run before Firebase's lazily cached facade in every native entry point.
/// Keep the OS check as well as Flutter's target check so widget tests can use
/// synthetic platforms without replacing their injected plugin implementations.
void registerNativeCloudForCurrentPlatform() {
  if (!Platform.isLinux || defaultTargetPlatform != TargetPlatform.linux) {
    return;
  }
  if (_linuxCloud != null) return;
  final local = ServiceEnvironmentConfig.usesLocalEmulators;
  final native = NativeLinuxCloud(
    authEmulatorPort: local ? 9099 : null,
    firestoreEmulatorPort: local ? 8080 : null,
  );
  native.register();
  _linuxCloud = native;
}
