// Escape both Desktop Entry string parsing and Exec argument parsing. The
// executable is a single argument, never a shell command or a field code.
String linuxBackupStartupEntry(String executable) {
  if (!executable.startsWith('/') ||
      executable.contains(RegExp(r'[\r\n\x00]'))) {
    throw ArgumentError(
      'An absolute, single-line executable path is required.',
    );
  }
  final quoted = executable
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll(r'$', r'\$')
      .replaceAll('`', r'\`')
      .replaceAll('%', '%%');
  final entryValue = quoted.replaceAll(r'\', r'\\');
  final tryExecValue = executable.replaceAll(r'\', r'\\');
  return '[Desktop Entry]\nType=Application\nName=RonikCloud Backup\n'
      'Comment=Back up the folders you selected in RonikCloud\n'
      'TryExec=$tryExecValue\n'
      'Exec="$entryValue" --background-backup-worker\n'
      'Terminal=false\nX-GNOME-Autostart-enabled=true\n';
}
