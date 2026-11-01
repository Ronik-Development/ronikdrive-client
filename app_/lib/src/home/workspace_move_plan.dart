class WorkspaceMoveFolderSnapshot {
  const WorkspaceMoveFolderSnapshot({
    required this.id,
    required this.name,
    this.parentId,
    this.colorHex,
  });

  final String id;
  final String name;
  final String? parentId;
  final String? colorHex;

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Untitled folder' : trimmed;
  }
}

class WorkspaceMoveFileSnapshot {
  const WorkspaceMoveFileSnapshot({
    required this.id,
    this.resolvedFolderId,
    this.isSecured = false,
  });

  final String id;
  final String? resolvedFolderId;
  final bool isSecured;
}

class WorkspaceMoveSelectedFileUpdate {
  WorkspaceMoveSelectedFileUpdate({
    required this.id,
    required this.folderId,
    required this.folderName,
    required this.folderColor,
    required this.clearFolderDecorations,
    required List<String> pathSegments,
  }) : pathSegments = List.unmodifiable(pathSegments);

  final String id;
  final String? folderId;
  final String? folderName;
  final String? folderColor;
  final bool clearFolderDecorations;
  final List<String> pathSegments;
}

class WorkspaceMoveFolderUpdate {
  WorkspaceMoveFolderUpdate({
    required this.id,
    required this.hasParentIdChange,
    required this.parentId,
    required List<String> pathSegments,
  }) : pathSegments = List.unmodifiable(pathSegments);

  final String id;
  final bool hasParentIdChange;
  final String? parentId;
  final List<String> pathSegments;
}

class WorkspaceMoveDescendantFileUpdate {
  WorkspaceMoveDescendantFileUpdate({
    required this.id,
    required List<String> pathSegments,
  }) : pathSegments = List.unmodifiable(pathSegments);

  final String id;
  final List<String> pathSegments;
}

class WorkspaceMovePlan {
  WorkspaceMovePlan({
    required List<WorkspaceMoveSelectedFileUpdate> selectedFileUpdates,
    required List<WorkspaceMoveFolderUpdate> folderUpdates,
    required List<WorkspaceMoveDescendantFileUpdate> descendantFileUpdates,
  }) : selectedFileUpdates = List.unmodifiable(selectedFileUpdates),
       folderUpdates = List.unmodifiable(folderUpdates),
       descendantFileUpdates = List.unmodifiable(descendantFileUpdates);

  final List<WorkspaceMoveSelectedFileUpdate> selectedFileUpdates;
  final List<WorkspaceMoveFolderUpdate> folderUpdates;
  final List<WorkspaceMoveDescendantFileUpdate> descendantFileUpdates;
}

String? normalizeWorkspaceFolderId(String? folderId) {
  final trimmed = folderId?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed == 'root') {
    return null;
  }
  return trimmed;
}

String sanitizeWorkspacePathSegment(String segment) {
  return segment.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
}

Set<String> descendantWorkspaceFolderIds(
  String folderId,
  Iterable<WorkspaceMoveFolderSnapshot> folders,
) {
  final descendants = <String>{};
  final folderList = folders.toList(growable: false);
  final queue = <String>[folderId];
  while (queue.isNotEmpty) {
    final currentId = queue.removeLast();
    for (final folder in folderList) {
      if (normalizeWorkspaceFolderId(folder.parentId) != currentId) {
        continue;
      }
      if (descendants.add(folder.id)) {
        queue.add(folder.id);
      }
    }
  }
  return descendants;
}

List<String> workspacePathSegmentsForFolder(
  String? folderId,
  Iterable<WorkspaceMoveFolderSnapshot> folders, {
  Map<String, String?> parentOverrides = const <String, String?>{},
}) {
  final normalizedId = normalizeWorkspaceFolderId(folderId);
  if (normalizedId == null) {
    return const <String>[];
  }

  final folderById = <String, WorkspaceMoveFolderSnapshot>{
    for (final folder in folders) folder.id: folder,
  };
  final memo = <String, List<String>>{};

  List<String> resolve(String id, Set<String> seen) {
    final cached = memo[id];
    if (cached != null) {
      return cached;
    }
    if (!seen.add(id)) {
      return const <String>[];
    }
    final folder = folderById[id];
    if (folder == null) {
      seen.remove(id);
      return const <String>[];
    }
    final parentId = parentOverrides.containsKey(id)
        ? normalizeWorkspaceFolderId(parentOverrides[id])
        : normalizeWorkspaceFolderId(folder.parentId);
    final parentSegments = parentId == null
        ? const <String>[]
        : resolve(parentId, seen);
    final segments = <String>[
      ...parentSegments,
      sanitizeWorkspacePathSegment(folder.displayName),
    ].where((segment) => segment.isNotEmpty).toList(growable: false);
    memo[id] = segments;
    seen.remove(id);
    return segments;
  }

  return resolve(normalizedId, <String>{});
}

