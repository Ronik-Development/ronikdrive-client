import 'dart:convert';

import 'package:crypto/crypto.dart';

String privacySupportCodeForUid(String uid) {
  final normalizedUid = uid.trim();
  if (normalizedUid.isEmpty) {
    return 'UNKNOWN';
  }
  final digest = sha256
      .convert(utf8.encode('ronikdrive-support-v1:$normalizedUid'))
      .toString()
      .substring(0, 12)
      .toUpperCase();
  return '${digest.substring(0, 6)}-${digest.substring(6)}';
}
