import 'package:flutter/foundation.dart';

@immutable
class StorageInventoryStatus {
  const StorageInventoryStatus({
    this.writeSuspended = false,
    this.status,
    this.complete = false,
    this.observedBytes,
    this.metadataUsageBytes,
  });

  factory StorageInventoryStatus.fromProfile(Map<String, dynamic>? profile) {
    final rawInventory = profile?['storageInventory'];
    final inventory = rawInventory is Map
        ? Map<String, dynamic>.from(rawInventory)
        : const <String, dynamic>{};
    final rawStatus = inventory['status'];
    final normalizedStatus = rawStatus is String
        ? rawStatus.trim().toLowerCase()
        : '';
    const knownStatuses = <String>{
      'healthy',
      'diverged',
      'partial',
      'over_capacity',
    };

    int? nonNegativeInteger(Object? value) {
      if (value is! num || !value.isFinite || value < 0) {
        return null;
      }
      return value.round();
    }

    return StorageInventoryStatus(
      writeSuspended: profile?['storageWriteSuspended'] == true,
      status: knownStatuses.contains(normalizedStatus)
          ? normalizedStatus
          : null,
      complete: inventory['complete'] == true,
      observedBytes: nonNegativeInteger(inventory['observedBytes']),
      metadataUsageBytes: nonNegativeInteger(inventory['metadataUsageBytes']),
    );
  }

  final bool writeSuspended;
  final String? status;
  final bool complete;
  final int? observedBytes;
  final int? metadataUsageBytes;

  bool get blocksWrites => writeSuspended;

  String get userMessage =>
      'Uploads are temporarily paused because verified storage usage exceeds '
      'the current plan. Existing files remain available. RonikCloud checks '
      'only aggregate encrypted-object counts and byte totals, never file '
      'contents or names.';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageInventoryStatus &&
          other.writeSuspended == writeSuspended &&
          other.status == status &&
          other.complete == complete &&
          other.observedBytes == observedBytes &&
          other.metadataUsageBytes == metadataUsageBytes;

  @override
  int get hashCode => Object.hash(
    writeSuspended,
    status,
    complete,
    observedBytes,
    metadataUsageBytes,
  );
}