WorkspaceMovePlan buildWorkspaceMovePlan({
  required Iterable<WorkspaceMoveFolderSnapshot> folders,
  required Iterable<WorkspaceMoveFileSnapshot> files,
  required Iterable<WorkspaceMoveFileSnapshot> selectedFiles,
  required Iterable<String> selectedFolderIds,
  required String? destinationFolderId,
}) {
  final folderList = folders.toList(growable: false);
  final fileList = files.toList(growable: false);
  final selectedFileList = selectedFiles.toList(growable: false);
  final selectedFileIds = selectedFileList.map((file) => file.id).toSet();
  final selectedFolderIdSet = selectedFolderIds
      .map(normalizeWorkspaceFolderId)
      .whereType<String>()
      .toSet();
  final folderById = <String, WorkspaceMoveFolderSnapshot>{
    for (final folder in folderList) folder.id: folder,
  };
  final targetId = normalizeWorkspaceFolderId(destinationFolderId);
  final targetFolder = targetId == null ? null : folderById[targetId];
  final parentOverrides = <String, String?>{};

  bool hasSelectedAncestor(WorkspaceMoveFolderSnapshot folder) {
    var parentId = normalizeWorkspaceFolderId(folder.parentId);
    final seen = <String>{};
    while (parentId != null && seen.add(parentId)) {
      if (selectedFolderIdSet.contains(parentId)) {
        return true;
      }
      parentId = normalizeWorkspaceFolderId(folderById[parentId]?.parentId);
    }
    return false;
  }

  for (final folderId in selectedFolderIdSet) {
    final folder = folderById[folderId];
    if (folder != null && !hasSelectedAncestor(folder)) {
      parentOverrides[folder.id] = targetId;
    }
  }

  final targetPathSegments = workspacePathSegmentsForFolder(
    targetId,
    folderList,
  );
  final selectedFileUpdates = <WorkspaceMoveSelectedFileUpdate>[
    for (final selectedFile in selectedFileList)
      WorkspaceMoveSelectedFileUpdate(
        id: selectedFile.id,
        folderId: targetId,
        folderName: targetFolder?.displayName,
        folderColor: targetFolder?.colorHex,
        clearFolderDecorations: selectedFile.isSecured,
        pathSegments: targetPathSegments,
      ),
  ];

  final affectedFolderIds = <String>{};
  for (final folderId in parentOverrides.keys) {
    affectedFolderIds
      ..add(folderId)
      ..addAll(descendantWorkspaceFolderIds(folderId, folderList));
  }

  final folderUpdates = <WorkspaceMoveFolderUpdate>[
    for (final folder in folderList)
      if (affectedFolderIds.contains(folder.id))
        WorkspaceMoveFolderUpdate(
          id: folder.id,
          hasParentIdChange: parentOverrides.containsKey(folder.id),
          parentId: parentOverrides[folder.id],
          pathSegments: workspacePathSegmentsForFolder(
            folder.id,
            folderList,
            parentOverrides: parentOverrides,
          ),
        ),
  ];

  final descendantFileUpdates = <WorkspaceMoveDescendantFileUpdate>[
    for (final file in fileList)
      if (!selectedFileIds.contains(file.id) &&
          affectedFolderIds.contains(
            normalizeWorkspaceFolderId(file.resolvedFolderId),
          ))
        WorkspaceMoveDescendantFileUpdate(
          id: file.id,
          pathSegments: workspacePathSegmentsForFolder(
            file.resolvedFolderId,
            folderList,
            parentOverrides: parentOverrides,
          ),
        ),
  ];

  return WorkspaceMovePlan(
    selectedFileUpdates: selectedFileUpdates,
    folderUpdates: folderUpdates,
    descendantFileUpdates: descendantFileUpdates,
  );
}
