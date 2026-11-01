import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FolderAccessException implements Exception {
  const FolderAccessException();
  String get message =>
      'Folder access needs to be renewed. Choose the folder again to resume its backup.';
}

class PersistentFolderSelection {
  const PersistentFolderSelection({required this.path, required this.bookmark});
  final String path;
  final String bookmark;
}

class FolderAccessLease {
  FolderAccessLease._(this._id);
  final String? _id;
  Future<void>? _closing;
  Future<void> close() => _closing ??= _release();
  Future<void> _release() async {
    if (_id != null) {
      try {
        await PersistentFolderAccess._channel.invokeMethod<void>(
          'release',
          _id,
        );
      } on MissingPluginException {
        // Engine teardown releases the native plugin and all its scopes.
      } on PlatformException {
        // Closing a scope must not mask a failed upload or escape dispose.
        // The native plugin also releases every retained scope on teardown.
      }
    }
  }
}

/// Retain a native grant for the complete scan/read operation, including on
/// headless engines. Its bookmark is stored only in encrypted account config.
class PersistentFolderAccess {
  static const _channel = MethodChannel('ronikcloud/folder-access');
  static bool get requiresBookmark =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<PersistentFolderSelection?> pick() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>('pick');
      if (value == null) return null;
      final path = value['path'];
      final bookmark = value['bookmark'];
      if (path is! String ||
          !path.startsWith('/') ||
          path.contains('\u0000') ||
          bookmark is! String ||
          bookmark.isEmpty ||
          bookmark.length > 90000) {
        throw const FolderAccessException();
      }
      return PersistentFolderSelection(path: path, bookmark: bookmark);
    } on PlatformException {
      throw const FolderAccessException();
    } on MissingPluginException {
      throw const FolderAccessException();
    }
  }

  static Future<FolderAccessLease> acquire({
    required String path,
    String? bookmark,
  }) async {
    if (!requiresBookmark) return FolderAccessLease._(null);
    if (!path.startsWith('/') ||
        path.contains('\u0000') ||
        bookmark == null ||
        bookmark.isEmpty ||
        bookmark.length > 90000) {
      throw const FolderAccessException();
    }
    try {
      final id = await _channel.invokeMethod<String>('acquire', {
        'path': path,
        'bookmark': bookmark,
      });
      if (id == null || id.isEmpty) throw const FolderAccessException();
      return FolderAccessLease._(id);
    } on PlatformException {
      throw const FolderAccessException();
    } on MissingPluginException {
      throw const FolderAccessException();
    }
  }

  static Future<T> withAccess<T>({
    required String path,
    String? bookmark,
    required Future<T> Function() action,
  }) async {
    final lease = await acquire(path: path, bookmark: bookmark);
    try {
      return await action();
    } finally {
      await lease.close();
    }
  }
}
