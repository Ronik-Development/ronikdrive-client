import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owner request actions remove exact lifecycle timestamps', () {
    final serviceSource = File(
      'lib/src/storage/secure_drive_service.dart',
    ).readAsStringSync();
    final revokeStart = serviceSource.indexOf('Future<void> revokeFileRequest');
    final watchStart = serviceSource.indexOf(
      'Stream<QuerySnapshot<Map<String, dynamic>>> watchFileRequests',
    );
    final revokeSource = serviceSource.substring(revokeStart, watchStart);

    expect(revokeStart, greaterThanOrEqualTo(0));
    expect(watchStart, greaterThan(revokeStart));
    for (final field in <String>[
      'createdAt',
      'revokedAt',
      'updatedAt',
      'lastUploadAt',
    ]) {
      expect(revokeSource, contains("'$field': FieldValue.delete()"));
    }
    expect(revokeSource, isNot(contains('serverTimestamp')));
  });

  test('owner lists do not require exact creation timestamps', () {
    final serviceSource = File(
      'lib/src/storage/secure_drive_service.dart',
    ).readAsStringSync();
    final requestWatchStart = serviceSource.indexOf('watchFileRequests');
    final commentsStart = serviceSource.indexOf(
      'Stream<QuerySnapshot<Map<String, dynamic>>> watchComments',
    );
    final requestWatchSource = serviceSource.substring(
      requestWatchStart,
      commentsStart,
    );

    expect(requestWatchSource, contains("where('uid', isEqualTo: uid)"));
    expect(requestWatchSource, isNot(contains("orderBy('createdAt'")));

  });

  test('requested upload acceptance deletes legacy timing detail', () {
    final workspaceSource = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();
    final downloadStart = workspaceSource.indexOf(
      'Future<void> _downloadRequestedUpload',
    );
    final nextMethod = workspaceSource.indexOf(
      'Future<String?> _resolveShareSourceLabel',
    );
    final downloadSource = workspaceSource.substring(downloadStart, nextMethod);

    expect(downloadSource, contains("'status': 'accepted'"));
    expect(downloadSource, contains("'createdAt': FieldValue.delete()"));
    expect(downloadSource, contains("'updatedAt': FieldValue.delete()"));
    expect(downloadSource, isNot(contains('serverTimestamp')));
  });

  test('request UX sorts by state and coarse expiry', () {
    final source = File(
      'lib/src/home/data_safety_center_page.dart',
    ).readAsStringSync();

    expect(source, contains('_compareRequestedUploadsForOwner'));
    expect(source, contains('_compareFileRequestsForOwner'));
    expect(source, contains('Expires around'));
    expect(source, contains("'pending' => 0"));
    expect(source, contains('if (leftClosed != rightClosed)'));
  });
}
