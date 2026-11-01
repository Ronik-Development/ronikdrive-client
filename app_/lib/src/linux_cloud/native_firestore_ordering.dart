import 'dart:convert';

import 'firestore_wire/google/firestore/v1/document.pb.dart' as wire;
import 'native_firestore_codec.dart';

/// Ordering for remote query views, including exact native 64-bit integers and
/// UTF-8/path ordering. Unrecognized pipeline-only values fail explicitly.
class NativeFirestoreOrdering {
  static int bytes(List<int> a, List<int> b) {
    final length = a.length < b.length ? a.length : b.length;
    for (var index = 0; index < length; index++) {
      final difference = a[index].compareTo(b[index]);
      if (difference != 0) return difference;
    }
    return a.length.compareTo(b.length);
  }

  static int text(String a, String b) => bytes(utf8.encode(a), utf8.encode(b));
  static int path(List<String> a, List<String> b) {
    final length = a.length < b.length ? a.length : b.length;
    for (var index = 0; index < length; index++) {
      final difference = text(a[index], b[index]);
      if (difference != 0) return difference;
    }
    return a.length.compareTo(b.length);
  }

  static int _rank(wire.Value value) => switch (value.whichValueType()) {
    wire.Value_ValueType.nullValue => 0,
    wire.Value_ValueType.booleanValue => 1,
    wire.Value_ValueType.integerValue || wire.Value_ValueType.doubleValue => 2,
    wire.Value_ValueType.timestampValue => 3,
    wire.Value_ValueType.stringValue => 4,
    wire.Value_ValueType.bytesValue => 5,
    wire.Value_ValueType.referenceValue => 6,
    wire.Value_ValueType.geoPointValue => 7,
    wire.Value_ValueType.arrayValue => 8,
    wire.Value_ValueType.mapValue => 9,
    _ => throw NativeFirestoreCodec.invalid('data-loss'),
  };
  static int compare(wire.Value a, wire.Value b) {
    final rank = _rank(a);
    final typeDifference = rank.compareTo(_rank(b));
    if (typeDifference != 0) return typeDifference;
    switch (rank) {
      case 0:
        return 0;
      case 1:
        return (a.booleanValue ? 1 : 0).compareTo(b.booleanValue ? 1 : 0);
      case 2:
        final num left = a.hasIntegerValue()
            ? a.integerValue.toInt()
            : a.doubleValue;
        final num right = b.hasIntegerValue()
            ? b.integerValue.toInt()
            : b.doubleValue;
        if (left.isNaN) return right.isNaN ? 0 : -1;
        if (right.isNaN) return 1;
        if (left == right) return 0;
        return left.compareTo(right);
      case 3:
        final seconds = a.timestampValue.seconds.compareTo(
          b.timestampValue.seconds,
        );
        return seconds == 0
            ? a.timestampValue.nanos.compareTo(b.timestampValue.nanos)
            : seconds;
      case 4:
        return text(a.stringValue, b.stringValue);
      case 5:
        return bytes(a.bytesValue, b.bytesValue);
      case 6:
        return path(a.referenceValue.split('/'), b.referenceValue.split('/'));
      case 7:
        final latitude = a.geoPointValue.latitude.compareTo(
          b.geoPointValue.latitude,
        );
        return latitude == 0
            ? a.geoPointValue.longitude.compareTo(b.geoPointValue.longitude)
            : latitude;
      case 8:
        final left = a.arrayValue.values, right = b.arrayValue.values;
        final length = left.length < right.length ? left.length : right.length;
        for (var index = 0; index < length; index++) {
          final difference = compare(left[index], right[index]);
          if (difference != 0) return difference;
        }
        return left.length.compareTo(right.length);
      case 9:
        final left = a.mapValue.fields, right = b.mapValue.fields;
        final leftKeys = left.keys.toList()..sort(text),
            rightKeys = right.keys.toList()..sort(text);
        final length = leftKeys.length < rightKeys.length
            ? leftKeys.length
            : rightKeys.length;
        for (var index = 0; index < length; index++) {
          final keyDifference = text(leftKeys[index], rightKeys[index]);
          if (keyDifference != 0) return keyDifference;
          final difference = compare(
            left[leftKeys[index]]!,
            right[rightKeys[index]]!,
          );
          if (difference != 0) return difference;
        }
        return leftKeys.length.compareTo(rightKeys.length);
      default:
        throw NativeFirestoreCodec.invalid('data-loss');
    }
  }

  static wire.Value? field(wire.Document document, List<String> path) {
    if (path.length == 1 && path.single == '__name__') {
      return wire.Value(referenceValue: document.name);
    }
    var fields = document.fields;
    wire.Value? value;
    for (var index = 0; index < path.length; index++) {
      value = fields[path[index]];
      if (value == null) return null;
      if (index < path.length - 1) {
        if (!value.hasMapValue()) return null;
        fields = value.mapValue.fields;
      }
    }
    return value;
  }
}
