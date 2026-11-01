import 'dart:math';
import 'package:cloud_storage/src/home/workspace_record_index.dart';
import 'package:cloud_storage/src/home/workspace_source_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Row = ({String id, int order, int bytes, String folder, bool active});
int compare(Row a, Row b) => a.order.compareTo(b.order);
Row row(int i, {int? order, bool active = true}) => (
  id: '$i',
  order: order ?? i,
  bytes: i + 1,
  folder: '${i % 7}',
  active: active,
);

void main() {
  for (final count in [100, 10000, 100000]) {
    test('mixed source updates match legacy results for $count records', () {
      final index = WorkspaceRecordIndex<Row>(
        compare: compare,
        include: (r) => r.active,
        weight: (r) => r.bytes,
        bucketOf: (r) => r.folder,
      );
      final source = WorkspaceSourceSnapshot<Row>(index: index);
      final personal = <String, Row>{
        for (var i = 0; i < count; i++) '$i': row(i),
      };
      final business = <String, Row>{};
      source.replace(
        WorkspaceSnapshotSource.personal,
        personal.values,
        idOf: (r) => r.id,
      );
      final random = Random(721);
      for (var step = 0; step < 40; step++) {
        final id = random.nextInt(count);
        final r = row(id, order: random.nextInt(count), active: step % 5 != 0);
        if (step % 3 == 0) {
          business[r.id] = r;
          source.upsert(
            WorkspaceSnapshotSource.assignedBusiness,
            r,
            idOf: (r) => r.id,
          );
        } else if (step % 3 == 1) {
          personal[r.id] = r;
          source.upsert(WorkspaceSnapshotSource.personal, r, idOf: (r) => r.id);
        } else {
          business.remove(r.id);
          personal.remove(r.id);
          source.remove(WorkspaceSnapshotSource.assignedBusiness, r.id);
          source.remove(WorkspaceSnapshotSource.personal, r.id);
        }
        final merged = {...personal, ...business};
        final expected = merged.values.where((r) => r.active).toList()
          ..sort(compare);
        final actual = source.sortedItems;
        expect(actual.length, expected.length);
        expect(
          List.generate(
            actual.length,
            (i) => actual[i] == expected[i],
          ).every((same) => same),
          isTrue,
        );
        expect(
          index.totalWeight,
          merged.values.fold<int>(0, (sum, r) => sum + r.bytes),
        );
        final bucket = index.inBucket('2').toSet();
        final expectedBucket = merged.values
            .where((r) => r.folder == '2')
            .toSet();
        expect(bucket.length, expectedBucket.length);
        expect(expectedBucket.every(bucket.contains), isTrue);
      }
      source.replace(
        WorkspaceSnapshotSource.assignedBusiness,
        [],
        idOf: (r) => r.id,
      );
      expect(
        source.sortedItems,
        personal.values.where((r) => r.active).toList()..sort(compare),
      );
      source.restore([], idOf: (r) => r.id, isAssignedBusiness: (_) => false);
      expect(source.sortedItems, isEmpty);
      expect(index.totalWeight, 0);
    });
  }

  test(
    'equal keys preserve legacy sorting after reorder, revoke and restore',
    () {
      final index = WorkspaceRecordIndex<Row>(
        compare: compare,
        include: (r) => r.active,
        weight: (r) => r.bytes,
        bucketOf: (r) => r.folder,
      );
      final source = WorkspaceSourceSnapshot<Row>(index: index);
      final rows = List.generate(70, (i) => row(i, order: 0));
      source.replace(WorkspaceSnapshotSource.personal, rows, idOf: (r) => r.id);
      final old = source.sortedItems;
      source.replace(
        WorkspaceSnapshotSource.personal,
        rows.reversed,
        idOf: (r) => r.id,
      );
      expect(source.sortedItems, rows.reversed.toList()..sort(compare));
      expect(old, rows.toList()..sort(compare));
      source.removeWhere((r) => int.parse(r.id).isEven);
      expect(
        source.sortedItems,
        rows.reversed.where((r) => int.parse(r.id).isOdd).toList()
          ..sort(compare),
      );
    },
  );
}
