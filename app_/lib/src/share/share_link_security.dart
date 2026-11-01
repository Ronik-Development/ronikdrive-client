import 'dart:convert';

import 'package:cryptography/cryptography.dart';

const String shareDownloadProofFormat = 'hmac-sha256-v1';
const int shareAccessPrivacyVersion = 4;

const String _shareDownloadProofDomain = 'ronikdrive-share-download-proof-v1\n';

/// Returns an expiry boundary with hour-level precision.
///
/// Expiry is operationally required to enforce a public link. Rounding the
/// target up to the next UTC hour avoids retaining a precise creation-time
/// fingerprint while never shortening the duration selected by the owner.
DateTime coarseShareExpiry({required DateTime now, required int days}) {
  if (days < 1 || days > 365) {
    throw RangeError.range(days, 1, 365, 'days');
  }
  final target = now.toUtc().add(Duration(days: days));
  final hour = DateTime.utc(target.year, target.month, target.day, target.hour);
  return target.isAfter(hour) ? hour.add(const Duration(hours: 1)) : hour;
}

class ShareLinkOwnerIndex {
  const ShareLinkOwnerIndex.empty()
    : _summariesBySourceFileId = const <String, List<ShareLinkOwnerSummary>>{};

  ShareLinkOwnerIndex.fromMaps(
    Iterable<Map<String, dynamic>> documents, {
    DateTime? Function(Object? value)? timestampParser,
  }) : _summariesBySourceFileId = _buildIndex(
         documents,
         timestampParser: timestampParser,
       );

  final Map<String, List<ShareLinkOwnerSummary>> _summariesBySourceFileId;

  static Map<String, List<ShareLinkOwnerSummary>> _buildIndex(
    Iterable<Map<String, dynamic>> documents, {
    DateTime? Function(Object? value)? timestampParser,
  }) {
    final mutable = <String, List<ShareLinkOwnerSummary>>{};
    for (final document in documents) {
      final sourceFileId = document['sourceFileId']?.toString().trim() ?? '';
      if (sourceFileId.isEmpty || sourceFileId.length > 256) {
        continue;
      }
      mutable
          .putIfAbsent(sourceFileId, () => <ShareLinkOwnerSummary>[])
          .add(
            ShareLinkOwnerSummary.fromMap(
              document,
              timestampParser: timestampParser,
            ),
          );
    }
    return Map<String, List<ShareLinkOwnerSummary>>.unmodifiable({
      for (final entry in mutable.entries)
        entry.key: List<ShareLinkOwnerSummary>.unmodifiable(entry.value),
    });
  }

  int activeCountFor(String sourceFileId, DateTime now) {
    final normalized = sourceFileId.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    return _summariesBySourceFileId[normalized]
            ?.where((summary) => summary.statusLabel(now) == 'Active')
            .length ??
        0;
  }

  DateTime? nextExpiryAfter(DateTime now) {
    final utcNow = now.toUtc();
    DateTime? next;
    for (final summaries in _summariesBySourceFileId.values) {
      for (final summary in summaries) {
        final expiry = summary.expiresAt;
        if (summary.revoked ||
            summary.downloadLimitReached ||
            expiry == null ||
            !expiry.isAfter(utcNow)) {
          continue;
        }
        if (next == null || expiry.isBefore(next)) {
          next = expiry;
        }
      }
    }
    return next;
  }
}

Future<String> deriveShareDownloadProof({
  required SecretKey shareKey,
  required String token,
}) async {
  final normalizedToken = token.trim();
  if (normalizedToken.isEmpty ||
      normalizedToken.length > 128 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalizedToken)) {
    throw const FormatException('The share token is invalid.');
  }
  final mac = await Hmac.sha256().calculateMac(
    utf8.encode('$_shareDownloadProofDomain$normalizedToken'),
    secretKey: shareKey,
  );
  return base64Encode(mac.bytes);
}

