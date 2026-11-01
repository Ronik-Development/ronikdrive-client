import 'package:cloud_storage/src/home/recovery_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovery messages reject callable and document details', () {
    const secret =
        'permission denied for uid=user-private and file=secret-plan.pdf';

    for (final action in RecoveryFailureAction.values) {
      final message = recoveryFailureMessage(action, Exception(secret));
      expect(message, isNot(contains('user-private')));
      expect(message, isNot(contains('secret-plan.pdf')));
      expect(message, isNot(contains('permission denied')));
    }
  });
}
