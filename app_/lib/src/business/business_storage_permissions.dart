import 'package:flutter/foundation.dart';

/// The device-side projection of server-authoritative Business storage
/// permissions.
///
/// Missing or malformed fields fail closed. The backend still rechecks the
/// current membership and permission document for every protected operation;
/// this projection exists to remove stale local data and unavailable controls
/// as soon as the authenticated user-profile mirror changes.
@immutable
class BusinessStoragePermissions {
  const BusinessStoragePermissions({
    this.canUpload = false,
    this.canDownload = false,
    this.canShare = false,
  });

  factory BusinessStoragePermissions.fromMap(Map<String, Object?> value) {
    return BusinessStoragePermissions(
      canUpload: value['uploadFiles'] == true,
      canDownload: value['downloadFiles'] == true,
      canShare: value['shareFiles'] == true,
    );
  }

  final bool canUpload;
  final bool canDownload;
  final bool canShare;

  bool get canUseStorage => canUpload || canDownload;

  @override
  bool operator ==(Object other) {
    return other is BusinessStoragePermissions &&
        other.canUpload == canUpload &&
        other.canDownload == canDownload &&
        other.canShare == canShare;
  }

  @override
  int get hashCode => Object.hash(canUpload, canDownload, canShare);
}
