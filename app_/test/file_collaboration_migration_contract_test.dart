import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy collaboration migration is protected and exactly retryable', () {
    final pageSource = File(
      'lib/src/home/file_collaboration_page.dart',
    ).readAsStringSync();
    final serviceSource = File(
      'lib/src/storage/secure_drive_service.dart',
    ).readAsStringSync();

    expect(pageSource, contains('normalizeLegacyComment('));
    expect(pageSource, contains('normalizeLegacyReview('));
    expect(pageSource, contains('_legacyPendingPayloads[commentId]'));
    expect(pageSource, contains('_legacyReviewPendingPayload'));
    expect(pageSource, contains('migrationOnly: true'));
    expect(pageSource, contains('legacyFingerprint: legacyFingerprint'));
    expect(pageSource, contains("const Text('Retry protection')"));
    expect(pageSource, contains('fileCollaborationCacheFingerprint('));
    expect(pageSource, isNot(contains("].join('|')")));

    expect(serviceSource, contains("if (migrationOnly) 'migrationOnly': true"));
    expect(serviceSource, contains("if (migrationOnly) 'legacyFingerprint':"));
    expect(serviceSource, contains("r'^[a-f0-9]{64}\$'"));
  });
}
