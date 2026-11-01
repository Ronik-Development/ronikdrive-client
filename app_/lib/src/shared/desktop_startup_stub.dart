class DesktopStartup {
  static bool get supported => false;
  static Future<bool> isEnabled() async => false;
  static Future<void> setEnabled(bool enabled) async =>
      throw UnsupportedError('Startup is managed by the operating system.');
}
