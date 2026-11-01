import 'dart:convert';
import 'package:cloud_storage/src/privacy/encrypted_metadata_shards.dart';
import 'package:cloud_storage/src/privacy/local_private_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Keys implements LocalPrivateCacheKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Cache extends LocalPrivateCachePreferences {
  _Cache(
    SharedPreferences prefs,
    LocalPrivateCacheCodec codec, {
    super.uid = 'synthetic',
  }) : super(preferences: prefs, scope: 'test', codec: codec);
  final writes = <String>[];
  bool failHead = false;
  @override
  Future<void> write({
    required String baseKey,
    required String namespace,
    required String? value,
  }) async {
    writes.add(baseKey);
    if (failHead && baseKey.endsWith('.head')) {
      throw StateError('Synthetic interrupted commit');
    }
    await super.write(baseKey: baseKey, namespace: namespace, value: value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late LocalPrivateCacheCodec codec;
  late _Cache cache;
  var current = true;
  EncryptedMetadataShards store({
    _Cache? privateCache,
    String uid = 'synthetic',
  }) => EncryptedMetadataShards(
    cache: privateCache ?? cache,
    preferences: prefs,
    baseKey: 'synthetic_metadata',
    namespace: 'synthetic_metadata',
    uid: uid,
    scope: 'test',
    accountCurrent: () => current,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    codec = LocalPrivateCacheCodec(keyStore: _Keys());
    cache = _Cache(prefs, codec);
    current = true;
  });
  List<Map<String, dynamic>> rows(int n) => List.generate(
    n,
    (i) => {
      'id': 'record-$i',
      'size': i,
      'name': 'synthetic-$i',
      '_localSourceMembership': [i.isEven ? 'personal' : 'assignedBusiness'],
    },
  );
  test(
    'one changed record rewrites one bucket and manifest, not unchanged order',
    () async {
      final data = rows(10000), s = store();
      await s.replace(data);
      cache.writes.clear();
      data[5000] = {...data[5000], 'size': 123};
      await s.replace(data);
      expect(cache.writes.where((k) => k.contains('.bucket.')).length, 1);
      expect(cache.writes.where((k) => k.contains('.order.')), isEmpty);
      expect(cache.writes.length, 3);
      expect((await store().read()).decodedRows, data);
      for (final value
          in prefs.getKeys().map(prefs.getString).whereType<String>()) {
        expect(value, isNot(contains('synthetic-5000')));
      }
    },
  );
  test(
    'interrupted head commit preserves the previous complete generation',
    () async {
      final data = rows(100), s = store();
      await s.replace(data);
      cache.failHead = true;
      await expectLater(
        s.replace([
          {...data.first, 'size': 999},
          ...data.skip(1),
        ]),
        throwsStateError,
      );
      cache.failHead = false;
      expect((await store().read()).decodedRows, data);
      await store().replace(data);
      expect((await store().read()).decodedRows, data);
    },
  );
  test(
    'mixed additions, removal and reorder preserve exact rows and membership',
    () async {
      final data = rows(100), s = store();
      await s.replace(data);
      final changed = [
        {
          'id': 'new',
          'size': 4,
          '_localSourceMembership': ['personal', 'assignedBusiness'],
        },
        ...data.skip(2).toList().reversed,
      ];
      await s.replace(changed);
      expect((await store().read()).decodedRows, changed);
      final other = _Cache(prefs, codec, uid: 'different');
      expect(
        (await store(privateCache: other, uid: 'different').read()).decodedRows,
        isNull,
      );
    },
  );
  test(
    'legacy cache remains readable, and locked or switched accounts fail safely',
    () async {
      final data = rows(100);
      await cache.write(
        baseKey: 'synthetic_metadata',
        namespace: 'synthetic_metadata',
        value: jsonEncode(data),
      );
      expect((await store().read()).value, jsonEncode(data));
      await store().replace(data);
      expect((await store().read()).decodedRows, data);
      current = false;
      await expectLater(store().read(), throwsStateError);
      await expectLater(store().replace(data), throwsStateError);
    },
  );
  test(
    'corrupt committed bucket is not replaced with stale earlier authorization',
    () async {
      final data = rows(100), s = store();
      await s.replace(data);
      await s.replace(data.skip(1).toList());
      final key = prefs.getKeys().firstWhere(
        (k) => k.contains('.bucket.') && k.contains('.2_account_'),
      );
      await prefs.setString(key, 'synthetic-corruption');
      final result = await store().read();
      expect(result.discardedCorruptValue, true);
      expect(result.decodedRows, isNull);
    },
  );
  test('authoritative replacement repairs a damaged optional cache', () async {
    final data = rows(100);
    await store().replace(data);
    final key = prefs.getKeys().firstWhere((k) => k.contains('.bucket.'));
    await prefs.setString(key, 'synthetic-corruption');
    final replacement = store();
    expect((await replacement.read()).discardedCorruptValue, true);
    await replacement.replace(data.skip(1).toList());
    expect((await store().read()).decodedRows, data.skip(1).toList());
  });
  for (final count in [100, 10000, 100000]) {
    test(
      'mixed reconstruction and 30 warm updates at $count records',
      () async {
        final data = rows(count), s = store();
        await s.replace(data);
        final times = <int>[], legacyTimes = <int>[];
        for (var i = 0; i < 30; i++) {
          data[count ~/ 2] = {...data[count ~/ 2], 'size': i};
          cache.writes.clear();
          final watch = Stopwatch()..start();
          await s.replace(data);
          times.add(watch.elapsedMicroseconds);
          expect(cache.writes.length, 3);
          final legacyWatch = Stopwatch()..start();
          await cache.write(
            baseKey: 'benchmark_old',
            namespace: 'benchmark_old',
            value: jsonEncode(data),
          );
          legacyTimes.add(legacyWatch.elapsedMicroseconds);
        }
        final changed = [
          data.last,
          {
            'id': 'inserted',
            'size': 4,
            '_localSourceMembership': ['personal', 'assignedBusiness'],
          },
          ...data.skip(1).take(count - 2).toList().reversed,
        ];
        await s.replace(changed);
        expect((await store().read()).decodedRows, changed);
        times.sort();
        legacyTimes.sort();
        // Only synthetic timing summaries; no filenames, keys or customer content.
        // ignore: avoid_print
        print(
          jsonEncode({
            'metadataRecords': count,
            'repetitions': 30,
            'shardedMedianUs': times[15],
            'shardedP95Us': times[28],
            'legacyMedianUs': legacyTimes[15],
            'legacyP95Us': legacyTimes[28],
            'environment': 'mock preferences, encrypted synthetic metadata',
          }),
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
  test(
    'permission invalidation rejects already queued reads and writes',
    () async {
      final data = rows(100), s = store();
      await s.replace(data);
      final oldRead = s.read(), oldWrite = s.replace(data.skip(1).toList());
      s.invalidate();
      await expectLater(oldRead, throwsStateError);
      await expectLater(oldWrite, throwsStateError);
      await s.clear();
      expect((await store().read()).decodedRows, isNull);
      await s.replace(data.skip(1).toList());
      expect((await store().read()).decodedRows, data.skip(1).toList());
    },
  );
}
