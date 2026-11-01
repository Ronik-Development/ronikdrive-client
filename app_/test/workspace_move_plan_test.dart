import 'package:cloud_storage/src/home/workspace_move_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildWorkspaceMovePlan', () {
    test('uses null folder id and empty path segments for root file moves', () {
      final plan = buildWorkspaceMovePlan(
        folders: const <WorkspaceMoveFolderSnapshot>[],
        files: const <WorkspaceMoveFileSnapshot>[
          WorkspaceMoveFileSnapshot(id: 'file-1', resolvedFolderId: 'inbox'),
        ],
        selectedFiles: const <WorkspaceMoveFileSnapshot>[
          WorkspaceMoveFileSnapshot(id: 'file-1'),
        ],
        selectedFolderIds: const <String>[],
        destinationFolderId: 'root',
      );

      expect(plan.selectedFileUpdates, hasLength(1));
      final update = plan.selectedFileUpdates.single;
      expect(update.id, 'file-1');
      expect(update.folderId, isNull);
      expect(update.folderName, isNull);
      expect(update.folderColor, isNull);
      expect(update.pathSegments, isEmpty);
    });

    test(
      'updates a nested folder parent and path when moved under a folder',
      () {
        final plan = buildWorkspaceMovePlan(
          folders: const <WorkspaceMoveFolderSnapshot>[
            WorkspaceMoveFolderSnapshot(id: 'clients', name: 'Clients'),
            WorkspaceMoveFolderSnapshot(
              id: 'reports',
              name: 'Reports',
              parentId: 'archive',
            ),
            WorkspaceMoveFolderSnapshot(id: 'archive', name: 'Archive'),
          ],
          files: const <WorkspaceMoveFileSnapshot>[],
          selectedFiles: const <WorkspaceMoveFileSnapshot>[],
          selectedFolderIds: const <String>['reports'],
          destinationFolderId: 'clients',
        );

        expect(plan.folderUpdates, hasLength(1));
        final update = plan.folderUpdates.single;
        expect(update.id, 'reports');
        expect(update.hasParentIdChange, isTrue);
        expect(update.parentId, 'clients');
        expect(update.pathSegments, const <String>['Clients', 'Reports']);
      },
    );

    test('moves selected folder descendants to root path segments', () {
      final plan = buildWorkspaceMovePlan(
        folders: const <WorkspaceMoveFolderSnapshot>[
          WorkspaceMoveFolderSnapshot(
            id: 'reports',
            name: 'Reports',
            parentId: 'clients',
          ),
          WorkspaceMoveFolderSnapshot(
            id: 'deep',
            name: 'Deep Dive',
            parentId: 'reports',
          ),
          WorkspaceMoveFolderSnapshot(id: 'clients', name: 'Clients'),
        ],
        files: const <WorkspaceMoveFileSnapshot>[
          WorkspaceMoveFileSnapshot(
            id: 'nested-file',
            resolvedFolderId: 'deep',
          ),
        ],
        selectedFiles: const <WorkspaceMoveFileSnapshot>[],
        selectedFolderIds: const <String>['reports'],
        destinationFolderId: null,
      );

      final folderUpdates = {
        for (final update in plan.folderUpdates) update.id: update,
      };
      expect(folderUpdates['reports']?.hasParentIdChange, isTrue);
      expect(folderUpdates['reports']?.parentId, isNull);
      expect(folderUpdates['reports']?.pathSegments, const <String>['Reports']);
      expect(folderUpdates['deep']?.hasParentIdChange, isFalse);
      expect(folderUpdates['deep']?.pathSegments, const <String>[
        'Reports',
        'Deep Dive',
      ]);

      expect(plan.descendantFileUpdates, hasLength(1));
      expect(plan.descendantFileUpdates.single.id, 'nested-file');
      expect(plan.descendantFileUpdates.single.pathSegments, const <String>[
        'Reports',
        'Deep Dive',
      ]);
    });

    test('moves selected files to a nested folder with target metadata', () {
      final plan = buildWorkspaceMovePlan(
        folders: const <WorkspaceMoveFolderSnapshot>[
          WorkspaceMoveFolderSnapshot(id: 'clients', name: 'Clients'),
          WorkspaceMoveFolderSnapshot(
            id: 'reports',
            name: 'Reports',
            parentId: 'clients',
            colorHex: '#2c7be5',
          ),
        ],
        files: const <WorkspaceMoveFileSnapshot>[
          WorkspaceMoveFileSnapshot(id: 'selected-file'),
        ],
        selectedFiles: const <WorkspaceMoveFileSnapshot>[
          WorkspaceMoveFileSnapshot(id: 'selected-file'),
        ],
        selectedFolderIds: const <String>[],
        destinationFolderId: 'reports',
      );

      expect(plan.selectedFileUpdates, hasLength(1));
      final update = plan.selectedFileUpdates.single;
      expect(update.id, 'selected-file');
      expect(update.folderId, 'reports');
      expect(update.folderName, 'Reports');
      expect(update.folderColor, '#2c7be5');
      expect(update.pathSegments, const <String>['Clients', 'Reports']);
    });
  });
}
