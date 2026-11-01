class DesktopDriveRuntime {
  static bool get supported => false;
  static Future<bool> isEnabled() async => false;
  static Future<String> status() async => 'unsupported';
  static Future<void> setEnabled(bool enabled) async =>
      throw UnsupportedError('Desktop required.');
  static Future<bool> refresh() async => false;
  static Future<void> stop() async {}
  static Future<void> openFolder() async =>
      throw UnsupportedError('Desktop required.');
}
