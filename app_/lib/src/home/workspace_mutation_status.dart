import 'package:flutter/material.dart';

enum WorkspaceMutationAction {
  renameFile,
  moveItems,
  createFolder,
  renameFolder,
  removeFolder,
  deleteItems,
}

enum WorkspaceMutationOutcome { rejected, uncertain }

class WorkspaceDeleteSelectionPlan {
  const WorkspaceDeleteSelectionPlan({
    required this.rootFolderIds,
    required this.standaloneFileIds,
  });

  final Set<String> rootFolderIds;
  final Set<String> standaloneFileIds;
}

WorkspaceDeleteSelectionPlan buildWorkspaceDeleteSelectionPlan({
  required Map<String, String?> folderParentIds,
  required Iterable<String> selectedFolderIds,
  required Map<String, String?> selectedFileFolderIds,
}) {
  final selectedFolders = selectedFolderIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();

  bool hasSelectedAncestor(String folderId) {
    final visited = <String>{folderId};
    var parentId = folderParentIds[folderId];
    while (parentId != null && parentId.isNotEmpty && visited.add(parentId)) {
      if (selectedFolders.contains(parentId)) {
        return true;
      }
      parentId = folderParentIds[parentId];
    }
    return false;
  }

  final rootFolderIds = selectedFolders
      .where((folderId) => !hasSelectedAncestor(folderId))
      .toSet();

  bool isInsideSelectedFolderTree(String? folderId) {
    final visited = <String>{};
    var currentId = folderId;
    while (currentId != null &&
        currentId.isNotEmpty &&
        visited.add(currentId)) {
      if (rootFolderIds.contains(currentId)) {
        return true;
      }
      currentId = folderParentIds[currentId];
    }
    return false;
  }

  final standaloneFileIds = selectedFileFolderIds.entries
      .where((entry) => !isInsideSelectedFolderTree(entry.value))
      .map((entry) => entry.key)
      .toSet();

  return WorkspaceDeleteSelectionPlan(
    rootFolderIds: Set<String>.unmodifiable(rootFolderIds),
    standaloneFileIds: Set<String>.unmodifiable(standaloneFileIds),
  );
}

class WorkspaceMutationFailure {
  const WorkspaceMutationFailure({required this.action, required this.outcome});

  final WorkspaceMutationAction action;
  final WorkspaceMutationOutcome outcome;

  bool get requiresAuthoritativeRefresh =>
      outcome == WorkspaceMutationOutcome.uncertain;

  String get message {
    if (requiresAuthoritativeRefresh) {
      return 'RonikCloud could not confirm the final result of this file or '
          'folder change. The last verified workspace remains visible. '
          'Refresh files before repeating it or starting another workspace '
          'change.';
    }
    return switch (action) {
      WorkspaceMutationAction.renameFile =>
        'The file was not renamed. Refresh files and try again.',
      WorkspaceMutationAction.createFolder =>
        'The folder was not created. Refresh files and try again.',
      WorkspaceMutationAction.moveItems ||
      WorkspaceMutationAction.renameFolder ||
      WorkspaceMutationAction.removeFolder ||
      WorkspaceMutationAction.deleteItems =>
        'The workspace change was not accepted. Refresh files and try again.',
    };
  }

  String get safeLogCategory => switch (action) {
    WorkspaceMutationAction.renameFile => 'rename_file',
    WorkspaceMutationAction.moveItems => 'move_items',
    WorkspaceMutationAction.createFolder => 'create_folder',
    WorkspaceMutationAction.renameFolder => 'rename_folder',
    WorkspaceMutationAction.removeFolder => 'remove_folder',
    WorkspaceMutationAction.deleteItems => 'delete_items',
  };
}

WorkspaceMutationFailure classifyWorkspaceMutationFailure({
  required WorkspaceMutationAction action,
  String? cloudCode,
}) {
  final normalizedCode = cloudCode
      ?.trim()
      .toLowerCase()
      .replaceAll('_', '-')
      .replaceFirst('firebase-firestore/', '')
      .replaceFirst('cloud-firestore/', '');
  final requestWasDefinitelyRejected = const <String>{
    'already-exists',
    'failed-precondition',
    'invalid-argument',
    'not-found',
    'permission-denied',
    'resource-exhausted',
    'unauthenticated',
  }.contains(normalizedCode);
  final canPartiallyApply = switch (action) {
    WorkspaceMutationAction.renameFile ||
    WorkspaceMutationAction.createFolder => false,
    WorkspaceMutationAction.moveItems ||
    WorkspaceMutationAction.renameFolder ||
    WorkspaceMutationAction.removeFolder ||
    WorkspaceMutationAction.deleteItems => true,
  };

  return WorkspaceMutationFailure(
    action: action,
    outcome: requestWasDefinitelyRejected && !canPartiallyApply
        ? WorkspaceMutationOutcome.rejected
        : WorkspaceMutationOutcome.uncertain,
  );
}

class WorkspaceMutationStatusNotice extends StatelessWidget {
  const WorkspaceMutationStatusNotice({
    super.key,
    required this.failure,
    required this.refreshing,
    required this.onRefresh,
  });

  final WorkspaceMutationFailure failure;
  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MaterialBanner(
      backgroundColor: colorScheme.errorContainer,
      leading: Icon(
        Icons.sync_problem_outlined,
        color: colorScheme.onErrorContainer,
      ),
      content: Text(
        failure.message,
        style: TextStyle(color: colorScheme.onErrorContainer),
      ),
      actions: [
        FilledButton.icon(
          onPressed: refreshing ? null : onRefresh,
          icon: refreshing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_outlined),
          label: Text(refreshing ? 'Refreshing files' : 'Refresh files'),
        ),
      ],
    );
  }
}
