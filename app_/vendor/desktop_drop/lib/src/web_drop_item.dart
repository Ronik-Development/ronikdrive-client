import 'dart:typed_data';

import 'package:desktop_drop/src/drop_item.dart';

class WebDropItem {
  WebDropItem({
    required this.uri,
    required this.children,
    this.data,
    required this.name,
    required this.type,
    required this.size,
    required this.relativePath,
    required this.lastModified,
  });

  final String uri;
  final List<WebDropItem> children;
  final Uint8List? data;
  final String name;
  final String type;
  final int size;
  final String? relativePath;
  final DateTime lastModified;

  static int _parseWebInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double && value.isFinite) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory WebDropItem.fromJson(Map<String, dynamic> json) => WebDropItem(
        uri: json['uri'],
        children: json['children'] == null
            ? []
            : (json['children'] as List)
                .cast<Map>()
                .map((e) => WebDropItem.fromJson(e.cast<String, dynamic>()))
                .toList(),
        data: json['data'] != null ? Uint8List.fromList(json['data']) : null,
        name: json['name'],
        type: json['type'],
        size: _parseWebInt(json['size']),
        relativePath: json['relativePath'],
        lastModified: DateTime.fromMillisecondsSinceEpoch(
          _parseWebInt(json['lastModified']),
        ),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uri': uri,
        'children': children.map((e) => e.toJson()).toList(),
        'data': data?.toList(),
        'name': name,
        'type': type,
        'size': size.toString(),
        'relativePath': relativePath,
        'lastModified': lastModified.millisecondsSinceEpoch.toString(),
      };

  DropItem toDropItem() {
    if (type == 'directory') {
      return DropItemDirectory(
        uri,
        children.map((e) => e.toDropItem()).toList(),
        name: name,
        mimeType: type,
        length: size,
        lastModified: lastModified,
        bytes: data,
      );
    } else {
      if (data != null) {
        return DropItemFile.fromData(
          data!,
          name: name,
          mimeType: type,
          length: size,
          lastModified: lastModified,
          path: uri,
        );
      }
      return DropItemFile(
        uri,
        name: name,
        mimeType: type,
        length: size,
        lastModified: lastModified,
        bytes: data,
      );
    }
  }
}
