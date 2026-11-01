import 'package:flutter/material.dart';

// We need a lightweight interface for folders to avoid circular deps with workspace_home_page
abstract class FolderInterface {
  String get id;
  String get name;
  String? get parentId;
  String? get colorHex;
}

class SimpleFolder implements FolderInterface {
  const SimpleFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.colorHex,
  });

  @override
  final String id;
  @override
  final String name;
  @override
  final String? parentId;
  @override
  final String? colorHex;
}

class FolderPicker extends StatefulWidget {
  const FolderPicker({
    super.key,
    required this.folders,
    required this.movingFolderIds,
    this.initialParentId,
  });

  final List<FolderInterface> folders;
  final Set<String> movingFolderIds;
  final String? initialParentId;

  @override
  State<FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<FolderPicker> {
  String? _currentParentId;

  @override
  void initState() {
    super.initState();
    _currentParentId = _normalizeFolderId(widget.initialParentId);
  }

  void _navigateTo(String? folderId) {
    setState(() {
      _currentParentId = _normalizeFolderId(folderId);
    });
  }

  void _navigateUp() {
    final current = _currentParentId;
    if (current == null) {
      return;
    }
    final parentId = _folderById[current]?.parentId;
    setState(() {
      _currentParentId = _normalizeFolderId(parentId);
    });
  }

  String? _normalizeFolderId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == 'root') {
      return null;
    }
    return trimmed;
  }

  Map<String, FolderInterface> get _folderById => <String, FolderInterface>{
    for (final folder in widget.folders) folder.id: folder,
  };

  List<FolderInterface> _breadcrumbFoldersFor(String? folderId) {
    final byId = _folderById;
    final chain = <FolderInterface>[];
    final seen = <String>{};
    var currentId = _normalizeFolderId(folderId);
    while (currentId != null && seen.add(currentId)) {
      final folder = byId[currentId];
      if (folder == null) {
        break;
      }
      chain.add(folder);
      currentId = _normalizeFolderId(folder.parentId);
    }
    return chain.reversed.toList(growable: false);
  }

  // Check if targetFolderId is a descendant of any movingFolderId
  bool _isDescendantOfMoving(String targetFolderId) {
    // If the folder itself is being moved, we can't move into it.
    if (widget.movingFolderIds.contains(targetFolderId)) return true;

    // Check hierarchy
    final folderById = _folderById;
    final current = folderById[targetFolderId];
    if (current == null) return false;

    // Since we don't have efficient parent lookup map here, this might be O(N*Depth).
    // But N is usually small (<1000).
    // Actually, simple check: is any ancestor in movingFolderIds?

    // We can pre-calculate this or just traverse up.
    String? pid = current.parentId;
    while (pid != null) {
      if (widget.movingFolderIds.contains(pid)) return true;
      final parent = folderById[pid];
      pid = parent?.parentId;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Filter folders for current level
    final currentLevelFolders = widget.folders.where((f) {
      if (_currentParentId == null) {
        return f.parentId == null;
      }
      return f.parentId == _currentParentId;
    }).toList();

    // Sort by name
    currentLevelFolders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final breadcrumbFolders = _breadcrumbFoldersFor(_currentParentId);
    final currentFolderName = _currentParentId == null
        ? 'My Drive'
        : (breadcrumbFolders.isEmpty ? 'Folder' : breadcrumbFolders.last.name);
    final currentDestinationDisabled =
        _currentParentId != null && _isDescendantOfMoving(_currentParentId!);

    return Scaffold(
      appBar: AppBar(
        title: Text('Move to...'),
        leading: _currentParentId != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _navigateUp,
                tooltip: 'Back',
              )
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
              ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: theme.colorScheme.surfaceContainerHigh,
            width: double.infinity,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.home_outlined, size: 18),
                  label: const Text('My Drive'),
                  onPressed: _currentParentId == null
                      ? null
                      : () => _navigateTo(null),
                ),
                for (final folder in breadcrumbFolders)
                  ActionChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(folder.name),
                    onPressed: folder.id == _currentParentId
                        ? null
                        : () => _navigateTo(folder.id),
                  ),
                if (breadcrumbFolders.isEmpty && _currentParentId != null)
                  Text(
                    currentFolderName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          if (currentDestinationDisabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                'Choose a folder outside the selected folder tree.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: currentLevelFolders.isEmpty
                ? Center(
                    child: Text(
                      'No folders here.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: currentLevelFolders.length,
                    itemBuilder: (context, index) {
                      final folder = currentLevelFolders[index];
                      final isMoving = widget.movingFolderIds.contains(
                        folder.id,
                      );
                      final isDisabled =
                          isMoving || _isDescendantOfMoving(folder.id);

                      return ListTile(
                        leading: Icon(
                          Icons.folder,
                          color: isDisabled
                              ? theme.disabledColor
                              : theme.colorScheme.primary,
                        ),
                        title: Text(
                          folder.name,
                          style: isDisabled
                              ? TextStyle(color: theme.disabledColor)
                              : null,
                        ),
                        subtitle: isMoving
                            ? const Text('Selected folder')
                            : (isDisabled
                                  ? const Text('Inside selected folder')
                                  : null),
                        enabled: !isDisabled,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: isDisabled ? null : () => _navigateTo(folder.id),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: currentDestinationDisabled
                      ? null
                      : () =>
                            Navigator.pop(context, _currentParentId ?? 'root'),
                  child: const Text('Move here'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
