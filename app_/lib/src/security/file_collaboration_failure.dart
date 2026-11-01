import '../shared/user_facing_cloud_error.dart';
import '../storage/secure_drive_service.dart';
import 'file_collaboration_encryption.dart';

enum FileCollaborationAction { sendComment, updateReview }

const String _commentFallback =
    'The encrypted comment could not be sent. Refresh file access and try again.';
const String _reviewFallback =
    'The encrypted review could not be updated. Refresh file access and try again.';

final Set<String> _safeCloudMessages = <String>{
  for (final code in const <String>[
    'unauthenticated',
    'permission-denied',
    'invalid-argument',
    'not-found',
    'failed-precondition',
    'already-exists',
    'aborted',
    'resource-exhausted',
    'deadline-exceeded',
    'unavailable',
    'unknown',
  ])
    userFacingCloudErrorMessage(
      operation: UserFacingCloudOperation.collaboration,
      code: code,
    ),
};

String fileCollaborationFailureMessage(
  Object error, {
  required FileCollaborationAction action,
}) {
  final fallback = switch (action) {
    FileCollaborationAction.sendComment => _commentFallback,
    FileCollaborationAction.updateReview => _reviewFallback,
  };

  if (error is SecureDriveException) {
    if (error.message == 'Comments must contain 1 to 4000 characters.' ||
        _safeCloudMessages.contains(error.message)) {
      return error.message;
    }
    return fallback;
  }

  if (error is FileCollaborationEncryptionException) {
    return switch (error.message) {
      'Comments must contain 1 to 4000 characters.' => error.message,
      'Review notes can use at most 1000 characters.' => error.message,
      'A comment can mention at most 25 people.' => error.message,
      'The protected mention list is invalid.' =>
        'Check the @email mentions and try again.',
      'The protected collaboration payload is too large.' =>
        action == FileCollaborationAction.sendComment
            ? 'This comment is too large to encrypt. Shorten it and try again.'
            : 'The review note is too large to encrypt. Shorten it and try again.',
      _ => fallback,
    };
  }

  return fallback;
}
