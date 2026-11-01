import 'package:flutter/material.dart';

import 'cloud_drive_provider.dart';
import 'migration_failure.dart';

typedef DriveMigrationCallback =
    Future<void> Function(
      CloudDriveProvider provider,
      List<RemoteFileEntry> files,
    );

class DriveMigrationOverlay extends StatefulWidget {
  const DriveMigrationOverlay({
    super.key,
    required this.providers,
    required this.onImport,
  });

  final List<CloudDriveProvider> providers;
  final DriveMigrationCallback onImport;

  @override
  State<DriveMigrationOverlay> createState() => _DriveMigrationOverlayState();
}

class _DriveMigrationOverlayState extends State<DriveMigrationOverlay>
    with TickerProviderStateMixin {
  CloudDriveProvider? _activeProvider;
  CloudDriveProvider? _connectingProvider;
  List<RemoteEntry> _entries = const <RemoteEntry>[];
  final List<RemoteFolderEntry?> _breadcrumbs = <RemoteFolderEntry?>[null];
  final Map<String, RemoteFileEntry> _selectedFiles =
      <String, RemoteFileEntry>{};
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedFiles.length;
    final selectedBytes = _selectedFiles.values.fold<int>(
      0,
      (total, file) => total + (file.sizeBytes > 0 ? file.sizeBytes : 0),
    );
    final selectedLabel = selectedCount == 0
        ? 'Select files or folders to migrate.'
        : '$selectedCount item${selectedCount == 1 ? '' : 's'} selected'
              '${selectedBytes > 0 ? ' - ${_formatSize(selectedBytes)}' : ''}.';
    return SafeArea(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Migrate files without downloading',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _activeProvider == null
                          ? 'Connect a storage provider, browse its folders, and copy selected items into encrypted RonikCloud folders.'
                          : 'Select files or folders from ${_activeProvider!.displayName}. Imported items keep their folder path under a provider folder.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_activeProvider == null) ...[
                _buildProviderList(context),
              ] else ...[
                _buildBreadcrumbs(context),
                const SizedBox(height: 8),
                _buildEntries(context),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text(selectedLabel)),
                    FilledButton.icon(
                      onPressed: selectedCount == 0 || _busy
                          ? null
                          : () async {
                              final provider = _activeProvider;
                              if (provider == null) {
                                return;
                              }
                              await _import(provider);
                            },
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Import'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderList(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final provider in widget.providers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: theme.colorScheme.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.55,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    provider.icon,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(provider.displayName),
                subtitle: Text(provider.description),
                trailing: _busy && _connectingProvider == provider
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : provider.isConnected
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.chevron_right_rounded),
                onTap: _busy
                    ? null
                    : () async {
                        setState(() {
                          _busy = true;
                          _connectingProvider = provider;
                          _error = null;
                        });
                        try {
                          await provider.ensureAuthenticated(context);
                          final entries = await provider.listChildren(null);
                          if (!mounted) return;
                          setState(() {
                            _activeProvider = provider;
                            _connectingProvider = null;
                            _entries = entries;
                            _breadcrumbs
                              ..clear()
                              ..add(null);
                            _selectedFiles.clear();
                            _busy = false;
                          });
                        } catch (error) {
                          if (!mounted) return;
                          setState(() {
                            _connectingProvider = null;
                            _error = migrationFailureMessage(
                              MigrationFailureAction.connect,
                              error,
                            );
                            _busy = false;
                          });
                        }
                      },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBreadcrumbs(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < _breadcrumbs.length; index++)
            Row(
              children: [
                if (index > 0) const Icon(Icons.chevron_right, size: 18),
                InkWell(
                  onTap: _busy
                      ? null
                      : () async {
                          await _navigateTo(index);
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Text(
                      index == 0
                          ? _activeProvider?.displayName ?? 'Root'
                          : _breadcrumbs[index]?.name ?? 'Folder',
                      style: TextStyle(
                        fontWeight: index == _breadcrumbs.length - 1
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEntries(BuildContext context) {
    if (_busy && _entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Text('This folder is empty.')),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.45,
      ),
      child: Material(
        color: Colors.transparent,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _entries.length,
          itemBuilder: (context, index) {
            final entry = _entries[index];
            if (entry is RemoteFolderEntry) {
              return ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: Text(entry.name),
                subtitle: const Text('Folder'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline),
                      tooltip: 'Select entire folder',
                      onPressed: _busy
                          ? null
                          : () async {
                              await _selectFolder(entry);
                            },
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: _busy
                    ? null
                    : () async {
                        await _openFolder(entry);
                      },
              );
            }
            final file = entry as RemoteFileEntry;
            final selected = _selectedFiles.containsKey(file.id);
            return CheckboxListTile(
              value: selected,
              onChanged: _busy
                  ? null
                  : (_) {
                      _toggleFile(file);
                    },
              title: Text(file.name),
              subtitle: Text(
                file.parentPathSegments.isEmpty
                    ? _formatSize(file.sizeBytes)
                    : '${file.parentPathSegments.join('/')} - ${_formatSize(file.sizeBytes)}',
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openFolder(RemoteFolderEntry folder) async {
    final provider = _activeProvider;
    if (provider == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entries = await provider.listChildren(folder);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _breadcrumbs.add(folder);
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = migrationFailureMessage(MigrationFailureAction.browse, error);
        _busy = false;
      });
    }
  }

  Future<void> _navigateTo(int breadcrumbIndex) async {
    if (breadcrumbIndex < 0 || breadcrumbIndex >= _breadcrumbs.length) {
      return;
    }
    final provider = _activeProvider;
    if (provider == null) {
      return;
    }

    final target = _breadcrumbs[breadcrumbIndex];
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final entries = await provider.listChildren(target);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _breadcrumbs.removeRange(breadcrumbIndex + 1, _breadcrumbs.length);
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = migrationFailureMessage(MigrationFailureAction.browse, error);
        _busy = false;
      });
    }
  }

  void _toggleFile(RemoteFileEntry file) {
    setState(() {
      if (_selectedFiles.containsKey(file.id)) {
        _selectedFiles.remove(file.id);
      } else {
        _selectedFiles[file.id] = file;
      }
    });
  }

  Future<void> _import(CloudDriveProvider provider) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onImport(provider, _selectedFiles.values.toList());
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = migrationFailureMessage(
          MigrationFailureAction.importFiles,
          error,
        );
        _busy = false;
      });
    }
  }

  Future<void> _selectFolder(RemoteFolderEntry folder) async {
    final provider = _activeProvider;
    if (provider == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final collected = <String, RemoteFileEntry>{};
      await _collectFolder(provider, folder, collected);
      if (!mounted) return;
      setState(() {
        _selectedFiles.addAll(collected);
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = migrationFailureMessage(
          MigrationFailureAction.selectFolder,
          error,
        );
        _busy = false;
      });
    }
  }

  Future<void> _collectFolder(
    CloudDriveProvider provider,
    RemoteFolderEntry folder,
    Map<String, RemoteFileEntry> output,
  ) async {
    final entries = await provider.listChildren(folder);
    for (final entry in entries) {
      if (entry is RemoteFileEntry) {
        output[entry.id] = entry;
      } else if (entry is RemoteFolderEntry) {
        await _collectFolder(provider, entry, output);
      }
    }
  }

  String _formatSize(int sizeBytes) {
    if (sizeBytes <= 0) {
      return 'Unknown size';
    }
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = sizeBytes.toDouble();
    var suffixIndex = 0;
    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[suffixIndex]}';
  }
}