class ShareLinkOwnerSummary {
  const ShareLinkOwnerSummary({
    required this.revoked,
    required this.expiresAt,
    required this.downloadCount,
    required this.maxDownloads,
    required this.notifyOnFirstAccess,
    required this.firstAccessNotified,
    required this.passwordProofProtected,
    required this.budgetWarningNotified,
    required this.proofAbuseNotified,
  });

  factory ShareLinkOwnerSummary.fromMap(
    Map<String, dynamic> data, {
    DateTime? Function(Object? value)? timestampParser,
  }) {
    DateTime? parse(Object? value) {
      if (timestampParser != null) {
        return timestampParser(value)?.toUtc();
      }
      if (value is DateTime) {
        return value.toUtc();
      }
      if (value is String) {
        return DateTime.tryParse(value)?.toUtc();
      }
      return null;
    }

    int count(Object? value, {int maximum = 1000000000}) {
      if (value is! num || !value.isFinite) {
        return 0;
      }
      final rounded = value.toInt();
      return rounded >= 0 && rounded <= maximum ? rounded : 0;
    }

    return ShareLinkOwnerSummary(
      revoked: data['revoked'] == true,
      expiresAt: parse(data['expiresAt']),
      downloadCount: count(data['downloadCount']),
      maxDownloads: count(data['maxDownloads'], maximum: 10000),
      notifyOnFirstAccess: data['notifyOnAccess'] == true,
      firstAccessNotified:
          data['firstAccessNotified'] == true ||
          parse(data['firstAccessNotifiedAt']) != null,
      passwordProofProtected:
          data['downloadProofFormat'] == shareDownloadProofFormat,
      budgetWarningNotified: data['budgetWarningNotified'] == true,
      proofAbuseNotified: data['proofAbuseNotified'] == true,
    );
  }

  final bool revoked;
  final DateTime? expiresAt;
  final int downloadCount;
  final int maxDownloads;
  final bool notifyOnFirstAccess;
  final bool firstAccessNotified;
  final bool passwordProofProtected;
  final bool budgetWarningNotified;
  final bool proofAbuseNotified;

  bool get downloadLimitReached =>
      maxDownloads > 0 && downloadCount >= maxDownloads;

  bool isExpired(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now.toUtc());

  String statusLabel(DateTime now) {
    if (revoked) {
      return 'Revoked';
    }
    if (isExpired(now)) {
      return 'Expired';
    }
    if (downloadLimitReached) {
      return 'Download budget reached';
    }
    return 'Active';
  }

  String get requestCountLabel => maxDownloads > 0
      ? 'Encrypted payload requests: $downloadCount of $maxDownloads'
      : 'Encrypted payload requests: $downloadCount (no link budget)';

  String get proofLabel => passwordProofProtected
      ? 'A secret-derived proof is required before encrypted payload egress.'
      : 'Legacy link: the token alone can request encrypted payload bytes. Recreate it.';

  String get alertLabel {
    if (firstAccessNotified) {
      return 'First-access alert sent. Exact access time is not retained.';
    }
    return notifyOnFirstAccess
        ? 'First-access alert is enabled.'
        : 'First-access alert is off.';
  }

  String get budgetAlertLabel => budgetWarningNotified
      ? 'Request-budget alert sent without file or recipient details.'
      : maxDownloads > 0
      ? 'A generic alert is sent near the request-budget limit.'
      : 'Legacy link has no request-budget alert. Recreate it.';

  String? get abuseAlertLabel => proofAbuseNotified
      ? 'Suspicious proof attempts were throttled. Revoke this link if unexpected.'
      : null;

  bool get requiresSecurityAttention =>
      proofAbuseNotified || !passwordProofProtected || maxDownloads <= 0;

  static String displayReference(String token) {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      return 'Share link';
    }
    final tail = normalized.length <= 6
        ? normalized
        : normalized.substring(normalized.length - 6);
    return 'Share link - $tail';
  }
}
