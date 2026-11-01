import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Photo IDs never leave the device. Only the existing keyed backup-path tags
/// are uploaded; these opaque local keys live in the encrypted backup cache.
class IosPhotoAsset {
  IosPhotoAsset(Map<Object?, Object?> value)
    : id = value['id'] as String,
      modified = DateTime.fromMillisecondsSinceEpoch(
        value['modified'] as int,
        isUtc: true,
      );

  final String id;
  final DateTime modified;
  String get token => sha256.convert(utf8.encode(id)).toString();
  String get sourcePath => p.join(IosPhotoLibrary.sourcePath, token);
}

class IosPhotoExport {
  const IosPhotoExport(this.path, this.name);
  final String path;
  final String name;
}

class IosPhotoLibrary {
  static const sourcePath = 'ios-photo-library';
  static const _channel = MethodChannel('ronikcloud/photo-library');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<String> authorization({bool request = false}) async =>
      await _channel.invokeMethod<String>(request ? 'authorize' : 'status') ??
      'denied';

  static Future<void> manageAccess() => _channel.invokeMethod('manageAccess');

  static Future<List<IosPhotoExport>> pick() async {
    final values = await _channel.invokeListMethod<Object?>('pick') ?? [];
    return values
        .map((value) {
          final file = value as Map<Object?, Object?>;
          return IosPhotoExport(file['path'] as String, file['name'] as String);
        })
        .toList(growable: false);
  }

  /// Enumerate metadata in bounded pages; export only one pending asset at a time.
  static Stream<IosPhotoAsset> assets() async* {
    final status = await authorization();
    if (status != 'limited' && status != 'authorized') {
      throw PlatformException(code: 'photo_access');
    }
    var offset = 0;
    while (true) {
      final page = await _channel.invokeListMethod<Object?>('list', {
        'offset': offset,
        'limit': 100,
      });
      if (page == null || page.isEmpty) return;
      for (final value in page) {
        yield IosPhotoAsset(value as Map<Object?, Object?>);
      }
      offset += page.length;
      if (page.length < 100) return;
    }
  }

  static Future<IosPhotoExport> export(IosPhotoAsset asset) async {
    final value = await _channel.invokeMapMethod<String, Object?>('export', {
      'id': asset.id,
      'modified': asset.modified.millisecondsSinceEpoch,
    });
    if (value == null) throw PlatformException(code: 'photo_export');
    return IosPhotoExport(value['path'] as String, value['name'] as String);
  }

  static Future<void> release(IosPhotoExport file) =>
      _channel.invokeMethod('release', {'path': file.path});

  static String message(Object error) {
    if (error is PlatformException && error.code == 'photo_access') {
      return 'Allow Photos access in iOS Settings, then try again. '
          'Limited access backs up only the photos you allow.';
    }
    return 'Photo backup could not finish. Check your connection and available '
        'device storage, then retry. Photos stored in iCloud must download first.';
  }
}
