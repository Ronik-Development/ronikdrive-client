import 'dart:math' as math;

// Initial-load and memory acceptance gates have not passed.
const workspaceIncrementalIndexEnabled = bool.fromEnvironment(
  'WORKSPACE_INCREMENTAL_INDEX',
  defaultValue: false,
);

/// Account-local effective records. Small batches update a compact sorted list;
/// large replacements rebuild it once. Equal sort keys use legacy List.sort.
class WorkspaceRecordIndex<T> {
  WorkspaceRecordIndex({
    required this.compare,
    required this.include,
    required this.weight,
    required this.bucketOf,
  });
  final Comparator<T> compare;
  final bool Function(T) include;
  final int Function(T) weight;
  final String Function(T) bucketOf;
  final Map<String, T> _records = {};
  final Map<String, Map<String, T>> _buckets = {};
  final Map<String, T?> _pending = {};
  List<MapEntry<String, T>> _sorted = [];
  List<T>? _view;
  int _ties = 0;
  int totalWeight = 0;
  int revision = 0;

  void invalidateSourceOrder() {
    _view = null;
  }

  void apply(String id, T? record) {
    final old = _records[id];
    if (identical(old, record)) return;
    _pending.putIfAbsent(id, () => old);
    if (old != null) {
      totalWeight -= weight(old);
      final bucket = _buckets[bucketOf(old)]!;
      bucket.remove(id);
      if (bucket.isEmpty) _buckets.remove(bucketOf(old));
      _records.remove(id);
    }
    if (record != null) {
      _records[id] = record;
      totalWeight += weight(record);
      (_buckets[bucketOf(record)] ??= {})[id] = record;
    }
    revision++;
    _view = null;
  }

  int _compareEntries(MapEntry<String, T> a, MapEntry<String, T> b) {
    final order = compare(a.value, b.value);
    return order == 0 ? a.key.compareTo(b.key) : order;
  }

  int _position(MapEntry<String, T> entry) {
    var low = 0, high = _sorted.length;
    while (low < high) {
      final middle = low + ((high - low) ~/ 2);
      if (_compareEntries(_sorted[middle], entry) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _equalAt(int left, int right) =>
      left >= 0 &&
          right < _sorted.length &&
          compare(_sorted[left].value, _sorted[right].value) == 0
      ? 1
      : 0;

  void _flush() {
    if (_pending.isEmpty) return;
    if (_sorted.isEmpty ||
        _pending.length > math.max(32, _records.length ~/ 16)) {
      _sorted = _records.entries.where((entry) => include(entry.value)).toList()
        ..sort(_compareEntries);
      _ties = 0;
      for (var i = 1; i < _sorted.length; i++) {
        _ties += _equalAt(i - 1, i);
      }
    } else {
      for (final pending in _pending.entries) {
        final old = pending.value;
        if (old != null && include(old)) {
          final position = _position(MapEntry(pending.key, old));
          _ties -=
              _equalAt(position - 1, position) +
              _equalAt(position, position + 1);
          _ties += _equalAt(position - 1, position + 1);
          _sorted.removeAt(position);
        }
        final current = _records[pending.key];
        if (current != null && include(current)) {
          final entry = MapEntry(pending.key, current);
          final position = _position(entry);
          _ties -= _equalAt(position - 1, position);
          _sorted.insert(position, entry);
          _ties +=
              _equalAt(position - 1, position) +
              _equalAt(position, position + 1);
        }
      }
    }
    _pending.clear();
  }

  void clear() {
    _records.clear();
    _buckets.clear();
    _sorted.clear();
    _pending.clear();
    _ties = 0;
    totalWeight = 0;
    _view = null;
    revision++;
  }

  Iterable<T> inBucket(String bucket) =>
      List<T>.unmodifiable(_buckets[bucket]?.values ?? <T>[]);

  List<T> sorted({required Iterable<T> Function() legacyOrder}) {
    if (_view != null) return _view!;
    _flush();
    final values = _ties == 0
        ? _sorted.map((entry) => entry.value)
        : (legacyOrder().where(include).toList()..sort(compare));
    return _view = List<T>.unmodifiable(values);
  }
}
