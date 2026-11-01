import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_private_cache.dart';

/// Copy-on-write encrypted buckets. The authenticated head is the commit point;
/// partial generations are never restored and committed corrupt data fails closed.
class EncryptedMetadataShards {
  EncryptedMetadataShards({
    required this.cache,
    required this.preferences,
    required this.baseKey,
    required this.namespace,
    required this.uid,
    required this.scope,
    required this.accountCurrent,
  });
  final LocalPrivateCachePreferences cache;
  final SharedPreferences preferences;
  final String baseKey, namespace, uid, scope;
  final bool Function() accountCurrent;
  Future<void> _chain = Future.value();
  int _epoch = 0;
  int? _expectedEpoch;
  void invalidate() {
    _epoch++;
    _loaded = false;
    _loadedRows = null;
  }

  Future<T> _guard<T>(int epoch, Future<T> Function() action) async {
    _expectedEpoch = epoch;
    try {
      _check();
      final result = await action();
      _check();
      return result;
    } finally {
      _expectedEpoch = null;
    }
  }

  Map<String, dynamic>? _manifest;
  Map<String, Map<String, dynamic>> _rows = {};
  Map<String, String> _encoded = {};
  final Map<String, int> _bucketIds = {};
  int _bucket(String id) => _bucketIds.putIfAbsent(id, () => bucket(id));
  List<String> _order = [];
  List<Map<String, dynamic>>? _loadedRows;
  bool _loaded = false;
  final Map<int, Map?> _cleanupManifests = {};
  static int bucket(String id) =>
      crypto.sha256.convert(utf8.encode(id)).bytes.first;
  String _key(String suffix) => '$baseKey.shards-v2.$suffix';
  void _check() {
    if (!accountCurrent() ||
        (_expectedEpoch != null && _expectedEpoch != _epoch)) {
      throw StateError('Metadata cache ownership or permissions changed.');
    }
  }

  Future<LocalPrivateCachePreferenceRead> _read(String suffix) => cache.read(
    baseKey: _key(suffix),
    namespace: '$namespace:shards-v2:$suffix',
  );
  Future<void> _write(String suffix, String value) async {
    _check();
    await cache.write(
      baseKey: _key(suffix),
      namespace: '$namespace:shards-v2:$suffix',
      value: value,
    );
    _check();
  }

