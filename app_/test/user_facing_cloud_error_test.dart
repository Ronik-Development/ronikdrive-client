import 'package:cloud_storage/src/shared/user_facing_cloud_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Business errors use a fixed user-facing vocabulary', () {
    expect(
      userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.business,
        code: 'PERMISSION_DENIED',
      ),
      contains('Business access changed'),
    );
    final unknown = userFacingCloudErrorMessage(
      operation: UserFacingCloudOperation.business,
      code: 'host=private.example file=payroll.xlsx token=secret',
    );
    expect(
      unknown,
      'The Business request could not be completed. Refresh and try again.',
    );
    expect(unknown, isNot(contains('private.example')));
    expect(unknown, isNot(contains('payroll.xlsx')));
    expect(unknown, isNot(contains('secret')));
  });

  test('upload errors explain recovery without copying server details', () {
    expect(
      userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.uploadMetadata,
        httpStatus: 503,
      ),
      contains('encrypted file is safe'),
    );
    final unknown = userFacingCloudErrorMessage(
      operation: UserFacingCloudOperation.uploadMetadata,
      code: 'object-key=users/private/report.pdf',
    );
    expect(unknown, contains('Retry from Data safety'));
    expect(unknown, isNot(contains('users/private')));
    expect(unknown, isNot(contains('report.pdf')));
  });

  test('security and purchase boundaries never copy provider details', () {
    for (final operation in <UserFacingCloudOperation>[
      UserFacingCloudOperation.businessEncryption,
      UserFacingCloudOperation.collaboration,
      UserFacingCloudOperation.secureStorage,
      UserFacingCloudOperation.encryptionSetup,
      UserFacingCloudOperation.accountVerification,
      UserFacingCloudOperation.twoFactor,
      UserFacingCloudOperation.applePurchase,
      UserFacingCloudOperation.accountDeletion,
      UserFacingCloudOperation.storageProvisioning,
      UserFacingCloudOperation.storageTransfer,
    ]) {
      final message = userFacingCloudErrorMessage(
        operation: operation,
        code:
            'host=private.example object=users/private/photo.jpg token=secret',
      );
      expect(message, isNotEmpty);
      expect(message, isNot(contains('private.example')));
      expect(message, isNot(contains('photo.jpg')));
      expect(message, isNot(contains('secret')));
    }
  });

  test('two-factor and encryption setup preserve safe recovery guidance', () {
    expect(
      userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.twoFactor,
        code: 'functions/INVALID_ARGUMENT',
      ),
      contains('verification code is invalid'),
    );
    expect(
      userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.encryptionSetup,
        httpStatus: 503,
      ),
      contains('temporarily unavailable'),
    );
  });

  test('account verification maps provider failures without provider text', () {
    expect(
      userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.accountVerification,
        code: 'INVALID_LOGIN_CREDENTIALS',
      ),
      'Password did not match this account.',
    );
    final unknown = userFacingCloudErrorMessage(
      operation: UserFacingCloudOperation.accountVerification,
      code: 'host=private.example token=secret account=user@example.test',
    );
    expect(unknown, contains('current account'));
    expect(unknown, isNot(contains('private.example')));
    expect(unknown, isNot(contains('secret')));
    expect(unknown, isNot(contains('user@example.test')));
  });

  test('deletion and storage failures explain safe recovery', () {
    expect(
      userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.accountDeletion,
        code: 'UNAVAILABLE',
      ),
      allOf(contains('temporarily unavailable'), contains('remains available')),
    );
    expect(
      userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.storageTransfer,
        httpStatus: 403,
      ),
      contains('not allowed'),
    );
  });

  test('collaboration errors provide fixed refresh guidance', () {
    expect(
      userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.collaboration,
        code: 'PERMISSION_DENIED',
      ),
      allOf(contains('access'), contains('administrator')),
    );
    final unknown = userFacingCloudErrorMessage(
      operation: UserFacingCloudOperation.collaboration,
      code: r'host=private.example path=C:\Users\person\photo.jpg token=secret',
    );
    expect(unknown, contains('Refresh the file'));
    expect(unknown, isNot(contains('private.example')));
    expect(unknown, isNot(contains(r'C:\Users')));
    expect(unknown, isNot(contains('photo.jpg')));
    expect(unknown, isNot(contains('secret')));
  });
}
