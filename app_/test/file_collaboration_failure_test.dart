import 'package:cloud_storage/src/security/file_collaboration_encryption.dart';
import 'package:cloud_storage/src/security/file_collaboration_failure.dart';
import 'package:cloud_storage/src/shared/user_facing_cloud_error.dart';
import 'package:cloud_storage/src/storage/secure_drive_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows only fixed collaboration cloud messages', () {
    final safeMessage = userFacingCloudErrorMessage(
      operation: UserFacingCloudOperation.collaboration,
      code: 'permission-denied',
    );
    expect(
      fileCollaborationFailureMessage(
        SecureDriveException(safeMessage),
        action: FileCollaborationAction.sendComment,
      ),
      safeMessage,
    );
  });

  test('rejects arbitrary SecureDriveException details', () {
    final message = fileCollaborationFailureMessage(
      const SecureDriveException(
        r'user@example.test C:\Users\person\photo.jpg token=secret',
      ),
      action: FileCollaborationAction.sendComment,
    );
    expect(
      message,
      'The encrypted comment could not be sent. Refresh file access and try again.',
    );
    expect(message, isNot(contains('user@example.test')));
    expect(message, isNot(contains(r'C:\Users')));
    expect(message, isNot(contains('photo.jpg')));
    expect(message, isNot(contains('secret')));
  });

  test('rejects unknown exception details for reviews', () {
    final message = fileCollaborationFailureMessage(
      Exception('provider payload with private-file-name.png'),
      action: FileCollaborationAction.updateReview,
    );
    expect(
      message,
      'The encrypted review could not be updated. Refresh file access and try again.',
    );
    expect(message, isNot(contains('private-file-name.png')));
  });

  test('preserves safe local validation guidance', () {
    expect(
      fileCollaborationFailureMessage(
        const SecureDriveException(
          'Comments must contain 1 to 4000 characters.',
        ),
        action: FileCollaborationAction.sendComment,
      ),
      'Comments must contain 1 to 4000 characters.',
    );
    expect(
      fileCollaborationFailureMessage(
        const FileCollaborationEncryptionException(
          'The protected mention list is invalid.',
        ),
        action: FileCollaborationAction.sendComment,
      ),
      'Check the @email mentions and try again.',
    );
  });

  test('turns encrypted payload limits into action-specific guidance', () {
    const error = FileCollaborationEncryptionException(
      'The protected collaboration payload is too large.',
    );
    expect(
      fileCollaborationFailureMessage(
        error,
        action: FileCollaborationAction.sendComment,
      ),
      'This comment is too large to encrypt. Shorten it and try again.',
    );
    expect(
      fileCollaborationFailureMessage(
        error,
        action: FileCollaborationAction.updateReview,
      ),
      'The review note is too large to encrypt. Shorten it and try again.',
    );
  });
}
