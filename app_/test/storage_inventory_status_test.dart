import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/storage/storage_inventory_status.dart';

void main() {
  test('parses the aggregate suspension summary without identifiers', () {
    final status = StorageInventoryStatus.fromProfile(<String, dynamic>{
      'storageWriteSuspended': true,
      'storageInventory': <String, dynamic>{
        'status': 'over_capacity',
        'complete': true,
        'observedBytes': 1234,
        'metadataUsageBytes': 1200,
        'objectCount': 9,
      },
    });

    expect(status.blocksWrites, isTrue);
    expect(status.status, 'over_capacity');
    expect(status.complete, isTrue);
    expect(status.observedBytes, 1234);
    expect(status.metadataUsageBytes, 1200);
    expect(status.userMessage, isNot(contains('objectCount')));
    expect(status.userMessage, contains('never file contents or names'));
  });

  test('ignores malformed optional aggregate fields', () {
    final status = StorageInventoryStatus.fromProfile(<String, dynamic>{
      'storageWriteSuspended': false,
      'storageInventory': <String, dynamic>{
        'status': 'unknown',
        'complete': 'yes',
        'observedBytes': -1,
        'metadataUsageBytes': '1200',
      },
    });

    expect(status.blocksWrites, isFalse);
    expect(status.status, isNull);
    expect(status.complete, isFalse);
    expect(status.observedBytes, isNull);
    expect(status.metadataUsageBytes, isNull);
  });
}
