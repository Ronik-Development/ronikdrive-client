import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Exposes the app theme mode to the root MaterialApp.
///
/// User-facing theme switching is disabled; the app follows the system setting.
class ThemeController {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  final ValueNotifier<ThemeMode> _mode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  /// The current theme mode that widgets should listen to.
  ValueListenable<ThemeMode> get listenable => _mode;

  /// Returns the active theme mode without creating a dependency.
  ThemeMode get mode => _mode.value;
}