  Future<LocalPrivateCachePreferenceRead> read() {
    final epoch = _epoch;
    final next = _chain.then((_) => _guard(epoch, _readUnlocked));
    _chain = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<LocalPrivateCachePreferenceRead> _readUnlocked() async {
    _check();
    if (_loaded) {
      return LocalPrivateCachePreferenceRead(decodedRows: _loadedRows);
    }
    final head = await _read('head');
    if (head.temporarilyUnavailable || head.discardedCorruptValue) return head;
    if (head.value == null) {
      final legacy = await cache.read(baseKey: baseKey, namespace: namespace);
      _check();
      if (legacy.value != null) {
        try {
          _loadedRows = (jsonDecode(legacy.value!) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } catch (_) {
          return const LocalPrivateCachePreferenceRead(
            discardedCorruptValue: true,
          );
        }
      }
      // Do not mark an absent cache loaded: a later full replacement initializes it.
      return legacy;
    }
    try {
      final pointer = jsonDecode(head.value!) as Map;
      final generation = pointer['generation'];
      if (generation is! int || generation < 1 || pointer['version'] != 2) {
        throw const FormatException();
      }
      final stored = await _read('manifest.${generation % 2}');
      if (stored.temporarilyUnavailable) return stored;
      final manifest = jsonDecode(stored.value!) as Map<String, dynamic>;
      if (manifest['version'] != 2 || manifest['generation'] != generation) {
        throw const FormatException();
      }
      final refs = Map<String, dynamic>.from(manifest['buckets'] as Map);
      if (refs.length > 256) throw const FormatException();
      final rows = <String, Map<String, dynamic>>{};
      final encoded = <String, String>{};
      for (final ref in refs.entries) {
        final index = int.parse(ref.key);
        if (index < 0 ||
            index > 255 ||
            ref.value is! int ||
            ref.value < 1 ||
            ref.value > generation) {
          throw const FormatException();
        }
        final data = await _read('bucket.$index.${ref.value}');
        if (data.temporarilyUnavailable) return data;
        for (final raw in jsonDecode(data.value!) as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          final id = row['id'];
          if (id is! String ||
              id.isEmpty ||
              bucket(id) != index ||
              rows.containsKey(id)) {
            throw const FormatException();
          }
          rows[id] = row;
          encoded[id] = jsonEncode(row);
        }
      }
      final orderGeneration = manifest['orderGeneration'];
      if (orderGeneration is! int ||
          orderGeneration < 1 ||
          orderGeneration > generation) {
        throw const FormatException();
      }
      final orderData = await _read('order.$orderGeneration');
      if (orderData.temporarilyUnavailable) return orderData;
      final order = List<String>.from(jsonDecode(orderData.value!) as List);
      if (order.length != rows.length ||
          order.toSet().length != order.length ||
          order.any((id) => !rows.containsKey(id))) {
        throw const FormatException();
      }
      _check();
      _manifest = manifest;
      _rows = rows;
      _encoded = encoded;
      _order = order;
      _loadedRows = order.map((id) => rows[id]!).toList(growable: false);
      _loaded = true;
      try {
        await _cleanup();
      } catch (_) {
        _check();
      }
      return LocalPrivateCachePreferenceRead(decodedRows: _loadedRows);
    } catch (_) {
      _check();
      return const LocalPrivateCachePreferenceRead(discardedCorruptValue: true);
    }
  }

  Future<void> replace(List<Map<String, dynamic>> rows) {
    final captured = List<Map<String, dynamic>>.of(rows);
    final epoch = _epoch;
    final next = _chain.then((_) => _guard(epoch, () => _replace(captured)));
    _chain = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> _replace(List<Map<String, dynamic>> incoming) async {
    _check();
    if (!_loaded) {
      final initial = await _readUnlocked();
      if (initial.temporarilyUnavailable) {
        throw const LocalPrivateCacheException(
          LocalPrivateCacheFailure.storageFailure,
          'The encrypted metadata cache needs reconciliation.',
        );
      }
    }
    if (!_loaded && (await _readUnlocked()).discardedCorruptValue) {
      // A fresh authoritative replacement may repair a damaged optional cache.
      await _clearUnlocked();
    }
    final nextRows = <String, Map<String, dynamic>>{},
        nextEncoded = <String, String>{};
    final nextOrder = <String>[], dirty = <int>{};
    for (final row in incoming) {
      final id = row['id'];
      if (id is! String || id.isEmpty || nextRows.containsKey(id)) {
        throw const FormatException('Invalid metadata cache identity.');
      }
      final encoded = identical(row, _rows[id])
          ? _encoded[id]!
          : jsonEncode(row);
      nextRows[id] = row;
      nextEncoded[id] = encoded;
      nextOrder.add(id);
      if (encoded != _encoded[id]) dirty.add(_bucket(id));
    }
    for (final id in _rows.keys) {
      if (!nextRows.containsKey(id)) dirty.add(_bucket(id));
    }
    final orderChanged = !listEquals(_order, nextOrder);
    if (dirty.isEmpty && !orderChanged && _manifest != null) return;
    final generation = ((_manifest?['generation'] as int?) ?? 0) + 1;
    final refs = Map<String, dynamic>.from(
      (_manifest?['buckets'] as Map?) ?? {},
    );
    final grouped = <int, List<String>>{for (final index in dirty) index: []};
    for (final id in nextOrder) {
      grouped[_bucket(id)]?.add(nextEncoded[id]!);
    }
    for (final entry in grouped.entries) {
      if (entry.value.isEmpty) {
        refs.remove('${entry.key}');
        continue;
      }
      await _write(
        'bucket.${entry.key}.$generation',
        '[${entry.value.join(',')}]',
      );
      refs['${entry.key}'] = generation;
    }
    final orderGeneration = orderChanged || _manifest == null
        ? generation
        : _manifest!['orderGeneration'] as int;
    if (orderGeneration == generation) {
      await _write('order.$generation', jsonEncode(nextOrder));
    }
    final manifest = {
      'version': 2,
      'generation': generation,
      'orderGeneration': orderGeneration,
      'buckets': refs,
    };
    await _write('manifest.${generation % 2}', jsonEncode(manifest));
    _cleanupManifests[generation % 2] = manifest;
    await _write('head', jsonEncode({'version': 2, 'generation': generation}));
    _manifest = manifest;
    _bucketIds.removeWhere((id, _) => !nextRows.containsKey(id));
    _rows = nextRows;
    _encoded = nextEncoded;
    _order = nextOrder;
    _loadedRows = nextOrder.map((id) => nextRows[id]!).toList(growable: false);
    _loaded = true;
    try {
      await _cleanup();
    } catch (_) {
      _check();
    }
  }

  Future<void> _cleanup() async {
    final keep = <String>{_key('head'), _key('manifest.0'), _key('manifest.1')};
    for (final slot in [0, 1]) {
      try {
        if (!_cleanupManifests.containsKey(slot)) {
          final stored = await _read('manifest.$slot');
          if (stored.temporarilyUnavailable) return;
          _cleanupManifests[slot] = stored.value == null
              ? null
              : jsonDecode(stored.value!) as Map;
        }
        final manifest = _cleanupManifests[slot];
        if (manifest == null) continue;
        keep.add(_key('order.${manifest['orderGeneration']}'));
        for (final e in (manifest['buckets'] as Map).entries) {
          keep.add(_key('bucket.${e.key}.${e.value}'));
        }
      } catch (_) {
        /* Uncommitted invalid manifests do not authorize data. */
      }
    }
    final physical = keep
        .map(
          (key) => LocalPrivateCachePreferences.scopedPreferenceKey(
            key,
            uid,
            scope: scope,
          ),
        )
        .toSet();
    final suffix = LocalPrivateCachePreferences.scopedPreferenceKey(
      'marker',
      uid,
      scope: scope,
    ).substring('marker'.length);
    for (final key in preferences.getKeys()) {
      if (key.startsWith('$baseKey.shards-v2.') &&
          key.endsWith(suffix) &&
          !physical.contains(key)) {
        _check();
        await preferences.remove(key);
      }
    }
  }

  Future<void> clear() async {
    final next = _chain.then((_) => _guard(_epoch, _clearUnlocked));
    _chain = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    await next;
  }

  Future<void> _clearUnlocked() async {
    _check();
    final suffix = LocalPrivateCachePreferences.scopedPreferenceKey(
      'marker',
      uid,
      scope: scope,
    ).substring('marker'.length);
    for (final key in preferences.getKeys()) {
      if (key.startsWith('$baseKey.shards-v2.') && key.endsWith(suffix)) {
        _check();
        await preferences.remove(key);
      }
    }
    _manifest = null;
    _cleanupManifests.clear();
    _rows = {};
    _encoded = {};
    _bucketIds.clear();
    _order = [];
    _loadedRows = null;
    _loaded = false;
    await cache.write(baseKey: baseKey, namespace: namespace, value: null);
  }
}
