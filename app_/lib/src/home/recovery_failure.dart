enum RecoveryFailureAction { rewind, restoreFile }

/// Recovery errors can originate in callable responses. Never surface their
/// arbitrary text because it can contain provider or document details.
String recoveryFailureMessage(
  RecoveryFailureAction action,
  Object error,
) => switch (action) {
  RecoveryFailureAction.rewind =>
    'Files could not be restored for that period. Check your connection and try Rewind again.',
  RecoveryFailureAction.restoreFile =>
    'This file could not be restored. Refresh Data safety and try again.',
};
