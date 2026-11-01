import 'workspace_record_index.dart';

enum WorkspaceSnapshotSource { personal, assignedBusiness }

class WorkspaceSourceSnapshot<T> {
  WorkspaceSourceSnapshot({this.index, this.equivalent});
  final WorkspaceRecordIndex<T>? index;
  final bool Function(T, T)? equivalent;
  int revision = 0;

  void _refreshIds(Iterable<String> ids) {
    _mergedItems = null;
    revision++;
    if (index == null) return;
    index!.invalidateSourceOrder();
    for (final id in ids) {
      index?.apply(id, _assignedBusiness[id] ?? _personal[id]);
    }
  }

  List<T> get sortedItems => index!.sorted(legacyOrder: () => mergedItems);

  final Map<String, T> _personal = <String, T>{};
  final Map<String, T> _assignedBusiness = <String, T>{};
  // Repeated consumers share one immutable view until either source changes.
  List<T>? _mergedItems;

  Map<String, T> _recordsFor(WorkspaceSnapshotSource source) {
    return switch (source) {
      WorkspaceSnapshotSource.personal => _personal,
      WorkspaceSnapshotSource.assignedBusiness => _assignedBusiness,
    };
  }

  void replace(
    WorkspaceSnapshotSource source,
    Iterable<T> records, {
    required String Function(T record) idOf,
  }) {
    final target = _recordsFor(source);
    if (index == null && equivalent == null) {
      target
        ..clear()
        ..addEntries(records.map((record) => MapEntry(idOf(record), record)));
      _refreshIds(const []);
      return;
    }
    final ids = target.keys.toSet();
    final replacement = <String, T>{};
    for (final record in records) {
      final id = idOf(record);
      final old = target[id];
      replacement[id] = old != null && equivalent?.call(old, record) == true
          ? old
          : record;
    }
    target
      ..clear()
      ..addAll(replacement);
    _refreshIds(ids..addAll(target.keys));
  }

  void upsert(
    WorkspaceSnapshotSource source,
    T record, {
    required String Function(T record) idOf,
  }) {
    final id = idOf(record);
    _recordsFor(source)[id] = record;
    _refreshIds([id]);
  }

  T? remove(WorkspaceSnapshotSource source, String id) {
    final removed = _recordsFor(source).remove(id);
    if (removed != null) _refreshIds([id]);
    return removed;
  }

  T? item(WorkspaceSnapshotSource source, String id) {
    return _recordsFor(source)[id];
  }

  bool updateExisting(T record, {required String Function(T record) idOf}) {
    final id = idOf(record);
    var updated = false;
    if (_personal.containsKey(id)) {
      _personal[id] = record;
      updated = true;
    }
    if (_assignedBusiness.containsKey(id)) {
      _assignedBusiness[id] = record;
      updated = true;
    }
    if (updated) _refreshIds([id]);
    return updated;
  }

  List<T> itemsFor(WorkspaceSnapshotSource source) {
    return List<T>.unmodifiable(_recordsFor(source).values);
  }

  void restore(
    Iterable<T> records, {
    required String Function(T record) idOf,
    required bool Function(T record) isAssignedBusiness,
  }) {
    final ids = {..._personal.keys, ..._assignedBusiness.keys};
    _personal.clear();
    _assignedBusiness.clear();
    for (final record in records) {
      final target = isAssignedBusiness(record) ? _assignedBusiness : _personal;
      target[idOf(record)] = record;
    }
    _refreshIds(
      ids
        ..addAll(_personal.keys)
        ..addAll(_assignedBusiness.keys),
    );
  }

  void removeWhere(bool Function(T record) predicate) {
    final ids = <String>{};
    bool remove(String id, T record) {
      if (!predicate(record)) return false;
      ids.add(id);
      return true;
    }

    _personal.removeWhere(remove);
    _assignedBusiness.removeWhere(remove);
    if (ids.isNotEmpty) _refreshIds(ids);
  }

  List<T> get mergedItems {
    final cached = _mergedItems;
    if (cached != null) return cached;
    final merged = <String, T>{..._personal, ..._assignedBusiness};
    return _mergedItems = List<T>.unmodifiable(merged.values);
  }
}
