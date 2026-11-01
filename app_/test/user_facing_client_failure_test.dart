import 'dart:io';

import 'package:cloud_storage/src/security/encryption_recovery_kit.dart';
import 'package:cloud_storage/src/shared/user_facing_client_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'client failure messages are fixed and contain no technical details',
    () {
      for (final failure in UserFacingClientFailure.values) {
        final message = userFacingClientFailureMessage(failure);
        expect(message, isNotEmpty);
        expect(message, isNot(contains('Bearer ')));
        expect(message, isNot(contains('firebase')));
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains(r'C:\Users\')));
        expect(message, isNot(contains('https://')));
      }
    },
  );

  test('tester signup maps status only and never accepts response details', () {
    expect(
      testerSignupFailureMessage(httpStatus: 409),
      'This email is already registered for the selected updates.',
    );
    expect(
      testerSignupFailureMessage(httpStatus: 429),
      contains('Wait briefly'),
    );
    expect(
      testerSignupFailureMessage(httpStatus: 503),
      contains('temporarily unavailable'),
    );
  });

  test('security and checkout UI use closed failure boundaries', () {
    final authGate = File(
      'lib/src/authentication/auth_gate.dart',
    ).readAsStringSync();
    final twoFactorGate = File(
      'lib/src/authentication/two_factor_gate.dart',
    ).readAsStringSync();
    final securitySettings = File(
      'lib/src/settings/security_settings_page.dart',
    ).readAsStringSync();
    final checkout = File(
      'lib/src/billing/checkout_webview_page.dart',
    ).readAsStringSync();
    final testerAccess = File(
      'lib/src/home/tester_access_page.dart',
    ).readAsStringSync();

    expect(authGate, isNot(contains('snapshot.error.toString()')));
    expect(
      twoFactorGate,
      isNot(contains("'Unable to verify the code right now. \$error'")),
    );
    expect(
      twoFactorGate,
      isNot(
        contains(
          "'We could not confirm your account security requirements. \$error'",
        ),
      ),
    );
    expect(
      securitySettings,
      isNot(contains("Text('Failed to load settings: \$error')")),
    );
    expect(securitySettings, isNot(contains('_showMessage(error.message)')));
    expect(checkout, isNot(contains('error.description')));
    expect(checkout, isNot(contains('error.toString()')));
    expect(testerAccess, isNot(contains("decoded['detail']")));
  });

  test('recovery-kit exception string omits its supplied message', () {
    const privateDetail =
        'private@example.com C:\\Users\\alice\\contracts\\merger.pdf';
    const error = EncryptionRecoveryKitException(
      EncryptionRecoveryKitFailure.invalidFormat,
      privateDetail,
    );

    expect(error.toString(), contains('invalidFormat'));
    expect(error.toString(), isNot(contains(privateDetail)));
    expect(error.toString(), isNot(contains('private@example.com')));
  });
}
