import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../desktop_drive/drive_provider_protocol.dart';
import '../shared/background_backup_runner.dart';
import 'local_access_server.dart';

class LocalAccessTile extends StatelessWidget {
  const LocalAccessTile({super.key, this.backendFactory});
  final Future<DriveProviderBackend?> Function({
    required Future<bool> Function() stillEnabled,
  })?
  backendFactory;
  @override
  Widget build(BuildContext context) {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return const SizedBox.shrink();
    }
    return ListTile(
      leading: const Icon(Icons.link),
      title: const Text('Local agent and WebDAV access'),
      subtitle: const Text(
        'Share read-only access to one folder for 15 minutes.',
      ),
      onTap: () => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AccessPanel(backendFactory: backendFactory),
      ),
    );
  }
}

class _AccessPanel extends StatefulWidget {
  const _AccessPanel({this.backendFactory});
  final Future<DriveProviderBackend?> Function({
    required Future<bool> Function() stillEnabled,
  })?
  backendFactory;
  @override
  State<_AccessPanel> createState() => _AccessPanelState();
}

class _AccessPanelState extends State<_AccessPanel>
    with WidgetsBindingObserver {
  DriveProviderBackend? _backend;
  LocalAccessServer? _server;
  List<ProviderItem> _folders = [];
  String? _folder, _url, _token, _error;
  bool _busy = true, _consent = false, _allowed = true;
  LocalAccessProtocol _protocol = LocalAccessProtocol.mcp;
  Timer? _expiry;
  Timer? _countdown;
  DateTime? _expiresAt;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final backend =
          await (widget.backendFactory ??
              BackgroundBackupRunner.createNativeDriveBackend)(
            stillEnabled: () async => mounted && _allowed,
          );
      if (!mounted || !_allowed || generation != _generation) {
        backend?.invalidate();
        return;
      }
      _backend = backend;
      if (backend == null) throw StateError('Unavailable');
      final folders = (await backend.list(
        'root',
      )).where((e) => e.directory).toList();
      if (mounted && _allowed && generation == _generation) {
        setState(() {
          _folders = folders
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
          _busy = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _error = 'Unlock standard Personal storage and reopen this panel.';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // End access on lifecycle notifications; OS-lock delivery is platform-specific.
    // Losing focus alone
    // must allow a local agent or WebDAV client to be the foreground app.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stop());
    }
  }

  Future<void> _start() async {
    if (_busy ||
        !_consent ||
        _folder == null ||
        _backend == null ||
        !_allowed) {
      return;
    }
    setState(() => _busy = true);
    final generation = _generation;
    final server = LocalAccessServer(_backend!, _folder!, _protocol);
    _server = server;
    try {
      final endpoint = await server.start();
      if (!mounted || !_allowed || generation != _generation) {
        await server.stop();
        return;
      }
      setState(() {
        _url = endpoint.url;
        _token = endpoint.token;
        _busy = false;
        _expiresAt = DateTime.now().add(const Duration(minutes: 15));
      });
      _expiry = Timer(const Duration(minutes: 15), () => unawaited(_stop()));
      _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (_) {
      await server.stop();
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _error =
              'Access could not start. Close and reopen this panel to retry.';
          _allowed = false;
        });
      }
    }
  }

  Future<void> _stop() async {
    _generation++;
    _allowed = false;
    _expiry?.cancel();
    _countdown?.cancel();
    _backend?.invalidate();
    final server = _server;
    _server = null;
    if (mounted) {
      setState(() {
        _url = null;
        _token = null;
        _busy = false;
        _expiresAt = null;
        _error = 'Session ended. You can start a new session when ready.';
      });
    }
    await server?.stop();
  }

  Future<void> _restart() async {
    if (_busy) return;
    await _stop();
    if (!mounted) return;
    setState(() {
      _allowed = true;
      _consent = false;
      _folder = null;
      _folders = [];
      _backend = null;
      _error = null;
      _busy = true;
    });
    await _load();
  }

  @override
  void dispose() {
    _allowed = false;
    _expiry?.cancel();
    _countdown?.cancel();
    _backend?.invalidate();
    unawaited(_server?.stop() ?? Future<void>.value());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Temporary local access'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Files remain encrypted in cloud storage. An authorized local client receives readable names and contents from the selected folder and its subfolders. It can retain copies or send them to an AI service; ending access cannot recall them. Secure and Business files are excluded.',
            ),
            const SizedBox(height: 12),
            if (_url == null) ...[
              DropdownButtonFormField<LocalAccessProtocol>(
                isExpanded: true,
                initialValue: _protocol,
                decoration: const InputDecoration(labelText: 'Connection'),
                items: const [
                  DropdownMenuItem(
                    value: LocalAccessProtocol.mcp,
                    child: Text('MCP — list files and read text'),
                  ),
                  DropdownMenuItem(
                    value: LocalAccessProtocol.webdav,
                    child: Text('WebDAV — browse and download'),
                  ),
                ],
                onChanged: _busy || !_allowed
                    ? null
                    : (v) => setState(() => _protocol = v!),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(_generation),
                isExpanded: true,
                initialValue: _folder,
                decoration: const InputDecoration(labelText: 'Personal folder'),
                items: _folders
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(
                          e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _busy || !_allowed
                    ? null
                    : (v) => setState(() => _folder = v),
              ),
              if (!_busy && _folders.isEmpty && _error == null)
                const Text(
                  'Create a standard Personal folder and add the files you want to share, then reopen this panel.',
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: _busy || !_allowed
                    ? null
                    : (v) => setState(() => _consent = v == true),
                title: const Text(
                  'Allow a trusted local client to read this folder.',
                ),
              ),
            ] else ...[
              Text(
                'Access ends in ${_remainingTime()}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              SelectableText('Endpoint: $_url'),
              const SizedBox(height: 12),
              Text(
                _protocol == LocalAccessProtocol.mcp
                    ? 'Set the Authorization header to Bearer followed by this token:'
                    : 'Username: ronikcloud\nPassword:',
              ),
              SelectableText(_token!),
              const SizedBox(height: 12),
              const Text(
                'Keep this token private. Closing this panel or minimizing the app ends access. Maximum file size: 8 MiB. Local clients only; cloud-hosted agents cannot connect directly.',
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    ),
    actions: [
      if (!_allowed)
        FilledButton(
          onPressed: _busy ? null : _restart,
          child: const Text('New session'),
        ),
      if (_url == null && _allowed)
        FilledButton(
          onPressed: !_busy && _consent && _folder != null ? _start : null,
          child: const Text('Start read-only session'),
        ),
      TextButton(
        onPressed: () async {
          await _stop();
          if (context.mounted) Navigator.of(context).pop();
        },
        child: Text(_url == null ? 'Close' : 'Stop and close'),
      ),
    ],
  );

  String _remainingTime() {
    final seconds = (_expiresAt?.difference(DateTime.now()).inSeconds ?? 0)
        .clamp(0, 900);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
