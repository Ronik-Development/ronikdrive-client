import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../shared/desktop_startup.dart';
import '../shared/folder_backup_platform_policy.dart';

class BackupStartupTile extends StatefulWidget {
  const BackupStartupTile({super.key});

  @override
  State<BackupStartupTile> createState() => _BackupStartupTileState();
}

class _BackupStartupTileState extends State<BackupStartupTile> {
  bool _busy = false;
  bool? _enabled;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (DesktopStartup.supported &&
        kReleaseMode &&
        supportsPersistentFolderBackups(
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
        )) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final enabled = await DesktopStartup.isEnabled();
      if (mounted) setState(() => _enabled = enabled);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not read the startup setting. Try again.',
        );
      }
    }
  }

  Future<void> _toggle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final requestedEnabled = !(_enabled ?? false);
    try {
      await DesktopStartup.setEnabled(requestedEnabled);
      final enabled = await DesktopStartup.isEnabled();
      if (mounted) {
        setState(() {
          _enabled = enabled;
          if (requestedEnabled &&
              !enabled &&
              defaultTargetPlatform == TargetPlatform.macOS) {
            _error =
                'macOS may require approval in System Settings > General > Login Items.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Startup could not be changed. On Mac, use Login Items in System Settings (macOS 13 or later).',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported =
        DesktopStartup.supported &&
        supportsPersistentFolderBackups(
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
        );
    final description = kIsWeb
        ? 'Folder backup needs the installed desktop app; closing a browser stops its work.'
        : !supported && defaultTargetPlatform != TargetPlatform.iOS
        ? persistentFolderBackupUnavailableMessage(
            isWeb: kIsWeb,
            platform: defaultTargetPlatform,
          )
        : !supported
        ? 'Your phone schedules background work. Battery limits and force-quitting can pause it. Open RonikCloud regularly to check backup status.'
        : !kReleaseMode
        ? 'This debug preview does not run backup after closing. The installed release can; it must stay signed in and your computer must be awake.'
        : 'Keep selected folders backed up after closing the window. Start at login to resume after a restart. Sleep, sign-out, or a locked keychain can pause backup.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keep backups running',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(description),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (supported && kReleaseMode) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : _enabled == null
                  ? _load
                  : _toggle,
              child: Text(
                _busy
                    ? 'Updating startup…'
                    : _enabled == null
                    ? 'Check startup setting'
                    : _enabled!
                    ? 'Turn off start at login'
                    : 'Start at login',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
