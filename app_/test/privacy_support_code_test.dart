import 'package:flutter_test/flutter_test.dart';

import 'package:cloud_storage/src/privacy/privacy_support_code.dart';

void main() {
  test('support code is stable, opaque, and human-readable', () {
    final code = privacySupportCodeForUid('firebase-user-123');
    expect(code, matches(RegExp(r'^[A-F0-9]{6}-[A-F0-9]{6}$')));
    expect(code, privacySupportCodeForUid('firebase-user-123'));
    expect(code, isNot(privacySupportCodeForUid('firebase-user-124')));
    expect(code.toLowerCase(), isNot(contains('firebase')));
  });

  test('empty account identifiers do not create a misleading code', () {
    expect(privacySupportCodeForUid('   '), 'UNKNOWN');
  });
}
