/// Fixed, privacy-safe messages for failures that originate on the client.
///
/// Callers deliberately pass only a closed failure kind (or an HTTP status
/// where explicitly supported). Exception text, provider response bodies,
/// file paths, account identifiers, and endpoint details must never cross
/// this boundary into user-visible UI.
enum UserFacingClientFailure {
  authConnection,
  securitySettingsLoad,
  biometricPreferenceUpdate,
  twoFactorDisable,
  twoFactorEnable,
  twoFactorStatus,
  twoFactorVerification,
  recoveryKitCreate,
  recoveryKitRestore,
  recoveryKitInvalid,
  recoveryKitAuthentication,
  recoveryKitAccountMismatch,
  recoveryKitEnvironmentMismatch,
  recoveryKitEncryptionMismatch,
  subscriptionStatus,
  subscriptionManagement,
  profileProvisioning,
  checkoutStart,
  appStoreLoad,
  appStorePurchase,
  appStoreVerification,
  supportReport,
  checkoutLoad,
  uploadProtection,
}

String userFacingClientFailureMessage(
  UserFacingClientFailure failure,
) => switch (failure) {
  UserFacingClientFailure.authConnection =>
    'RonikCloud could not confirm the signed-in session. Check your connection and try again.',
  UserFacingClientFailure.securitySettingsLoad =>
    'Account security settings could not be refreshed. Check your connection and try again.',
  UserFacingClientFailure.biometricPreferenceUpdate =>
    'The sign-in preference could not be updated on this device. Try again.',
  UserFacingClientFailure.twoFactorDisable =>
    'Two-factor authentication could not be disabled. Check the current code and your connection, then retry.',
  UserFacingClientFailure.twoFactorEnable =>
    'Two-factor authentication could not be enabled. Check the current code and your connection, then retry.',
  UserFacingClientFailure.twoFactorStatus =>
    'RonikCloud could not confirm the account security check. Refresh your session and try again.',
  UserFacingClientFailure.twoFactorVerification =>
    'The security code could not be verified. Check the current code and your connection, then retry.',
  UserFacingClientFailure.recoveryKitCreate =>
    'The recovery kit could not be created safely. Unlock the encrypted workspace and try again.',
  UserFacingClientFailure.recoveryKitRestore =>
    'Encryption access could not be restored from this kit. Check the kit and passphrase, then retry.',
  UserFacingClientFailure.recoveryKitInvalid =>
    'This recovery kit is invalid or is not a supported RonikCloud kit.',
  UserFacingClientFailure.recoveryKitAuthentication =>
    'The recovery passphrase was not accepted or the kit is damaged.',
  UserFacingClientFailure.recoveryKitAccountMismatch =>
    'This recovery kit belongs to a different account.',
  UserFacingClientFailure.recoveryKitEnvironmentMismatch =>
    'This recovery kit belongs to a different RonikCloud environment.',
  UserFacingClientFailure.recoveryKitEncryptionMismatch =>
    'This recovery kit does not match the account encryption setup.',
  UserFacingClientFailure.subscriptionStatus =>
    'RonikCloud could not confirm the subscription status. Check your connection and retry without leaving this account.',
  UserFacingClientFailure.subscriptionManagement =>
    'The subscription change could not be completed. Your current access is unchanged; check your connection and try again.',
  UserFacingClientFailure.profileProvisioning =>
    'The encrypted workspace profile could not be prepared. Check your connection and retry.',
  UserFacingClientFailure.checkoutStart =>
    'Secure checkout could not be started. Check your connection and try again.',
  UserFacingClientFailure.appStoreLoad =>
    'App Store subscriptions could not be loaded. Check your connection and try again.',
  UserFacingClientFailure.appStorePurchase =>
    'The App Store purchase could not be started. Check your connection and try again.',
  UserFacingClientFailure.appStoreVerification =>
    'The App Store transaction could not be verified. Your purchase remains available to restore; try again.',
  UserFacingClientFailure.supportReport =>
    'The privacy-filtered report could not be sent. Your text remains on this device so you can retry.',
  UserFacingClientFailure.checkoutLoad =>
    'The secure checkout page could not be loaded. Check your connection and try again.',
  UserFacingClientFailure.uploadProtection =>
    'The encrypted transfer could not finish. Confirm the workspace is unlocked, check your connection, and retry.',
};

String testerSignupFailureMessage({int? httpStatus}) => switch (httpStatus) {
  400 =>
    'The signup request could not be accepted. Check the email and preferences, then try again.',
  409 => 'This email is already registered for the selected updates.',
  429 => 'Too many signup attempts were made. Wait briefly and try again.',
  502 || 503 || 504 =>
    'The tester signup service is temporarily unavailable. Check your connection and try again.',
  _ => 'Unable to join the tester list. Please try again.',
};
