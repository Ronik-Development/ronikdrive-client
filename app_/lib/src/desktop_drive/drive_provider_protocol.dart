import 'dart:typed_data';

import 'drive_relative_path.dart';

const nativeDriveMaximumFileBytes = 64 * 1024 * 1024;

/// The native boundary never contains object-store keys or encryption keys.
class ProviderItem {
  ProviderItem({
    required this.id,
    required this.parentId,
    required this.name,
    required this.version,
    required this.directory,
    required this.size,
  }) {
    DriveRelativePath([name]);
    if (id.isEmpty || version.isEmpty || size < 0) {
      throw const ProviderFailure('invalid');
    }
  }
  final String id, parentId, name, version;
  final bool directory;
  final int size;

  Map<String, Object> toJson() => {
    'id': id,
    'parentId': parentId,
    'name': name,
    'version': version,
    'directory': directory,
    'size': size,
  };
}

class ProviderFailure implements Exception {
  const ProviderFailure(this.code);
  final String code;
  @override
  String toString() => 'Desktop drive operation failed.';
}

/// Implementations must recheck authorization AND version at completion.
/// Read returns authenticated contents, not intermediate decryption output.
abstract interface class DriveProviderBackend {
  void invalidate();
  Future<List<ProviderItem>> list(String parentId);
  Future<ProviderItem> item(String id);
  Future<Uint8List> read(String id, String version);
  Future<ProviderItem> create(
    String parentId,
    String name,
    bool directory,
    Uint8List contents,
  );
  Future<ProviderItem> update(
    String id,
    String version,
    String? parentId,
    String? name,
    Uint8List? contents,
  );
  Future<void> recycle(String id, String version);
}

/// Native callers retain the same request ID when replaying a create after
/// losing its response. Read-only adapters never invoke this interface.
abstract interface class RecoverableDriveCreates {
  Future<ProviderItem> createWithRequestId(
    String requestId,
    String parentId,
    String name,
    bool directory,
    Uint8List contents,
  );
}
