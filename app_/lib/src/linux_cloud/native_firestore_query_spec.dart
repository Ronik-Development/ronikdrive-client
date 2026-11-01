import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:protobuf/well_known_types/google/protobuf/wrappers.pb.dart';

import 'firestore_wire/google/firestore/v1/document.pb.dart' as wire;
import 'firestore_wire/google/firestore/v1/query.pb.dart' as rpc;
import 'native_firestore_codec.dart';
import 'native_firestore_ordering.dart';
import 'native_firestore_writes.dart';

class NativeQueryOrder {
  NativeQueryOrder(List<String> field, this.descending)
    : field = List.unmodifiable(field);
  final List<String> field;
  final bool descending;
  bool get isName => field.length == 1 && field.single == '__name__';
}

class NativeFirestoreQuerySpec {
  NativeFirestoreQuerySpec({
    required this.codec,
    required this.path,
    this.collectionGroup = false,
    Map<String, dynamic>? parameters,
  }) : parameters = Map.unmodifiable({
         'where': <List<dynamic>>[],
         'orderBy': <List<dynamic>>[],
         'startAt': null,
         'startAfter': null,
         'endAt': null,
         'endBefore': null,
         'limit': null,
         'limitToLast': null,
         ...?parameters,
       }) {
    final parts = path.split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        (collectionGroup ? parts.length != 1 : parts.length.isEven)) {
      throw NativeFirestoreCodec.invalid();
    }
  }
  final NativeFirestoreCodec codec;
  final String path;
  final bool collectionGroup;
  final Map<String, dynamic> parameters;
  String get parent {
    if (collectionGroup || !path.contains('/')) return codec.documentsRoot;
    return '${codec.documentsRoot}/${path.substring(0, path.lastIndexOf('/'))}';
  }

  NativeFirestoreQuerySpec copy(Map<String, dynamic> changes) =>
      NativeFirestoreQuerySpec(
        codec: codec,
        path: path,
        collectionGroup: collectionGroup,
        parameters: {...parameters, ...changes},
      );
  List<List<dynamic>> get conditions => List<List<dynamic>>.from(
    (parameters['where'] as List).map(
      (value) => List<dynamic>.from(value as List),
    ),
  );

  List<NativeQueryOrder> get orders {
    final rows = List<List<dynamic>>.from(
      (parameters['orderBy'] as List).map(
        (value) => List<dynamic>.from(value as List),
      ),
    );
    final result = <NativeQueryOrder>[];
    for (final row in rows) {
      if (row.length != 2 || row[1] is! bool) {
        throw NativeFirestoreCodec.invalid();
      }
      result.add(
        NativeQueryOrder(
          NativeFirestoreCodec.fieldComponents(row[0]),
          row[1] as bool,
        ),
      );
    }
    final descending = result.isNotEmpty && result.last.descending;
    final required = <String, List<String>>{};
    for (final condition in conditions) {
      if (condition.length != 3) throw NativeFirestoreCodec.invalid();
      if (const {'<', '<=', '>', '>=', '!=', 'not-in'}.contains(condition[1])) {
        final field = NativeFirestoreCodec.fieldComponents(condition[0]);
        if (!(field.length == 1 && field.single == '__name__')) {
          required[NativeFirestoreCodec.fieldPath(condition[0])] = field;
        }
      }
    }
    final additional = required.values.toList()
      ..sort(NativeFirestoreOrdering.path);
    for (final field in additional) {
      if (!result.any(
        (order) => NativeFirestoreOrdering.path(order.field, field) == 0,
      )) {
        result.add(NativeQueryOrder(field, descending));
      }
    }
    if (!result.any((order) => order.isName)) {
      result.add(NativeQueryOrder(['__name__'], descending));
    }
    return result;
  }

  wire.Value _nameValue(Object? value) {
    if (value is DocumentReferencePlatform) return codec.encode(value);
    if (value is! String ||
        value.isEmpty ||
        (!collectionGroup && value.contains('/'))) {
      throw NativeFirestoreCodec.invalid();
    }
    return wire.Value(
      referenceValue: NativeFirestoreWrites(
        codec,
      ).resource(collectionGroup ? value : '$path/$value'),
    );
  }

  rpc.StructuredQuery_Filter _condition(List<dynamic> condition) {
    if (condition.length != 3 || condition[1] is! String) {
      throw NativeFirestoreCodec.invalid();
    }
    final field = rpc.StructuredQuery_FieldReference(
      fieldPath: NativeFirestoreCodec.fieldPath(condition[0]),
    );
    final operator = condition[1] as String;
    final value = condition[2];
    final isName = field.fieldPath == '__name__';
    if (!isName &&
        (operator == '==' || operator == '!=') &&
        (value == null || value is double && value.isNaN)) {
      return rpc.StructuredQuery_Filter(
        unaryFilter: rpc.StructuredQuery_UnaryFilter(
          field_2: field,
          op: value == null
              ? (operator == '=='
                    ? rpc.StructuredQuery_UnaryFilter_Operator.IS_NULL
                    : rpc.StructuredQuery_UnaryFilter_Operator.IS_NOT_NULL)
              : (operator == '=='
                    ? rpc.StructuredQuery_UnaryFilter_Operator.IS_NAN
                    : rpc.StructuredQuery_UnaryFilter_Operator.IS_NOT_NAN),
        ),
      );
    }
    final rpc.StructuredQuery_FieldFilter_Operator operation =
        switch (operator) {
          '==' => rpc.StructuredQuery_FieldFilter_Operator.EQUAL,
          '!=' => rpc.StructuredQuery_FieldFilter_Operator.NOT_EQUAL,
          '<' => rpc.StructuredQuery_FieldFilter_Operator.LESS_THAN,
          '<=' => rpc.StructuredQuery_FieldFilter_Operator.LESS_THAN_OR_EQUAL,
          '>' => rpc.StructuredQuery_FieldFilter_Operator.GREATER_THAN,
          '>=' =>
            rpc.StructuredQuery_FieldFilter_Operator.GREATER_THAN_OR_EQUAL,
          'in' => rpc.StructuredQuery_FieldFilter_Operator.IN,
          'not-in' => rpc.StructuredQuery_FieldFilter_Operator.NOT_IN,
          'array-contains' =>
            rpc.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS,
          'array-contains-any' =>
            rpc.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS_ANY,
          _ => throw NativeFirestoreCodec.invalid(),
        };
    wire.Value encoded;
    if (const {'in', 'not-in', 'array-contains-any'}.contains(operator)) {
      if (value is! List || value.isEmpty) throw NativeFirestoreCodec.invalid();
      encoded = wire.Value(
        arrayValue: wire.ArrayValue(
          values: value.map(
            (item) => isName
                ? _nameValue(item)
                : codec.encode(item, inArray: operator == 'array-contains-any'),
          ),
        ),
      );
    } else {
      encoded = isName
          ? _nameValue(value)
          : codec.encode(value, inArray: operator == 'array-contains');
    }
    return rpc.StructuredQuery_Filter(
      fieldFilter: rpc.StructuredQuery_FieldFilter(
        field_1: field,
        op: operation,
        value: encoded,
      ),
    );
  }

  rpc.Cursor? _cursor(
    String inclusive,
    String exclusive,
    bool start,
    List<NativeQueryOrder> order,
  ) {
    final inclusiveValues = parameters[inclusive],
        exclusiveValues = parameters[exclusive];
    if (inclusiveValues != null && exclusiveValues != null) {
      throw NativeFirestoreCodec.invalid();
    }
    final raw = inclusiveValues ?? exclusiveValues;
    if (raw == null) return null;
    if (raw is! Iterable) throw NativeFirestoreCodec.invalid();
    final values = raw.toList();
    if (values.length > order.length) throw NativeFirestoreCodec.invalid();
    return rpc.Cursor(
      before: start ? inclusiveValues != null : exclusiveValues != null,
      values: Iterable<int>.generate(values.length).map(
        (index) => order[index].isName
            ? _nameValue(values[index])
            : codec.encode(values[index]),
      ),
    );
  }

  rpc.StructuredQuery build() {
    final order = orders;
    final reverse = parameters['limitToLast'] != null;
    final count = parameters['limitToLast'] ?? parameters['limit'];
    if (count != null && (count is! int || count < 1 || count > 2147483647)) {
      throw NativeFirestoreCodec.invalid();
    }
    final filters = conditions.map(_condition).toList();
    final start = _cursor('startAt', 'startAfter', true, order),
        end = _cursor('endAt', 'endBefore', false, order);
    rpc.Cursor? inverted(rpc.Cursor? cursor) => cursor == null
        ? null
        : (rpc.Cursor.fromBuffer(cursor.writeToBuffer())
            ..before = !cursor.before);
    return rpc.StructuredQuery(
      from: [
        rpc.StructuredQuery_CollectionSelector(
          collectionId: path.split('/').last,
          allDescendants: collectionGroup,
        ),
      ],
      where: filters.isEmpty
          ? null
          : filters.length == 1
          ? filters.single
          : rpc.StructuredQuery_Filter(
              compositeFilter: rpc.StructuredQuery_CompositeFilter(
                op: rpc.StructuredQuery_CompositeFilter_Operator.AND,
                filters: filters,
              ),
            ),
      orderBy: order.map(
        (entry) => rpc.StructuredQuery_Order(
          field_1: rpc.StructuredQuery_FieldReference(
            fieldPath: NativeFirestoreCodec.fieldPath(FieldPath(entry.field)),
          ),
          direction: entry.descending != reverse
              ? rpc.StructuredQuery_Direction.DESCENDING
              : rpc.StructuredQuery_Direction.ASCENDING,
        ),
      ),
      startAt: reverse ? inverted(end) : start,
      endAt: reverse ? inverted(start) : end,
      limit: count == null ? null : Int32Value(value: count),
    );
  }

  List<wire.Document> sorted(Iterable<wire.Document> documents) {
    final order = orders;
    return documents.toList()..sort((a, b) {
      for (final entry in order) {
        final left = NativeFirestoreOrdering.field(a, entry.field),
            right = NativeFirestoreOrdering.field(b, entry.field);
        if (left == null || right == null) {
          throw NativeFirestoreCodec.invalid('data-loss');
        }
        final difference = NativeFirestoreOrdering.compare(left, right);
        if (difference != 0) return entry.descending ? -difference : difference;
      }
      return 0;
    });
  }
}
