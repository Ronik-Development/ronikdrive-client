import 'dart:convert';

import 'package:crypto/crypto.dart';

String? sanitizeStorageHomePrefix(String? source) {
  if (source == null) {
    return null;
  }
  final normalized = source.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }

  final buffer = StringBuffer();
  var lastWasUnderscore = false;
  for (final codeUnit in normalized.codeUnits) {
    final isLowercaseLetter = codeUnit >= 97 && codeUnit <= 122;
    final isDigit = codeUnit >= 48 && codeUnit <= 57;
    if (isLowercaseLetter || isDigit) {
      buffer.writeCharCode(codeUnit);
      lastWasUnderscore = false;
      continue;
    }

    if (!lastWasUnderscore && buffer.isNotEmpty) {
      buffer.write('_');
      lastWasUnderscore = true;
    }
  }

  final sanitized = buffer.toString().trim();
  if (sanitized.isEmpty) {
    return null;
  }
  return sanitized;
}

String? storageHomePrefixForUid(String? uid) {
  final normalized = uid?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  final digest = sha256.convert(utf8.encode(normalized)).toString();
  return 'user_${digest.substring(0, 32)}';
}

String _stableHashToken(String value, {int length = 32}) {
  final digest = sha256.convert(utf8.encode(value.trim())).toString();
  return digest.substring(0, length.clamp(1, digest.length));
}

String? companyStorageRootPrefix(String? companyId) {
  final normalized = companyId?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return 'company_${_stableHashToken('company:$normalized', length: 28)}';
}

String? companyPrivateStoragePrefix(String? companyId, String? uid) {
  final root = companyStorageRootPrefix(companyId);
  final normalizedUid = uid?.trim();
  if (root == null || normalizedUid == null || normalizedUid.isEmpty) {
    return null;
  }
  return '$root/private/${_stableHashToken(normalizedUid, length: 28)}';
}

String? companySharedStoragePrefix(String? companyId) {
  final root = companyStorageRootPrefix(companyId);
  return root == null ? null : '$root/shared';
}

String? companyGroupStoragePrefix(String? companyId, String? groupId) {
  final root = companyStorageRootPrefix(companyId);
  final normalizedGroupId = groupId?.trim();
  if (root == null || normalizedGroupId == null || normalizedGroupId.isEmpty) {
    return null;
  }
  return '$root/groups/${_stableHashToken('group:$normalizedGroupId', length: 28)}';
}
