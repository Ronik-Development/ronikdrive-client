import 'dart:typed_data';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protobuf/well_known_types/google/protobuf/struct.pbenum.dart'
    as proto;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as proto;

import 'firestore_wire/google/firestore/v1/document.pb.dart' as wire;
import 'firestore_wire/google/type/latlng.pb.dart' as geo;

enum NativeFieldOperationKind {
  arrayUnion,
  arrayRemove,
  delete,
  increment,
  serverTimestamp,
}

class NativeFieldOperation {
  const NativeFieldOperation(this.kind, [this.value]);
  final NativeFieldOperationKind kind;
  final Object? value;
}

class NativeFieldValueFactory extends FieldValueFactoryPlatform {
  @override
  dynamic arrayUnion(List<dynamic> elements) => NativeFieldOperation(
    NativeFieldOperationKind.arrayUnion,
    List.unmodifiable(elements),
  );
  @override
  dynamic arrayRemove(List<dynamic> elements) => NativeFieldOperation(
    NativeFieldOperationKind.arrayRemove,
    List.unmodifiable(elements),
  );
  @override
  dynamic delete() =>
      const NativeFieldOperation(NativeFieldOperationKind.delete);
  @override
  dynamic increment(num value) =>
      NativeFieldOperation(NativeFieldOperationKind.increment, value);
  @override
  dynamic serverTimestamp() =>
      const NativeFieldOperation(NativeFieldOperationKind.serverTimestamp);
}

class NativeFirestoreCodec {
  NativeFirestoreCodec(this.firestore);
  final FirebaseFirestorePlatform firestore;
  String get database =>
      'projects/${firestore.app.options.projectId}/databases/${firestore.databaseId}';
  String get documentsRoot => '$database/documents';
  static FirebaseException invalid([String code = 'invalid-argument']) =>
      FirebaseException(
        plugin: 'cloud_firestore',
        code: code,
        message: 'The database value or field path is not supported.',
      );

  static NativeFieldOperation? operation(Object? value) {
    final delegate = value is FieldValuePlatform
        ? FieldValuePlatform.getDelegate(value)
        : value;
    return delegate is NativeFieldOperation ? delegate : null;
  }

  static List<String> fieldComponents(Object field) {
    if (field == FieldPath.documentId) return ['__name__'];
    if (field is String && field.split('.').any((part) => part.isEmpty)) {
      throw invalid();
    }
    final components = field is FieldPath
        ? field.components
        : field is String
        ? FieldPath.fromString(field).components
        : throw invalid();
    if (components.isEmpty ||
        components.any((part) => part.isEmpty || part.contains('\u0000'))) {
      throw invalid();
    }
    return List.unmodifiable(components);
  }

  static String fieldPath(Object field) => fieldComponents(field)
      .map(
        (part) => RegExp(r'^[_A-Za-z][_A-Za-z0-9]*$').hasMatch(part)
            ? part
            : '`${part.replaceAll('\\', '\\\\').replaceAll('`', '\\`')}`',
      )
      .join('.');

  wire.Value encode(Object? value, {bool inArray = false}) {
    if (value == null) return wire.Value(nullValue: proto.NullValue.NULL_VALUE);
    if (value is bool) return wire.Value(booleanValue: value);
    if (value is int) return wire.Value(integerValue: Int64(value));
    if (value is double) return wire.Value(doubleValue: value);
    if (value is String) return wire.Value(stringValue: value);
    if (value is DateTime) return encode(Timestamp.fromDate(value));
    if (value is Timestamp) {
      return wire.Value(
        timestampValue: proto.Timestamp(
          seconds: Int64(value.seconds),
          nanos: value.nanoseconds,
        ),
      );
    }
    if (value is GeoPoint) {
      return wire.Value(
        geoPointValue: geo.LatLng(
          latitude: value.latitude,
          longitude: value.longitude,
        ),
      );
    }
    if (value is Blob) return wire.Value(bytesValue: List<int>.of(value.bytes));
    if (value is Uint8List) return wire.Value(bytesValue: List<int>.of(value));
    if (value is DocumentReferencePlatform) {
      final root =
          'projects/${value.firestore.app.options.projectId}/databases/${value.firestore.databaseId}/documents';
      if (root != documentsRoot) throw invalid();
      return wire.Value(referenceValue: '$documentsRoot/${value.path}');
    }
    if (value is List) {
      if (inArray) throw invalid();
      return wire.Value(
        arrayValue: wire.ArrayValue(
          values: value.map((item) => encode(item, inArray: true)),
        ),
      );
    }
    if (value is Map) {
      if (value.keys.any((key) => key is! String)) throw invalid();
      return wire.Value(
        mapValue: wire.MapValue(
          fields: value.entries.map(
            (entry) => MapEntry(entry.key as String, encode(entry.value)),
          ),
        ),
      );
    }
    // Sentinels belong to a write transform, never to an ordinary value.
    throw invalid();
  }

  Object? decode(wire.Value value) => switch (value.whichValueType()) {
    wire.Value_ValueType.nullValue => null,
    wire.Value_ValueType.booleanValue => value.booleanValue,
    wire.Value_ValueType.integerValue => value.integerValue.toInt(),
    wire.Value_ValueType.doubleValue => value.doubleValue,
    wire.Value_ValueType.stringValue => value.stringValue,
    wire.Value_ValueType.timestampValue => Timestamp(
      value.timestampValue.seconds.toInt(),
      value.timestampValue.nanos,
    ),
    wire.Value_ValueType.geoPointValue => GeoPoint(
      value.geoPointValue.latitude,
      value.geoPointValue.longitude,
    ),
    wire.Value_ValueType.bytesValue => Blob(
      Uint8List.fromList(value.bytesValue),
    ),
    wire.Value_ValueType.arrayValue =>
      value.arrayValue.values.map(decode).toList(),
    wire.Value_ValueType.mapValue => value.mapValue.fields.map(
      (key, entry) => MapEntry(key, decode(entry)),
    ),
    wire.Value_ValueType.referenceValue => _reference(value.referenceValue),
    _ => throw invalid('data-loss'),
  };
  DocumentReferencePlatform _reference(String resource) {
    if (!resource.startsWith('$documentsRoot/')) throw invalid('data-loss');
    final path = resource.substring(documentsRoot.length + 1);
    final parts = path.split('/');
    if (parts.length.isOdd || parts.any((part) => part.isEmpty)) {
      throw invalid('data-loss');
    }
    return firestore.doc(path);
  }

  Map<String, dynamic> decodeFields(Map<String, wire.Value> fields) =>
      fields.map((key, value) => MapEntry(key, decode(value)));
}
