enum UserFacingCloudOperation {
  business,
  businessEncryption,
  collaboration,
  secureStorage,
  encryptionSetup,
  accountVerification,
  twoFactor,
  applePurchase,
  accountDeletion,
  storageProvisioning,
  storageTransfer,
  uploadMetadata,
}

String userFacingCloudErrorMessage({
  required UserFacingCloudOperation operation,
  String? code,
  int? httpStatus,
}) {
  final normalizedCode = _normalizedCloudCode(code, httpStatus: httpStatus);
  return switch (operation) {
    UserFacingCloudOperation.business => _businessMessage(normalizedCode),
    UserFacingCloudOperation.businessEncryption => _businessEncryptionMessage(
      normalizedCode,
    ),
    UserFacingCloudOperation.collaboration => _collaborationMessage(
      normalizedCode,
    ),
    UserFacingCloudOperation.secureStorage => _secureStorageMessage(
      normalizedCode,
    ),
    UserFacingCloudOperation.encryptionSetup => _encryptionSetupMessage(
      normalizedCode,
    ),
    UserFacingCloudOperation.accountVerification => _accountVerificationMessage(
      normalizedCode,
    ),
    UserFacingCloudOperation.twoFactor => _twoFactorMessage(normalizedCode),
    UserFacingCloudOperation.applePurchase => _applePurchaseMessage(
      normalizedCode,
    ),
    UserFacingCloudOperation.accountDeletion => _accountDeletionMessage(
      normalizedCode,
    ),
    UserFacingCloudOperation.storageProvisioning => _storageProvisioningMessage(
      normalizedCode,
    ),
    UserFacingCloudOperation.storageTransfer => _storageTransferMessage(
      normalizedCode,
    ),
    UserFacingCloudOperation.uploadMetadata => _uploadMetadataMessage(
      normalizedCode,
    ),
  };
}

String _collaborationMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your session expired. Sign in again before updating the encrypted discussion.',
  'permission-denied' =>
    'Your access to this encrypted discussion changed. Refresh the file or ask an administrator to review access.',
  'invalid-argument' =>
    'The encrypted discussion update could not be accepted. Refresh the file and try again.',
  'not-found' =>
    'This file or discussion no longer exists. Refresh the workspace.',
  'failed-precondition' =>
    'This encrypted discussion needs another access or encryption safety step. Refresh the file and follow the on-screen guidance.',
  'already-exists' || 'aborted' =>
    'The encrypted discussion changed on another device. Refresh before trying again.',
  'resource-exhausted' =>
    'The encrypted discussion is temporarily busy or reached a limit. Wait briefly and retry.',
  'deadline-exceeded' || 'unavailable' =>
    'The encrypted discussion is temporarily unavailable. Check your connection and retry.',
  _ =>
    'The encrypted discussion could not be updated. Refresh the file and try again.',
};

String _normalizedCloudCode(String? value, {int? httpStatus}) {
  final initial = value
      ?.trim()
      .toLowerCase()
      .replaceAll('_', '-')
      .replaceAll(' ', '-');
  if (initial != null && initial.isNotEmpty) {
    var normalized = initial;
    for (final prefix in const <String>['firebase-functions/', 'functions/']) {
      if (normalized.startsWith(prefix)) {
        normalized = normalized.substring(prefix.length);
        break;
      }
    }
    return normalized;
  }
  return switch (httpStatus) {
    400 => 'invalid-argument',
    401 => 'unauthenticated',
    403 => 'permission-denied',
    404 => 'not-found',
    409 => 'aborted',
    412 => 'failed-precondition',
    429 => 'resource-exhausted',
    500 => 'internal',
    502 || 503 || 504 => 'unavailable',
    _ => 'unknown',
  };
}

String _businessMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your session expired. Sign in again to continue with the Business workspace.',
  'permission-denied' =>
    'Your Business access changed. Refresh the workspace or ask a company administrator to review it.',
  'invalid-argument' =>
    'The Business request could not be accepted. Review the form and try again.',
  'not-found' =>
    'That Business item no longer exists. Refresh the workspace before continuing.',
  'failed-precondition' =>
    'This Business change is not ready yet. Refresh the workspace and review the required safety step.',
  'already-exists' || 'aborted' =>
    'Business data changed on another device. Refresh before trying again.',
  'resource-exhausted' =>
    'The Business service is temporarily busy or reached a limit. Wait briefly and retry.',
  'deadline-exceeded' || 'unavailable' =>
    'The Business service is temporarily unavailable. Check your connection and retry.',
  _ => 'The Business request could not be completed. Refresh and try again.',
};

