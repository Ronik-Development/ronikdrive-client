// CPU/allocation microbenchmark, not Firestore or rendered UI latency.
import 'dart:convert';
import 'dart:io';
import 'package:cloud_storage/src/home/workspace_source_snapshot.dart';

void main() {
  final results = <Map<String, Object>>[];
  for (final count in [100, 10000, 100000]) {
    final snapshot = WorkspaceSourceSnapshot<int>();
    final personal = {for (var i = 0; i < count; i++) '$i': i};
    final business = {for (var i = count ~/ 2; i < count; i++) '$i': -i};
    snapshot.replace(
      WorkspaceSnapshotSource.personal,
      personal.values,
      idOf: (item) => '$item',
    );
    snapshot.replace(
      WorkspaceSnapshotSource.assignedBusiness,
      business.values,
      idOf: (item) => '${-item}',
    );
    List<int> baseline() =>
        List<int>.unmodifiable(<String, int>{...personal, ...business}.values);
    List<int> candidate() => snapshot.mergedItems;
    for (var repetition = -5; repetition < 30; repetition++) {
      final methods = [('baseline', baseline), ('candidate', candidate)];
      for (final (method, read)
          in repetition.isEven ? methods : methods.reversed) {
        // Each scenario includes a mutation, first read and repeated reads.
        snapshot.upsert(WorkspaceSnapshotSource.personal, 0, idOf: (_) => '0');
        final watch = Stopwatch()..start();
        final first = read();
        final coldMicros = watch.elapsedMicroseconds;
        if (first.length != count || first.last != -(count - 1)) {
          throw StateError('Merged source semantics changed');
        }
        watch.reset();
        for (var access = 0; access < 20; access++) {
          final values = read();
          if (values.length != count) throw StateError('Missing records');
        }
        if (repetition >= 0) {
          results.add({
            'records': count,
            'method': method,
            'repetition': repetition,
            'firstReadUs': coldMicros,
            'twentyWarmReadsUs': watch.elapsedMicroseconds,
          });
        }
      }
    }
  }
  stdout.writeln(
    jsonEncode({
      'benchmark': 'metadata-merge-AOT',
      'network': false,
      'renderedUI': false,
      'samples': results,
      'processPeakRssBytes': ProcessInfo.maxRss,
    }),
  );
}
