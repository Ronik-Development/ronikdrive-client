import 'package:cloud_storage/src/home/workspace_view_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every List and Map mutation invalidates the current derived view', () {
    final rows = RevisionList<int>()..addAll([3, 1, 2]);
    final offline = RevisionMap<String, int>();
    final cache = WorkspaceViewCache<List<int>>();
    var calls = 0;
    List<int> read(String account, bool allowed) =>
        cache.resolve((account, allowed, rows.revision, offline.revision), () {
          calls++;
          return allowed ? rows.toList() : [];
        });
    final first = read('alice', true);
    expect(identical(first, read('alice', true)), isTrue);
    final mutations = <void Function()>[
      () => rows[0] = 4,
      () => rows.sort(),
      () => rows.removeWhere((r) => r == 1),
      () => rows.insert(0, 5),
      () => rows.removeAt(0),
      () => rows.addAll([6]),
      () => rows.length = 1,
      () => offline['x'] = 1,
      () => offline.remove('x'),
      () => rows.clear(),
    ];
    for (final mutate in mutations) {
      final before = calls;
      mutate();
      read('alice', true);
      expect(calls, before + 1);
    }
    expect(read('alice', false), isEmpty);
    final before = calls;
    read('bob', false);
    expect(calls, before + 1);
    cache.clear();
    read('bob', false);
    expect(calls, before + 2);
    expect(first, [3, 1, 2]);
  });
}
