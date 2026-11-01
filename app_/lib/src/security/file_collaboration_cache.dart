import 'dart:convert';

import 'package:crypto/crypto.dart';

const int fileCollaborationCacheMaxComponentCharacters = 49152;

/// Produces a bounded, non-reversible in-memory cache identity.
///
/// Collaboration snapshots can contain ciphertext and, during migration, old
/// readable text. The page needs to recognize unchanged snapshots, but it must
/// not keep a second concatenated copy of those values as a cache key.
String fileCollaborationCacheFingerprint(Iterable<Object?> components) {
  final canonical = StringBuffer('ronikdrive-collaboration-cache-v1;');
  for (final component in components) {
    final text = component?.toString() ?? '';
    if (text.length > fileCollaborationCacheMaxComponentCharacters) {
      canonical
        ..write('oversize:')
        ..write(text.length)
        ..write(';');
      continue;
    }
    canonical
      ..write(text.length)
      ..write(':')
      ..write(text)
      ..write(';');
  }
  return sha256.convert(utf8.encode(canonical.toString())).toString();
}

String fileCollaborationLegacyReviewFingerprint({
  required String fileId,
  required String reviewerUid,
  required String status,
  required String reviewerName,
  required String note,
}) {
  final canonical = jsonEncode(<String>[
    'ronikdrive-legacy-review-migration-v1',
    fileId.trim(),
    reviewerUid.trim(),
    status.trim(),
    reviewerName.trim(),
    note.trim(),
  ]);
  return sha256.convert(utf8.encode(canonical)).toString();
}
