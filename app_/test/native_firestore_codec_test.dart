import 'dart:typed_data';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:cloud_storage/src/linux_cloud/firestore_wire/google/firestore/v1/document.pb.dart'
    as wire;
import 'package:cloud_storage/src/linux_cloud/native_firestore_codec.dart';
import 'package:cloud_storage/src/linux_cloud/native_firestore_writes.dart';
import 'package:cloud_storage/src/linux_cloud/native_firestore_query_spec.dart';
import 'package:cloud_storage/src/linux_cloud/native_firestore_ordering.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_cloud_fixture.dart';

class _Firestore extends FirebaseFirestorePlatform {
  _Firestore(FirebaseApp app, {String databaseId = '(default)'})
    : super(appInstance: app, databaseChoice: databaseId);
  @override
  DocumentReferencePlatform doc(String path) => _Reference(this, path);
}

class _Reference extends DocumentReferencePlatform {
  _Reference(super.firestore, super.path);
}

Matcher _code(String code) =>
    isA<FirebaseException>().having((e) => e.code, 'code', code);

void main() {
  late NativeCloudFixture fixture;
  late _Firestore firestore;
  late NativeFirestoreCodec codec;
  setUp(() async {
    fixture = NativeCloudFixture();
    await fixture.initialize();
    firestore = _Firestore(fixture.app);
    codec = NativeFirestoreCodec(firestore);
  });
  tearDown(() async {
    await fixture.dispose();
  });

  NativeFirestoreQuerySpec query(Map<String, dynamic> parameters) =>
      NativeFirestoreQuerySpec(
        codec: codec,
        path: 'files',
        parameters: parameters,
      );
  wire.Document document(String id, Map<String, Object?> data) => wire.Document(
    name: '${codec.documentsRoot}/files/$id',
    fields: data.entries.map(
      (entry) => MapEntry(entry.key, codec.encode(entry.value)),
    ),
  );

  test('collection and collection-group queries select the correct parent', () {
    final top = query({});
    expect(top.parent, codec.documentsRoot);
    expect(top.build().from.single.collectionId, 'files');
    expect(top.build().orderBy.single.field_1.fieldPath, '__name__');
    final nested = NativeFirestoreQuerySpec(
      codec: codec,
      path: 'users/a/files',
    );
    expect(nested.parent, '${codec.documentsRoot}/users/a');
    final group = NativeFirestoreQuerySpec(
      codec: codec,
      path: 'files',
      collectionGroup: true,
    );
    expect(group.build().from.single.allDescendants, true);
  });

  test('inequality fields and document identity complete stable ordering', () {
    final spec = query({
      'where': [
        ['size', '>', 100],
        ['updatedAt', '<', Timestamp(100, 0)],
      ],
      'orderBy': [
        ['size', true],
      ],
    });
    final built = spec.build();
    expect(built.where.compositeFilter.filters, hasLength(2));
    expect(built.orderBy.map((order) => order.field_1.fieldPath), [
      'size',
      'updatedAt',
      '__name__',
    ]);
    expect(built.orderBy.map((order) => order.direction.name).toSet(), {
      'DESCENDING',
    });
  });

  test('null and NaN equality use their unary filter representation', () {
    expect(
      query({
        'where': [
          ['value', '==', null],
        ],
      }).build().where.unaryFilter.op.name,
      'IS_NULL',
    );
    expect(
      query({
        'where': [
          ['value', '!=', null],
        ],
      }).build().where.unaryFilter.op.name,
      'IS_NOT_NULL',
    );
    expect(
      query({
        'where': [
          ['value', '==', double.nan],
        ],
      }).build().where.unaryFilter.op.name,
      'IS_NAN',
    );
  });

  test('document-ID filters contain full same-database references', () {
    final built = query({
      'where': [
        [
          FieldPath.documentId,
          'in',
          ['a', 'b'],
        ],
      ],
    }).build();
    expect(
      built.where.fieldFilter.value.arrayValue.values.map(
        (value) => value.referenceValue,
      ),
      ['${codec.documentsRoot}/files/a', '${codec.documentsRoot}/files/b'],
    );
    expect(
      () => query({
        'where': [
          [FieldPath.documentId, '==', 'foreign/path'],
        ],
      }).build(),
      throwsA(_code('invalid-argument')),
    );
  });

  test(
    'IN can compare a stored array without allowing nested stored arrays',
    () {
      final built = query({
        'where': [
          [
            'tags',
            'in',
            [
              ['a', 'b'],
            ],
          ],
        ],
      }).build();
      expect(
        built.where.fieldFilter.value.arrayValue.values.single.arrayValue.values
            .map((value) => value.stringValue),
        ['a', 'b'],
      );
      expect(
        () => codec.encode([
          ['a', 'b'],
        ]),
        throwsA(_code('invalid-argument')),
      );
    },
  );

  test(
    'last-page queries reverse both order and cursor inclusivity on the wire',
    () {
      final spec = query({
        'orderBy': [
          [FieldPath.documentId, false],
        ],
        'startAt': ['a'],
        'endBefore': ['z'],
        'limitToLast': 3,
      });
      final built = spec.build();
      expect(built.orderBy.single.direction.name, 'DESCENDING');
      expect(
        built.startAt.values.single.referenceValue,
        '${codec.documentsRoot}/files/z',
      );
      expect(
        built.endAt.values.single.referenceValue,
        '${codec.documentsRoot}/files/a',
      );
      expect(built.startAt.before, false);
      expect(built.endAt.before, false);
      expect(built.limit.value, 3);
      expect(
        spec
            .sorted([document('b', {}), document('a', {})])
            .map((doc) => doc.name.split('/').last),
        ['a', 'b'],
      );
    },
  );

  test(
    'query views sort native numeric boundaries without rounding integers',
    () {
      final spec = query({
        'orderBy': [
          ['value', false],
        ],
      });
      final docs = spec.sorted([
        document('large', {'value': 9007199254740993}),
        document('double', {'value': 9007199254740992.0}),
        document('nan', {'value': double.nan}),
        document('negative', {'value': double.negativeInfinity}),
      ]);
      expect(docs.map((doc) => doc.name.split('/').last), [
        'nan',
        'negative',
        'double',
        'large',
      ]);
    },
  );

  test(
    'Unicode strings and document references follow UTF-8/path-segment order',
    () {
      expect(
        NativeFirestoreOrdering.compare(
          codec.encode('\uE000'),
          codec.encode('\u{10000}'),
        ),
        lessThan(0),
      );
      expect(
        NativeFirestoreOrdering.compare(
          wire.Value(referenceValue: '${codec.documentsRoot}/groups/a/files/x'),
          wire.Value(
            referenceValue: '${codec.documentsRoot}/groups/a-1/files/x',
          ),
        ),
        lessThan(0),
      );
      expect(
        NativeFirestoreOrdering.compare(
          codec.encode({'a': 1}),
          codec.encode({'a': 1, 'b': 2}),
        ),
        lessThan(0),
      );
    },
  );

  test('overwrite, merge and empty maps produce different explicit masks', () {
    final writes = NativeFirestoreWrites(codec);
    final overwrite = writes.set('files/a', {
      'nested': {'x': 1},
    });
    expect(overwrite.hasUpdateMask(), false);
    final merge = writes.set('files/a', {
      'nested': {'x': 1},
      'empty': <String, dynamic>{},
    }, SetOptions(merge: true));
    expect(merge.updateMask.fieldPaths, unorderedEquals(['nested.x', 'empty']));
    expect(merge.update.fields['empty']!.mapValue.fields, isEmpty);
  });

  test(
    'mergeFields excludes unselected transforms and validates every requested path',
    () {
      final writes = NativeFirestoreWrites(codec);
      final increment = FieldValuePlatform(
        NativeFieldValueFactory().increment(2),
      );
      final write = writes.set('files/a', {
        'selected': 1,
        'counter': increment,
      }, SetOptions(mergeFields: ['selected']));
      expect(write.updateMask.fieldPaths, ['selected']);
      expect(write.updateTransforms, isEmpty);
      expect(
        () => writes.set('files/a', {
          'nested': {'x': 1},
        }, SetOptions(mergeFields: ['nested', 'nested.missing'])),
        throwsA(_code('invalid-argument')),
      );
    },
  );

  test(
    'set treats dotted keys literally while update treats them as nested paths',
    () {
      final writes = NativeFirestoreWrites(codec);
      final set = writes.set('files/a', {'a.b': 1}, SetOptions(merge: true));
      expect(set.update.fields['a.b']!.integerValue.toInt(), 1);
      expect(set.updateMask.fieldPaths, ['`a.b`']);
      final update = writes.update('files/a', {'a.b': 1});
      expect(
        update.update.fields['a']!.mapValue.fields['b']!.integerValue.toInt(),
        1,
      );
      expect(update.updateMask.fieldPaths, ['a.b']);
      expect(update.currentDocument.exists, true);
    },
  );

  test(
    'update replaces an explicit map and rejects overlapping field paths',
    () {
      final writes = NativeFirestoreWrites(codec);
      final update = writes.update('files/a', {
        'a': {'b': 1},
      });
      expect(update.updateMask.fieldPaths, ['a']);
      expect(
        () => writes.update('files/a', {
          'a': {'b': 1},
          'a.b': 2,
        }),
        throwsA(_code('invalid-argument')),
      );
      expect(
        () => writes.update('files/a', {}),
        throwsA(_code('invalid-argument')),
      );
    },
  );

  test('delete sentinels remove fields only in allowed write contexts', () {
    final writes = NativeFirestoreWrites(codec);
    final deletion = FieldValuePlatform(NativeFieldValueFactory().delete());
    expect(
      () => writes.set('files/a', {'gone': deletion}),
      throwsA(_code('invalid-argument')),
    );
    final merged = writes.set('files/a', {
      'nested': {'gone': deletion},
    }, SetOptions(merge: true));
    expect(merged.updateMask.fieldPaths, ['nested.gone']);
    expect(merged.update.fields['nested']!.mapValue.fields, isEmpty);
    expect(
      () => writes.update('files/a', {
        'nested': {'gone': deletion},
      }),
      throwsA(_code('invalid-argument')),
    );
    final updated = writes.update('files/a', {'nested.gone': deletion});
    expect(updated.updateMask.fieldPaths, ['nested.gone']);
    expect(updated.update.fields, isEmpty);
  });

  test(
    'transform-only updates preserve fields and use server-side operations',
    () {
      final factory = NativeFieldValueFactory();
      final write = NativeFirestoreWrites(codec).update('files/a', {
        'counter': FieldValuePlatform(factory.increment(2)),
        'updatedAt': FieldValuePlatform(factory.serverTimestamp()),
        'members': FieldValuePlatform(factory.arrayUnion(['user-a'])),
        'removed': FieldValuePlatform(factory.arrayRemove(['user-b'])),
      });
      expect(write.hasUpdateMask(), true);
      expect(write.updateMask.fieldPaths, isEmpty);
      expect(write.update.fields, isEmpty);
      expect(write.updateTransforms.map((value) => value.fieldPath), [
        'counter',
        'updatedAt',
        'members',
        'removed',
      ]);
      expect(write.updateTransforms.first.increment.integerValue.toInt(), 2);
      expect(write.updateTransforms[1].hasSetToServerValue(), true);
      expect(
        write
            .updateTransforms[2]
            .appendMissingElements
            .values
            .single
            .stringValue,
        'user-a',
      );
      expect(
        write.updateTransforms[3].removeAllFromArray.values.single.stringValue,
        'user-b',
      );
    },
  );

  test('scalar and nested metadata preserve their types and 64-bit values', () {
    final original = <String, Object?>{
      'empty': null,
      'enabled': true,
      'small': -1,
      'largest': 9223372036854775807,
      'smallest': -9223372036854775808,
      'ratio': 1.25,
      'name': 'Česká složka 📁',
      'items': [
        1,
        {
          'nested': [true, 'text'],
        },
      ],
    };
    expect(codec.decode(codec.encode(original)), original);
  });
  test(
    'timestamps preserve nanoseconds and normalize dates before the epoch',
    () {
      final timestamp = Timestamp(-1, 999999999);
      expect(codec.decode(codec.encode(timestamp)), timestamp);
      final time = DateTime.fromMicrosecondsSinceEpoch(-1, isUtc: true);
      expect(codec.decode(codec.encode(time)), Timestamp(-1, 999999000));
    },
  );
  test('floating point special values round-trip through binary protobuf', () {
    expect((codec.decode(codec.encode(double.nan)) as double).isNaN, true);
    expect(codec.decode(codec.encode(double.infinity)), double.infinity);
    expect(
      codec.decode(codec.encode(double.negativeInfinity)),
      double.negativeInfinity,
    );
  });
  test('binary data is copied before asynchronous RPC use', () {
    final bytes = Uint8List.fromList([0, 1, 255]);
    final value = codec.encode(Blob(bytes));
    bytes[0] = 99;
    expect(value.bytesValue, [0, 1, 255]);
    expect((codec.decode(value) as Blob).bytes, [0, 1, 255]);
  });
  test('geographic coordinates remain geographic values', () {
    const point = GeoPoint(50.0755, 14.4378);
    expect(codec.decode(codec.encode(point)), point);
  });
  test('document references resolve within the exact configured database', () {
    final reference = firestore.doc('files/český');
    final value = codec.encode(reference);
    expect(value.referenceValue, '${codec.documentsRoot}/files/český');
    expect(
      (codec.decode(value) as DocumentReferencePlatform).path,
      reference.path,
    );
    expect(
      () => codec.encode(
        _Firestore(fixture.app, databaseId: 'another-db').doc('files/a'),
      ),
      throwsA(_code('invalid-argument')),
    );
    expect(
      () => codec.decode(
        wire.Value(
          referenceValue:
              'projects/foreign/databases/(default)/documents/files/a',
        ),
      ),
      throwsA(_code('data-loss')),
    );
  });
  test('literal field names are escaped while dotted paths stay nested', () {
    expect(NativeFirestoreCodec.fieldPath('folder.name'), 'folder.name');
    expect(
      NativeFirestoreCodec.fieldPath(FieldPath(['folder.name'])),
      '`folder.name`',
    );
    expect(NativeFirestoreCodec.fieldPath(FieldPath.documentId), '__name__');
    expect(
      NativeFirestoreCodec.fieldPath(FieldPath(['tick`slash\\'])),
      r'`tick\`slash\\`',
    );
    expect(
      () => NativeFirestoreCodec.fieldPath('a..b'),
      throwsA(_code('invalid-argument')),
    );
  });
  test(
    'sentinels are retained as write operations and rejected as literal data',
    () {
      final factory = NativeFieldValueFactory();
      final operation = factory.increment(5) as NativeFieldOperation;
      expect(
        NativeFirestoreCodec.operation(FieldValuePlatform(operation)),
        same(operation),
      );
      expect(operation.kind, NativeFieldOperationKind.increment);
      expect(operation.value, 5);
      expect(
        () => codec.encode(FieldValuePlatform(operation)),
        throwsA(_code('invalid-argument')),
      );
      expect(
        () => codec.encode([
          [1],
        ]),
        throwsA(_code('invalid-argument')),
      );
      expect(
        () => codec.encode({1: 'unsupported'}),
        throwsA(_code('invalid-argument')),
      );
      expect(() => codec.decode(wire.Value()), throwsA(_code('data-loss')));
    },
  );
}
