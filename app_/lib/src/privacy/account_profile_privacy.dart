const int accountProfilePrivacyVersion = 1;

Map<String, dynamic> protectedAccountProfileCreatePayload({
  required String createdAt,
  required String legalVersion,
  required String legalAcceptedAt,
  required bool productUpdatesOptIn,
}) {
  final normalizedCreatedAt = createdAt.trim();
  final normalizedLegalVersion = legalVersion.trim();
  final normalizedLegalAcceptedAt = legalAcceptedAt.trim();
  if (normalizedCreatedAt.isEmpty ||
      normalizedLegalVersion.isEmpty ||
      normalizedLegalAcceptedAt.isEmpty) {
    throw ArgumentError(
      'Account profile timestamps and policy version are required.',
    );
  }

  return <String, dynamic>{
    'profilePrivacyVersion': accountProfilePrivacyVersion,
    'createdAt': normalizedCreatedAt,
    'currentPeriodEnd': 'pending',
    'capacity': 'pending',
    'subscriptionStatus': 'pending',
    'legalVersion': normalizedLegalVersion,
    'termsAcceptedAt': normalizedLegalAcceptedAt,
    'privacyAcknowledgedAt': normalizedLegalAcceptedAt,
    'acceptableUseAcceptedAt': normalizedLegalAcceptedAt,
    'cancellationRefundAcknowledgedAt': normalizedLegalAcceptedAt,
    'dataRetentionAcknowledgedAt': normalizedLegalAcceptedAt,
    'subprocessorsAcknowledgedAt': normalizedLegalAcceptedAt,
    'legalAcceptanceSource': 'signup',
    'productUpdatesOptIn': productUpdatesOptIn,
    'productUpdatesSource': 'signup',
    if (productUpdatesOptIn) 'productUpdatesOptInAt': normalizedLegalAcceptedAt,
  };
}
