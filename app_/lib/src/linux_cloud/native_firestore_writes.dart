import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

import 'firestore_wire/google/firestore/v1/common.pb.dart' as common;
import 'firestore_wire/google/firestore/v1/document.pb.dart' as wire;
import 'firestore_wire/google/firestore/v1/write.pb.dart' as rpc;
import 'native_firestore_codec.dart';

class NativeFirestoreWrites {
  NativeFirestoreWrites(this.codec);
  final NativeFirestoreCodec codec;
  String resource(String path) {
    final parts = path.split('/');
    if (parts.length.isOdd ||
        parts.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains('\u0000'),
        )) {
      throw NativeFirestoreCodec.invalid();
    }
    return '${codec.documentsRoot}/$path';
  }

  rpc.Write delete(String path) => rpc.Write(delete: resource(path));

  rpc.Write set(String path, Map<String, dynamic> data, [SetOptions? options]) {
    final parsed = _ParsedWrite(codec);
    final merging = options?.merge == true || options?.mergeFields != null;
    final value = parsed.parse(
      data,
      [],
      deleteAllowed: merging,
      nestedDeleteAllowed: merging,
    )!;
    List<List<String>>? mask;
    final selected = options?.mergeFields;
    if (selected != null) {
      final requested = selected
          .map(NativeFirestoreCodec.fieldComponents)
          .toList();
      for (final field in requested) {
        if (!parsed.provided.any((provided) => _same(field, provided))) {
          throw NativeFirestoreCodec.invalid();
        }
      }
      mask = _normalize(requested);
    } else if (merging) {
      mask = _normalize(parsed.mask);
    }
    final transforms = parsed.transforms
        .where(
          (entry) =>
              selected == null ||
              mask!.any((field) => _prefix(field, entry.$1)),
        )
        .map((entry) => parsed.transform(entry.$1, entry.$2));
    return rpc.Write(
      update: wire.Document(
        name: resource(path),
        fields: value.mapValue.fields.entries,
      ),
      updateMask: mask == null
          ? null
          : common.DocumentMask(fieldPaths: mask.map(_path)),
      updateTransforms: transforms,
    );
  }

  rpc.Write update(String path, Map<Object, dynamic> data) {
    if (data.isEmpty) throw NativeFirestoreCodec.invalid();
    final parsed = _ParsedWrite(codec);
    final fields = <String, wire.Value>{};
    final paths = data.keys.map(NativeFirestoreCodec.fieldComponents).toList();
    for (var index = 0; index < paths.length; index++) {
      if (paths
          .skip(index + 1)
          .any(
            (other) =>
                _prefix(paths[index], other) || _prefix(other, paths[index]),
          )) {
        throw NativeFirestoreCodec.invalid();
      }
    }
    final mask = <List<String>>[];
    var index = 0;
    for (final entry in data.entries) {
      final field = paths[index++];
      final value = parsed.parse(
        entry.value,
        field,
        deleteAllowed: true,
        nestedDeleteAllowed: false,
      );
      final operation = NativeFirestoreCodec.operation(entry.value);
      if (value != null) {
        _put(fields, field, value);
        mask.add(field);
      } else if (operation?.kind == NativeFieldOperationKind.delete) {
        mask.add(field);
      }
    }
    return rpc.Write(
      update: wire.Document(name: resource(path), fields: fields.entries),
      updateMask: common.DocumentMask(fieldPaths: mask.map(_path)),
      currentDocument: common.Precondition(exists: true),
      updateTransforms: parsed.transforms.map(
        (entry) => parsed.transform(entry.$1, entry.$2),
      ),
    );
  }

  static void _put(
    Map<String, wire.Value> fields,
    List<String> path,
    wire.Value value,
  ) {
    var current = fields;
    for (final part in path.take(path.length - 1)) {
      final parent = current.putIfAbsent(
        part,
        () => wire.Value(mapValue: wire.MapValue()),
      );
      if (!parent.hasMapValue()) throw NativeFirestoreCodec.invalid();
      current = parent.mapValue.fields;
    }
    current[path.last] = value;
  }

  static String _path(List<String> components) =>
      NativeFirestoreCodec.fieldPath(FieldPath(components));
  static bool _prefix(List<String> a, List<String> b) =>
      a.length <= b.length &&
      Iterable<int>.generate(a.length).every((index) => a[index] == b[index]);
  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length && _prefix(a, b);
  static List<List<String>> _normalize(Iterable<List<String>> fields) {
    final unique = <String, List<String>>{
      for (final field in fields) _path(field): field,
    }.values.toList();
    return unique
        .where(
          (field) => !unique.any(
            (parent) => parent.length < field.length && _prefix(parent, field),
          ),
        )
        .toList();
  }
}

class _ParsedWrite {
  _ParsedWrite(this.codec);
  final NativeFirestoreCodec codec;
  final mask = <List<String>>[];
  final provided = <List<String>>[];
  final transforms = <(List<String>, NativeFieldOperation)>[];

  wire.Value? parse(
    Object? value,
    List<String> path, {
    required bool deleteAllowed,
    required bool nestedDeleteAllowed,
  }) {
    if (path.isNotEmpty) provided.add(path);
    final operation = NativeFirestoreCodec.operation(value);
    if (operation != null) {
      if (path.isEmpty) throw NativeFirestoreCodec.invalid();
      if (operation.kind == NativeFieldOperationKind.delete) {
        if (!deleteAllowed) throw NativeFirestoreCodec.invalid();
        mask.add(path);
      } else {
        transforms.add((path, operation));
      }
      return null;
    }
    if (value is Map) {
      if (value.keys.any(
        (key) => key is! String || key.isEmpty || key.contains('\u0000'),
      )) {
        throw NativeFirestoreCodec.invalid();
      }
      final fields = <String, wire.Value>{};
      for (final entry in value.entries) {
        final child = parse(
          entry.value,
          [...path, entry.key as String],
          deleteAllowed: nestedDeleteAllowed,
          nestedDeleteAllowed: nestedDeleteAllowed,
        );
        if (child != null) fields[entry.key as String] = child;
      }
      if (value.isEmpty && path.isNotEmpty) mask.add(path);
      return wire.Value(mapValue: wire.MapValue(fields: fields.entries));
    }
    mask.add(path);
    return codec.encode(value);
  }

  rpc.DocumentTransform_FieldTransform transform(
    List<String> path,
    NativeFieldOperation operation,
  ) {
    final field = NativeFirestoreWrites._path(path);
    return switch (operation.kind) {
      NativeFieldOperationKind.serverTimestamp =>
        rpc.DocumentTransform_FieldTransform(
          fieldPath: field,
          setToServerValue:
              rpc.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME,
        ),
      NativeFieldOperationKind.increment =>
        rpc.DocumentTransform_FieldTransform(
          fieldPath: field,
          increment: codec.encode(operation.value),
        ),
      NativeFieldOperationKind.arrayUnion =>
        rpc.DocumentTransform_FieldTransform(
          fieldPath: field,
          appendMissingElements: wire.ArrayValue(
            values: (operation.value as List).map(
              (value) => codec.encode(value, inArray: true),
            ),
          ),
        ),
      NativeFieldOperationKind.arrayRemove =>
        rpc.DocumentTransform_FieldTransform(
          fieldPath: field,
          removeAllFromArray: wire.ArrayValue(
            values: (operation.value as List).map(
              (value) => codec.encode(value, inArray: true),
            ),
          ),
        ),
      NativeFieldOperationKind.delete => throw NativeFirestoreCodec.invalid(),
    };
  }
}
