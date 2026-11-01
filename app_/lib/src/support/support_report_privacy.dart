import '../privacy/privacy_redaction.dart';

const String supportReportPrivacyVersion = 'support-report-minimal-v1';

enum SupportReportCategory { issue, productFeedback }

String redactSupportReportText(String value) {
  var output = redactDiagnosticText(value);
  output = output.replaceAll(
    RegExp(r'https?://[^\s]+', caseSensitive: false),
    '<url-redacted>',
  );
  output = output.replaceAll(
    RegExp(
      r'(?<![A-Za-z0-9])[A-Za-z]:\\(?:[^\\\s]+\\)*[^\\\s]*',
      caseSensitive: false,
    ),
    '<path-redacted>',
  );
  output = output.replaceAllMapped(
    RegExp(r'''(^|[\s"'(])/(?:[^/\s]+/)*[^/\s,;)"']+''', multiLine: true),
    (match) => '${match.group(1) ?? ''}<path-redacted>',
  );
  return output;
}

class SupportReportPrivacyException implements Exception {
  const SupportReportPrivacyException(this.message);

  final String message;

  @override
  String toString() => 'SupportReportPrivacyException: $message';
}

class SupportReportPayload {
  const SupportReportPayload._({
    required this.title,
    required this.description,
    required this.stepsToReproduce,
    required this.platform,
    required this.buildMode,
    required this.category,
  });

  final String? title;
  final String description;
  final String? stepsToReproduce;
  final String platform;
  final String buildMode;
  final SupportReportCategory category;

  factory SupportReportPayload.prepare({
    required String title,
    required String description,
    required String stepsToReproduce,
    required String platform,
    required String buildMode,
    SupportReportCategory category = SupportReportCategory.issue,
  }) {
    final protectedDescription = _requiredProtectedText(
      description,
      label: 'description',
      maxLength: 4000,
    );
    return SupportReportPayload._(
      category: category,
      title: _optionalProtectedText(title, label: 'title', maxLength: 160),
      description: protectedDescription,
      stepsToReproduce: _optionalProtectedText(
        stepsToReproduce,
        label: 'steps',
        maxLength: 4000,
      ),
      platform: _platform(platform),
      buildMode: _buildMode(buildMode),
    );
  }

  Map<String, Object?> toCallablePayload() => <String, Object?>{
    'privacyVersion': supportReportPrivacyVersion,
    'category': category == SupportReportCategory.issue
        ? 'issue'
        : 'product_feedback',
    if (title != null) 'title': title,
    'description': description,
    if (stepsToReproduce != null) 'stepsToReproduce': stepsToReproduce,
    'platform': platform,
    'buildMode': buildMode,
  };

  static String _requiredProtectedText(
    String value, {
    required String label,
    required int maxLength,
  }) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > maxLength) {
      throw SupportReportPrivacyException(
        'The $label must contain 1 to $maxLength characters.',
      );
    }
    if (_hasUnsupportedControl(normalized)) {
      throw SupportReportPrivacyException('The $label contains invalid text.');
    }
    final protected = redactSupportReportText(normalized).trim();
    if (protected.isEmpty || protected.length > maxLength) {
      throw SupportReportPrivacyException('The $label is invalid.');
    }
    return protected;
  }

  static String? _optionalProtectedText(
    String value, {
    required String label,
    required int maxLength,
  }) {
    if (value.trim().isEmpty) return null;
    return _requiredProtectedText(value, label: label, maxLength: maxLength);
  }

  static bool _hasUnsupportedControl(String value) {
    for (final unit in value.codeUnits) {
      if ((unit < 32 && unit != 9 && unit != 10 && unit != 13) || unit == 127) {
        return true;
      }
    }
    return false;
  }

  static String _platform(String value) {
    final normalized = value.trim();
    const allowed = <String>{
      'android',
      'fuchsia',
      'iOS',
      'linux',
      'macOS',
      'windows',
      'web',
      'unknown',
    };
    if (!allowed.contains(normalized)) {
      throw const SupportReportPrivacyException(
        'The support platform is invalid.',
      );
    }
    return normalized;
  }

  static String _buildMode(String value) {
    final normalized = value.trim();
    if (!const <String>{'debug', 'profile', 'release'}.contains(normalized)) {
      throw const SupportReportPrivacyException(
        'The support build mode is invalid.',
      );
    }
    return normalized;
  }
}

class SupportReportReceipt {
  const SupportReportReceipt({
    required this.supportCode,
    required this.retentionDays,
  });

  final String supportCode;
  final int retentionDays;

  factory SupportReportReceipt.fromCallableResult(Map<String, dynamic> result) {
    if (result['accepted'] != true) {
      throw const SupportReportPrivacyException(
        'The support service did not accept the report.',
      );
    }
    final supportCode = result['supportCode']?.toString().trim() ?? '';
    final retentionDays = switch (result['retentionDays']) {
      int value => value,
      num value => value.round(),
      _ => int.tryParse(result['retentionDays']?.toString() ?? '') ?? 0,
    };
    if (!RegExp(r'^[A-F0-9]{6}-[A-F0-9]{6}$').hasMatch(supportCode) ||
        retentionDays < 1 ||
        retentionDays > 3650) {
      throw const SupportReportPrivacyException(
        'The support service returned an invalid receipt.',
      );
    }
    return SupportReportReceipt(
      supportCode: supportCode,
      retentionDays: retentionDays,
    );
  }
}
