import 'package:cloud_storage/src/business/business_storage_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('company storage uses only a decrypted in-memory label', () {
    expect(businessCompanyStorageLabel('Northwind'), 'Northwind shared files');
    expect(businessCompanyStorageLabel(null), 'Company shared files');
    expect(
      businessCompanyStorageLabel('Protected company'),
      'Protected company files',
    );
    expect(
      businessCompanyStorageLabel('Encrypted company'),
      'Protected company files',
    );
  });

  test('unreadable groups use friendly ordinals instead of record IDs', () {
    expect(
      businessGroupStorageLabel('Design', protectedOrdinal: 1),
      'Design files',
    );
    expect(
      businessGroupStorageLabel(null, protectedOrdinal: 2),
      'Protected group 2 files',
    );
    expect(
      businessGroupStorageLabel('Encrypted group', protectedOrdinal: 3),
      'Protected group 3 files',
    );
  });
}