String _uploadMetadataMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your session expired. Sign in again before finishing this encrypted upload.',
  'permission-denied' =>
    'This account is not allowed to finish the encrypted upload. Refresh access and retry.',
  'invalid-argument' =>
    'The saved encrypted-upload details are no longer compatible. Update the app and retry from Data safety.',
  'not-found' =>
    'The encrypted upload could not be matched to its storage record. Retry from Data safety.',
  'failed-precondition' =>
    'The encrypted upload is waiting for an account or storage safety check. Refresh and retry.',
  'already-exists' || 'aborted' =>
    'This upload changed on another device. Refresh the workspace before retrying.',
  'resource-exhausted' =>
    'This upload cannot be finished because the storage limit was reached.',
  'deadline-exceeded' || 'unavailable' =>
    'The encrypted file is safe, but its workspace entry is still waiting. Check your connection and retry from Data safety.',
  _ =>
    'The encrypted file is safe, but its workspace entry could not be finished. Retry from Data safety.',
};

String _businessEncryptionMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your session expired. Sign in again before preparing Business encryption.',
  'permission-denied' =>
    'Your Business encryption access changed. Refresh the workspace or ask a company administrator to review it.',
  'invalid-argument' =>
    'The Business encryption request is no longer compatible. Update the app and try again.',
  'not-found' =>
    'The protected Business item no longer exists. Refresh the workspace before continuing.',
  'failed-precondition' =>
    'Business encryption needs another safety step. Refresh the workspace and follow the on-screen guidance.',
  'already-exists' || 'aborted' =>
    'Business encryption changed on another device. Refresh before trying again.',
  'resource-exhausted' =>
    'Business encryption is temporarily busy. Wait briefly and retry.',
  'deadline-exceeded' || 'unavailable' =>
    'Business encryption is temporarily unavailable. Check your connection and retry.',
  _ =>
    'Business encryption could not be prepared. Check your connection and try again.',
};

String _secureStorageMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your session expired. Sign in again before changing secure storage.',
  'permission-denied' =>
    'This account is not allowed to make that secure-storage change. Refresh access and retry.',
  'invalid-argument' =>
    'The secure-storage request could not be accepted. Update the app and retry.',
  'not-found' =>
    'That secure-storage item no longer exists. Refresh the workspace.',
  'failed-precondition' =>
    'This secure-storage change is waiting for another safety check. Refresh and retry.',
  'already-exists' || 'aborted' =>
    'Secure storage changed on another device. Refresh before trying again.',
  'resource-exhausted' =>
    'Secure storage is temporarily busy or reached a limit. Wait briefly and retry.',
  'deadline-exceeded' || 'unavailable' =>
    'Secure storage is temporarily unavailable. Check your connection and retry.',
  _ => 'The secure-storage operation could not be completed. Try again.',
};

String _encryptionSetupMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your session expired. Sign in again before setting up encryption.',
  'permission-denied' =>
    'This account cannot finish encryption setup yet. Refresh your session and retry.',
  'invalid-argument' =>
    'The encryption setup request is no longer compatible. Update the app and retry.',
  'failed-precondition' || 'aborted' =>
    'Encryption setup changed on another device. Refresh before trying again.',
  'resource-exhausted' =>
    'Encryption setup is temporarily busy. Wait briefly and retry.',
  'deadline-exceeded' || 'unavailable' =>
    'Encryption setup is temporarily unavailable. Check your connection and retry.',
  _ => 'Unable to set up encryption for this account. Try again.',
};

