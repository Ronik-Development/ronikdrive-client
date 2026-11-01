import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../shared/background_service.dart';
import 'desktop_drive_runtime.dart';

class DesktopDriveSetupTile extends StatefulWidget {
  const DesktopDriveSetupTile({
    super.key,
    this.available,
    this.loadEnabled,
    this.saveEnabled,
    this.loadStatus,
    this.startWorker,
    this.openFolder,
  });
  final bool? available;
  final Future<bool> Function()? loadEnabled;
  final Future<void> Function(bool)? saveEnabled;
  final Future<String> Function()? loadStatus;
  final Future<void> Function()? startWorker;
  final Future<void> Function()? openFolder;
  @override
  State<DesktopDriveSetupTile> createState() => _DesktopDriveSetupTileState();
}

class _DesktopDriveSetupTileState extends State<DesktopDriveSetupTile> {
  bool _enabled = false, _consent = false, _busy = true;
  String? _error;
  String _status = 'starting';
  Timer? _timer;
  bool _toggling = false;
  int _loadGeneration = 0;
  bool get _available =>
      widget.available ?? (DesktopDriveRuntime.supported && kReleaseMode);
  String get _explorer => defaultTargetPlatform == TargetPlatform.macOS
      ? 'Finder'
      : 'File Explorer';
  @override
  void initState() {
    super.initState();
    if (_available) {
      unawaited(_load());
      _timer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!_toggling) unawaited(_load());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final enabled =
          await (widget.loadEnabled ?? DesktopDriveRuntime.isEnabled)();
      final status = await (widget.loadStatus ?? DesktopDriveRuntime.status)();
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _enabled = enabled;
          _status = status;
          _busy = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = 'Unlock this device and retry setup.';
          _busy = false;
        });
      }
    }
  }

  Future<void> _toggle() async {
    if (_busy || (!_enabled && !_consent)) return;
    _toggling = true;
    _loadGeneration++;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = !_enabled;
      await (widget.saveEnabled ?? DesktopDriveRuntime.setEnabled)(next);
      if (next) {
        await (widget.startWorker ??
            BackgroundService.ensureDesktopWorkerRunning)();
      }
      await _load();
      if (mounted && !next) setState(() => _consent = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Drive setup did not finish. Unlock the app and try again.';
          _busy = false;
        });
      }
    } finally {
      _toggling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) {
      return ListTile(
        leading: const Icon(Icons.desktop_windows_outlined),
        title: Text('$_explorer integration'),
        subtitle: const Text(
          'Not enabled in this build. Native drive access is still a development preview; no setup step was missed. Use Files and Backups in RonikCloud for now.',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Use $_explorer',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Access your standard workspace from $_explorer and your usual apps. Secure storage stays inside RonikCloud.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Cloud files remain encrypted. Downloaded files and their names become accessible to this device’s apps. Pausing or signing out does not erase copies already downloaded.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Preview: files up to 64 MiB. Move or delete folders inside RonikCloud. Keep the computer awake and use Start at login to reconnect after a restart.',
          ),
          if (defaultTargetPlatform == TargetPlatform.windows)
            const Text(
              'Windows preview: renames and remote change refresh are still being completed. Use RonikCloud for those operations. Local file uploads require the matching server release.',
            ),
          if (!_enabled)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _consent,
              title: const Text(
                'Allow standard files to be accessed by this device’s apps',
              ),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _consent = value ?? false),
            ),
          if (_enabled)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(switch (_status) {
                'connected' => 'Connected to $_explorer',
                'syncing' => 'Syncing changes with $_explorer…',
                'needs-attention' =>
                  'Some changes could not sync. Local files are preserved. Check your connection and storage capacity; retries are automatic.',
                'paused' =>
                  'Connection paused. Unlock RonikCloud and check your internet connection.',
                _ => 'Starting the background connection…',
              }),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: _busy || (!_enabled && !_consent) ? null : _toggle,
            child: Text(
              _busy
                  ? 'Please wait…'
                  : _enabled
                  ? 'Pause native access'
                  : 'Enable in $_explorer',
            ),
          ),
          if (_enabled &&
              {'connected', 'syncing', 'needs-attention'}.contains(_status) &&
              (defaultTargetPlatform == TargetPlatform.windows ||
                  widget.openFolder != null))
            TextButton.icon(
              onPressed: () async {
                try {
                  await (widget.openFolder ?? DesktopDriveRuntime.openFolder)();
                } catch (_) {
                  if (mounted) {
                    setState(
                      () => _error =
                          'The Explorer location is unavailable. Reconnect and try again.',
                    );
                  }
                }
              },
              icon: const Icon(Icons.folder_open_outlined),
              label: Text('Open in $_explorer'),
            ),
        ],
      ),
    );
  }
}
