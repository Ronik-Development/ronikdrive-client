import 'dart:collection';

/// A single projection, never a history of queries, accounts or private labels.
class WorkspaceViewCache<T> {
  Object? _key;
  T? _value;
  T resolve(Object key, T Function() build) {
    if (_key == key && _value != null) return _value as T;
    clear();
    final value = build();
    _key = key;
    _value = value;
    return value;
  }

  void clear() {
    _key = null;
    _value = null;
  }
}

/// Covers mutations through List interfaces, including optimistic updates.
class RevisionList<T> extends ListBase<T> {
  final List<T> _values = [];
  int revision = 0;
  @override
  int get length => _values.length;
  @override
  set length(int value) {
    _values.length = value;
    revision++;
  }

  @override
  T operator [](int index) => _values[index];
  @override
  void operator []=(int index, T value) {
    _values[index] = value;
    revision++;
  }

  @override
  void add(T element) {
    _values.add(element);
    revision++;
  }

  @override
  void addAll(Iterable<T> iterable) {
    _values.addAll(iterable);
    revision++;
  }

  @override
  void clear() {
    _values.clear();
    revision++;
  }

  @override
  void insert(int index, T element) {
    _values.insert(index, element);
    revision++;
  }

  @override
  T removeAt(int index) {
    final value = _values.removeAt(index);
    revision++;
    return value;
  }

  @override
  void sort([Comparator<T>? compare]) {
    _values.sort(compare);
    revision++;
  }
}

class RevisionMap<K, V> extends MapBase<K, V> {
  final Map<K, V> _values = {};
  int revision = 0;
  @override
  V? operator [](Object? key) => _values[key];
  @override
  void operator []=(K key, V value) {
    _values[key] = value;
    revision++;
  }

  @override
  Iterable<K> get keys => _values.keys;
  @override
  V? remove(Object? key) {
    final value = _values.remove(key);
    revision++;
    return value;
  }

  @override
  void clear() {
    _values.clear();
    revision++;
  }
}
