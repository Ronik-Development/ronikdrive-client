import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_storage/src/home/workspace_record_index.dart';
import 'package:cloud_storage/src/home/workspace_source_snapshot.dart';

typedef Row = ({String id, int rank, int bytes});
int compare(Row a, Row b) => a.rank.compareTo(b.rank);

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    final count = int.parse(args[1]);
    final records = List.generate(
      count,
      (i) => (id: '$i', rank: i, bytes: i + 1),
    )..shuffle(Random(414));
    final beforeRss = ProcessInfo.currentRss;
    final watch = Stopwatch()..start();
    final index = args[0] == 'indexed'
        ? WorkspaceRecordIndex<Row>(
            compare: compare,
            include: (_) => true,
            weight: (r) => r.bytes,
            bucketOf: (_) => 'root',
          )
        : null;
    final source = WorkspaceSourceSnapshot<Row>(index: index);
    source.replace(
      WorkspaceSnapshotSource.personal,
      records,
      idOf: (r) => r.id,
    );
    final sorted = index == null
        ? (source.mergedItems.toList()..sort(compare))
        : source.sortedItems;
    final weight =
        index?.totalWeight ??
        source.mergedItems.fold<int>(0, (n, r) => n + r.bytes);
    watch.stop();
    if (sorted.length != count || weight != count * (count + 1) ~/ 2) {
      throw StateError('Mismatch');
    }
    stdout.writeln(
      jsonEncode({
        'mode': args[0],
        'count': count,
        'microseconds': watch.elapsedMicroseconds,
        'rssBytes': ProcessInfo.currentRss,
        'beforeRssBytes': beforeRss,
        'maxRssBytes': ProcessInfo.maxRss,
      }),
    );
    return;
  }
  final samples = [];
  for (final count in [100, 10000, 100000]) {
    for (var repeat = 0; repeat < 30; repeat++) {
      for (final mode
          in repeat.isEven ? ['legacy', 'indexed'] : ['indexed', 'legacy']) {
        final result = await Process.run(Platform.resolvedExecutable, [
          mode,
          '$count',
        ]);
        if (result.exitCode != 0) throw StateError('Child benchmark failed');
        samples.add(jsonDecode(result.stdout as String));
      }
    }
  }
  stdout.writeln(
    jsonEncode({
      'kind': 'synthetic-first-projection-fresh-process',
      'samples': samples,
    }),
  );
}
