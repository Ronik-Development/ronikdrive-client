import 'dart:async';

import 'package:cloud_storage/src/home/migration/migration_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migration messages never copy arbitrary provider details', () {
    const secret =
        'Bearer token-for-private@example.com /private/contracts/merger.pdf';

    for (final action in MigrationFailureAction.values) {
      final message = migrationFailureMessage(action, Exception(secret));
      expect(message, isNot(contains(secret)));
      expect(message, isNot(contains('private@example.com')));
      expect(message, isNot(contains('merger.pdf')));
    }
  });

  test('timeouts receive fixed connection guidance', () {
    final message = migrationFailureMessage(
      MigrationFailureAction.browse,
      TimeoutException('https://provider.example/private/path'),
    );

    expect(
      message,
      'The request timed out. Check your connection and try again.',
    );
    expect(message, isNot(contains('provider.example')));
  });
}
