import 'package:cloud_firestore/cloud_firestore.dart';

/// A UI hint only; the callable checks current server-owned billing state again.
bool canSubmitIssueReport(Map<String, dynamic>? profile, {DateTime? now}) {
  if (profile == null) return false;
  final instant = now ?? DateTime.now();
  bool activeSource(Map source) {
    final expiry = _date(source['currentPeriodEnd']);
    final revoked = _date(source['revokedAt']);
    return source['status'] == 'active' &&
        const [
          'basic',
          'pro',
          'ultra',
        ].contains(source['tier'] ?? source['planTier']) &&
        (revoked == null || revoked.isAfter(instant)) &&
        (expiry == null || expiry.isAfter(instant));
  }

  final sources = profile['billingSources'];
  if (sources is Map && sources.isNotEmpty) {
    return const ['stripe', 'app_store'].any((provider) {
      final source = sources[provider];
      return source is Map && activeSource(source);
    });
  }
  final expiry = _date(
    profile['currentPeriodEnd'] ?? profile['subscriptionEndDate'],
  );
  return profile['subscriptionStatus'] == 'active' &&
      const ['stripe', 'app_store'].contains(
        profile['billingPrimaryProvider'] ?? profile['subscriptionProvider'],
      ) &&
      const [
        'basic',
        'pro',
        'ultra',
      ].contains(profile['subscriptionTier'] ?? profile['planTier']) &&
      expiry != null &&
      expiry.isAfter(instant);
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is num && value.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(
      (value > 100000000000 ? value : value * 1000).round(),
    );
  }
  return value is String ? DateTime.tryParse(value) : null;
}
