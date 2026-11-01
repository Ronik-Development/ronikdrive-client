import 'dart:io';

import 'package:cloud_storage/src/home/workspace_source_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

class _Record {
  const _Record(this.id, this.label, [this.size = 0]);

  final String id;
  final String label;
  final int size;
}

void main() {
  group('WorkspaceSourceSnapshot', () {
    test(
      'reuses only unchanged immutable views and invalidates every mutation',
      () {
        final snapshot = WorkspaceSourceSnapshot<_Record>();
        String idOf(_Record record) => record.id;
        snapshot.replace(WorkspaceSnapshotSource.personal, const [
          _Record('one', 'Personal'),
        ], idOf: idOf);
        final oldView = snapshot.mergedItems;
        expect(identical(oldView, snapshot.mergedItems), isTrue);
        expect(() => oldView.clear(), throwsUnsupportedError);
        snapshot.upsert(
          WorkspaceSnapshotSource.assignedBusiness,
          const _Record('one', 'Shared'),
          idOf: idOf,
        );
        expect(snapshot.mergedItems.single.label, 'Shared');
        expect(oldView.single.label, 'Personal');
        snapshot.remove(WorkspaceSnapshotSource.assignedBusiness, 'one');
        expect(snapshot.mergedItems.single.label, 'Personal');
        snapshot.updateExisting(const _Record('one', 'Updated'), idOf: idOf);
        expect(snapshot.mergedItems.single.label, 'Updated');
        snapshot.replace(WorkspaceSnapshotSource.personal, const [
          _Record('two', 'Replacement'),
        ], idOf: idOf);
        expect(snapshot.mergedItems.single.id, 'two');
        snapshot.restore(
          const [_Record('three', 'Restored')],
          idOf: idOf,
          isAssignedBusiness: (_) => true,
        );
        expect(snapshot.mergedItems.single.id, 'three');
        snapshot.removeWhere((record) => record.id == 'three');
        expect(snapshot.mergedItems, isEmpty);
      },
    );

    test('merges Personal and assigned Business records by opaque ID', () {
      final snapshot = WorkspaceSourceSnapshot<_Record>();
      snapshot.replace(WorkspaceSnapshotSource.personal, const <_Record>[
        _Record('personal', 'Personal'),
        _Record('shared', 'Older copy'),
      ], idOf: (record) => record.id);
      snapshot.replace(
        WorkspaceSnapshotSource.assignedBusiness,
        const <_Record>[
          _Record('business', 'Business'),
          _Record('shared', 'Current copy'),
        ],
        idOf: (record) => record.id,
      );

      final records = <String, _Record>{
        for (final record in snapshot.mergedItems) record.id: record,
      };
      expect(records.keys, <String>{'personal', 'shared', 'business'});
      expect(records['shared']?.label, 'Current copy');
    });

    test('replacing one source preserves the other source', () {
      final snapshot = WorkspaceSourceSnapshot<_Record>();
      snapshot.replace(WorkspaceSnapshotSource.personal, const <_Record>[
        _Record('personal', 'Personal'),
      ], idOf: (record) => record.id);
      snapshot.replace(
        WorkspaceSnapshotSource.assignedBusiness,
        const <_Record>[_Record('business', 'Business')],
        idOf: (record) => record.id,
      );

      snapshot.replace(WorkspaceSnapshotSource.personal, const <_Record>[
        _Record('personal-2', 'Personal 2'),
      ], idOf: (record) => record.id);

      expect(snapshot.mergedItems.map((record) => record.id).toSet(), <String>{
        'personal-2',
        'business',
      });
    });

    test('incremental changes affect only their owning source', () {
      final snapshot = WorkspaceSourceSnapshot<_Record>();
      snapshot.replace(WorkspaceSnapshotSource.personal, const <_Record>[
        _Record('shared', 'Personal copy'),
        _Record('personal', 'Personal'),
      ], idOf: (record) => record.id);
      snapshot.replace(
        WorkspaceSnapshotSource.assignedBusiness,
        const <_Record>[
          _Record('shared', 'Business copy'),
          _Record('business', 'Business'),
        ],
        idOf: (record) => record.id,
      );

      snapshot.remove(WorkspaceSnapshotSource.assignedBusiness, 'shared');
      snapshot.upsert(
        WorkspaceSnapshotSource.assignedBusiness,
        const _Record('business-2', 'Business 2'),
        idOf: (record) => record.id,
      );
      expect(
        snapshot.updateExisting(
          const _Record('business', 'Business updated'),
          idOf: (record) => record.id,
        ),
        isTrue,
      );

      final records = <String, _Record>{
        for (final record in snapshot.mergedItems) record.id: record,
      };
      expect(records['shared']?.label, 'Personal copy');
      expect(
        snapshot.item(WorkspaceSnapshotSource.personal, 'shared'),
        isNotNull,
      );
      expect(
        snapshot
            .itemsFor(WorkspaceSnapshotSource.assignedBusiness)
            .map((record) => record.id),
        <String>['business', 'business-2'],
      );
      expect(
        snapshot
            .item(WorkspaceSnapshotSource.assignedBusiness, 'business')
            ?.label,
        'Business updated',
      );
    });

    test(
      'merged quota counts a duplicate once and follows valid ownership',
      () {
        final snapshot = WorkspaceSourceSnapshot<_Record>();
        snapshot.replace(WorkspaceSnapshotSource.personal, const <_Record>[
          _Record('shared', 'Personal copy', 10),
          _Record('personal', 'Personal', 5),
        ], idOf: (record) => record.id);
        snapshot.replace(
          WorkspaceSnapshotSource.assignedBusiness,
          const <_Record>[
            _Record('shared', 'Business copy', 10),
            _Record('business', 'Business', 20),
          ],
          idOf: (record) => record.id,
        );

        expect(
          snapshot.mergedItems.fold<int>(
            0,
            (total, record) => total + record.size,
          ),
          35,
        );

        snapshot.removeWhere((record) => record.id == 'business');
        snapshot.remove(WorkspaceSnapshotSource.assignedBusiness, 'shared');

        expect(
          snapshot.mergedItems.fold<int>(
            0,
            (total, record) => total + record.size,
          ),
          15,
        );
      },
    );

    test('restores source ownership and removes revoked Business records', () {
      final snapshot = WorkspaceSourceSnapshot<_Record>();
      snapshot.restore(
        const <_Record>[
          _Record('personal', 'Personal'),
          _Record('business', 'Business'),
        ],
        idOf: (record) => record.id,
        isAssignedBusiness: (record) => record.id == 'business',
      );

      snapshot.removeWhere((record) => record.id == 'business');

      expect(snapshot.mergedItems.map((record) => record.id), const <String>[
        'personal',
      ]);
    });
  });

  test(
    'folder stream contract merges sources and discards raw diagnostics',
    () {
      final source = File(
        'lib/src/home/workspace_home_page.dart',
      ).readAsStringSync();

      expect(source, contains('WorkspaceSnapshotSource.assignedBusiness'));
      expect(source, contains('WorkspaceSnapshotSource.personal'));
      expect(source, contains('_pendingFolderSnapshotProcessing'));
      expect(source, contains('_folderSnapshotSources.mergedItems'));
      expect(
        source,
        contains('Your last verified folder view remains available'),
      );
      expect(
        source,
        isNot(contains("debugPrint('Failed to load folders: \$error')")),
      );
      expect(
        source,
        isNot(contains('Failed to parse folder document \${doc.id}')),
      );
      expect(
        source,
        isNot(contains('Failed to persist cached folders: \$error')),
      );
      expect(
        source,
        isNot(contains('Failed to restore cached folders: \$error')),
      );
    },
  );

  test(
    'file stream contract isolates sources, cache ownership, and diagnostics',
    () {
      final source = File(
        'lib/src/home/workspace_home_page.dart',
      ).readAsStringSync();

      expect(source, contains('_fileSnapshotSources.mergedItems'));
      expect(source, contains('_initializedFileSnapshotSources'));
      expect(source, contains('_companyStorageStreamGeneration'));
      expect(
        source,
        contains('companyStreamGeneration == _companyStorageStreamGeneration'),
      );
      expect(source, contains('_hasAppliedUserProfileState'));
      expect(source, contains('!_hasAppliedUserProfileState ||'));
      expect(source, contains('markSourceInitialized: false'));
      expect(
        source,
        contains('_hasAppliedUserProfileState && !_canReadCompanyStorage'),
      );
      expect(source, contains('if (companyStreamAccessChanged)'));
      expect(
        source,
        isNot(contains('if (companyAccessChanged || stateChanged)')),
      );
      expect(source, contains("'_localSourceMembership': sourceMembership"));
      expect(source, contains('personalFileDocuments: ownedFiles.docs'));
      expect(source, contains('assignedFileDocuments: assignedFileDocuments'));
      expect(source, contains('Files could not be refreshed.'));
      expect(source, contains('verified file view'));
      expect(
        source,
        isNot(contains("debugPrint('Failed to load files: \$error')")),
      );
      expect(
        source,
        isNot(contains('Failed to parse file document \${doc.id}')),
      );
      expect(
        source,
        isNot(contains('Failed to persist cached files: \$error')),
      );
      expect(
        source,
        isNot(contains('Failed to restore cached files: \$error')),
      );
    },
  );
}