String _accountVerificationMessage(String code) => switch (code) {
  'wrong-password' ||
  'invalid-credential' ||
  'invalid-login-credentials' => 'Password did not match this account.',
  'too-many-requests' || 'resource-exhausted' =>
    'Too many password checks were attempted. Wait briefly and try again.',
  'user-disabled' =>
    'This account is disabled. Contact support before unlocking encryption.',
  'user-not-found' || 'no-current-user' || 'unauthenticated' =>
    'Your sign-in session is no longer available. Sign in again and retry.',
  'network-request-failed' || 'deadline-exceeded' || 'unavailable' =>
    'Password verification is temporarily unavailable. Check your connection and retry.',
  _ => 'Could not verify the current account. Sign in again and retry.',
};

String _twoFactorMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your session expired. Sign in again to complete the security check.',
  'permission-denied' =>
    'The security check was not accepted. Refresh your session and try again.',
  'invalid-argument' =>
    'That verification code is invalid. Check the current code and try again.',
  'failed-precondition' || 'aborted' =>
    'Two-factor settings changed on another device. Refresh before trying again.',
  'resource-exhausted' =>
    'Too many security-check attempts were made. Wait briefly and try again.',
  'deadline-exceeded' || 'unavailable' =>
    'The security verification service is temporarily unavailable. Check your connection and retry.',
  _ => 'Unable to complete the security check. Try again.',
};

String _applePurchaseMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your session expired. Sign in again before using App Store subscriptions.',
  'permission-denied' =>
    'This App Store transaction cannot be linked to this RonikCloud account.',
  'invalid-argument' =>
    'The App Store transaction could not be verified. Refresh purchases and try again.',
  'not-found' =>
    'The App Store subscription could not be found. Refresh purchases and try again.',
  'failed-precondition' =>
    'The App Store transaction needs another account or purchase safety check.',
  'already-exists' || 'aborted' =>
    'The App Store subscription changed on another device. Refresh purchases.',
  'resource-exhausted' =>
    'App Store verification is temporarily busy. Wait briefly and retry.',
  'deadline-exceeded' || 'unavailable' =>
    'App Store verification is temporarily unavailable. Check your connection and retry.',
  _ => 'The App Store purchase could not be completed. Try again.',
};

String _accountDeletionMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your session expired before account deletion. Sign in again; your account remains available.',
  'permission-denied' =>
    'This account cannot be deleted from the current session. Refresh access and try again.',
  'invalid-argument' =>
    'The account-deletion request is no longer compatible. Update the app and retry.',
  'failed-precondition' =>
    'Account deletion is waiting for a required safety step. Re-authenticate, resolve any company-owner responsibility, and retry shortly.',
  'resource-exhausted' =>
    'Account deletion is temporarily busy. Wait briefly and retry.',
  'deadline-exceeded' || 'unavailable' =>
    'The account-deletion service is temporarily unavailable. Your sign-in remains available so you can retry.',
  _ =>
    'Account deletion stopped before sign-in removal. Your account remains available so you can retry safely.',
};

String _storageProvisioningMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your session expired while preparing secure storage. Sign in again.',
  'permission-denied' =>
    'Secure-storage access changed. Refresh your account access and retry.',
  'invalid-argument' =>
    'The secure-storage setup request is no longer compatible. Update the app and retry.',
  'failed-precondition' =>
    'Secure storage is not ready for this account yet. Refresh the subscription and retry.',
  'resource-exhausted' =>
    'Secure-storage setup is temporarily busy. Wait briefly and retry.',
  'deadline-exceeded' || 'unavailable' =>
    'Secure-storage setup is temporarily unavailable. Check your connection and retry.',
  _ => 'Secure storage could not be prepared. Wait briefly and retry.',
};

String _storageTransferMessage(String code) => switch (code) {
  'unauthenticated' =>
    'Your session expired during the secure-storage request. Sign in again and retry.',
  'permission-denied' =>
    'This account is not allowed to access that encrypted storage object. Refresh access and retry.',
  'invalid-argument' =>
    'The secure-storage request could not be accepted. Update the app and retry.',
  'not-found' =>
    'The encrypted storage object could not be found. Refresh the workspace.',
  'failed-precondition' || 'aborted' =>
    'Secure storage changed while this request was running. Refresh and retry.',
  'resource-exhausted' =>
    'The secure-storage limit was reached or the service is temporarily busy.',
  'deadline-exceeded' || 'unavailable' =>
    'Secure storage is temporarily unavailable. Check your connection and retry.',
  _ => 'The secure-storage request could not be completed. Try again.',
};
