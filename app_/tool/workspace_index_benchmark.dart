import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_storage/src/home/workspace_record_index.dart';
import 'package:cloud_storage/src/home/workspace_source_snapshot.dart';

typedef Row = ({String id, int rank, int bytes});
int compare(Row a, Row b) => a.rank.compareTo(b.rank);

void main(List<String> args) {
  final samples = <Map<String, Object>>[];
  for (final count in [100, 10000, 100000]) {
    final random = Random(414);
    final records = List.generate(
      count,
      (i) => (id: '$i', rank: i, bytes: i + 1),
    )..shuffle(random);
    final index = WorkspaceRecordIndex<Row>(
      compare: compare,
      include: (_) => true,
      weight: (r) => r.bytes,
      bucketOf: (_) => 'root',
    );
    final indexed = WorkspaceSourceSnapshot<Row>(index: index);
    final legacy = WorkspaceSourceSnapshot<Row>();
    indexed.replace(
      WorkspaceSnapshotSource.personal,
      records,
      idOf: (r) => r.id,
    );
    legacy.replace(
      WorkspaceSnapshotSource.personal,
      records,
      idOf: (r) => r.id,
    );
    indexed.sortedItems;
    for (var repeat = -3; repeat < 30; repeat++) {
      final id = random.nextInt(count);
      final row = (id: '$id', rank: count + repeat + 3, bytes: 17);
      final modes = repeat.isEven
          ? ['legacy', 'indexed']
          : ['indexed', 'legacy'];
      List<Row>? previous;
      for (final mode in modes) {
        final source = mode == 'legacy' ? legacy : indexed;
        final watch = Stopwatch()..start();
        source.upsert(WorkspaceSnapshotSource.personal, row, idOf: (r) => r.id);
        final result = mode == 'legacy'
            ? (source.mergedItems.toList()..sort(compare))
            : source.sortedItems;
        final usage = mode == 'legacy'
            ? source.mergedItems.fold<int>(0, (n, r) => n + r.bytes)
            : index.totalWeight;
        watch.stop();
        if (previous != null) {
          for (var i = 0; i < result.length; i++) {
            if (previous[i] != result[i]) {
              throw StateError('Projection mismatch');
            }
          }
        }
        previous = result;
        if (repeat >= 0) {
          samples.add({
            'count': count,
            'repeat': repeat,
            'mode': mode,
            'microseconds': watch.elapsedMicroseconds,
            'usage': usage,
            'rssBytes': ProcessInfo.currentRss,
          });
        }
      }
    }
  }
  stdout.writeln(
    jsonEncode({
      'kind': 'synthetic-local-AOT',
      'samples': samples,
      'maxRssBytes': ProcessInfo.maxRss,
    }),
  );
}
