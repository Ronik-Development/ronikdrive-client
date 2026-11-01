import 'dart:convert';

import 'package:crypto/crypto.dart';

String baseStorageObjectKey(String objectKey) {
  final normalized = objectKey.trim();
  final partMarker = normalized.indexOf('.parts/');
  return partMarker < 0 ? normalized : normalized.substring(0, partMarker);
}

String objectKeyHash(String objectKey) {
  final normalized = baseStorageObjectKey(objectKey);
  if (normalized.isEmpty) {
    throw ArgumentError.value(objectKey, 'objectKey', 'cannot be empty');
  }
  return sha256.convert(utf8.encode(normalized)).toString();
}

String hashedFileDocumentIdForObjectKey(String objectKey) =>
    'f_${objectKeyHash(objectKey)}';

String pendingFileIdForObjectKey(String objectKey) =>
    'pending_${objectKeyHash(objectKey)}';

/// Whether a local upload-completion record should be applied to the current
/// workspace state.
///
/// The metadata callable and the Firestore listener race legitimately. When
/// Firestore wins, the durable record can already be visible before the
/// callable returns and attempts to insert its deterministic optimistic
/// record. Applying that late `pending_` record would replace the durable ID,
/// after which the unchanged Firestore document is not emitted again and the
/// upload can appear twice on the next merge. Preserve the durable identity in
/// that ordering; the inverse ordering is handled by
/// [pendingFileIdReplacedByServerRecord].
bool shouldApplyOptimisticFileRecord({
  required String candidateFileId,
  required String objectKey,
  required String? existingFileIdForObjectKey,
}) {
  final pendingId = pendingFileIdForObjectKey(objectKey);
  if (candidateFileId.trim() != pendingId) {
    return true;
  }
  final existingId = existingFileIdForObjectKey?.trim();
  return existingId == null || existingId.isEmpty || existingId == pendingId;
}

/// Returns the optimistic local identity replaced by an authoritative server
/// record for the same opaque storage object.
///
/// Uploads are shown immediately with a deterministic `pending_` identity.
/// Firestore assigns the durable file identity asynchronously. If both are
/// kept, one upload appears twice and its transfer size is counted twice until
/// the next full refresh. Only the deterministic pending identity is eligible
/// for replacement; distinct durable records are never collapsed here.
String? pendingFileIdReplacedByServerRecord({
  required String serverFileId,
  required String objectKey,
  required Iterable<String> knownFileIds,
}) {
  final normalizedServerId = serverFileId.trim();
  if (normalizedServerId.isEmpty) {
    return null;
  }
  final pendingId = pendingFileIdForObjectKey(objectKey);
  if (pendingId == normalizedServerId || !knownFileIds.contains(pendingId)) {
    return null;
  }
  return pendingId;
}

String legacyFileDocumentIdForObjectKey(String objectKey) =>
    baseStorageObjectKey(objectKey).replaceAll('/', '--');

const String _previewObjectIdentityDomain = 'ronikdrive-preview-object-v2\n';

/// Resolves an encrypted preview to an object key with the same opaque shape
/// as ordinary encrypted content.
///
/// The source's Personal or Business authorization scope is retained, while
/// the provider-visible key contains no `thumbnail`, image, MIME, or filename
/// label. The deterministic token lets authorized cleanup and inventory code
/// recognize the optional ciphertext without storing another relationship in
/// file metadata.
String thumbnailStorageObjectKey(
  String objectKey, {
  required String fallbackPrefix,
}) {
  final normalized = baseStorageObjectKey(objectKey);
  final normalizedFallback = fallbackPrefix.trim().replaceFirst(
    RegExp(r'/+$'),
    '',
  );
  if (normalized.isEmpty || normalizedFallback.isEmpty) {
    throw ArgumentError('An object key and fallback prefix are required.');
  }

  const marker = '/objects/';
  final markerIndex = normalized.indexOf(marker);
  final scopePrefix = markerIndex > 0
      ? normalized.substring(0, markerIndex)
      : normalizedFallback;
  final digest = sha256
      .convert(utf8.encode('$_previewObjectIdentityDomain$normalized'))
      .bytes;
  final token = base64Url.encode(digest.sublist(0, 16)).replaceAll('=', '');
  return '$scopePrefix/objects/'
      '${token.substring(0, 2).toLowerCase()}/'
      '${token.substring(2, 4).toLowerCase()}/$token';
}

/// Returns the provider key used by preview objects created before opaque
/// preview identity v2. This is read/delete compatibility only; new writes
/// must use [thumbnailStorageObjectKey].
String legacyThumbnailStorageObjectKey(
  String objectKey, {
  required String fallbackPrefix,
}) {
  final normalized = baseStorageObjectKey(objectKey);
  final normalizedFallback = fallbackPrefix.trim().replaceFirst(
    RegExp(r'/+$'),
    '',
  );
  if (normalized.isEmpty || normalizedFallback.isEmpty) {
    throw ArgumentError('An object key and fallback prefix are required.');
  }

  const marker = '/objects/';
  final markerIndex = normalized.indexOf(marker);
  final objectToken = normalized.split('/').last.trim();
  if (markerIndex > 0 && objectToken.isNotEmpty) {
    return '${normalized.substring(0, markerIndex)}/thumbnails/$objectToken';
  }
  return '$normalizedFallback/thumbnails/${objectKeyHash(normalized)}';
}

List<String> thumbnailStorageObjectKeyCandidates(
  String objectKey, {
  required String fallbackPrefix,
}) {
  final current = thumbnailStorageObjectKey(
    objectKey,
    fallbackPrefix: fallbackPrefix,
  );
  final legacy = legacyThumbnailStorageObjectKey(
    objectKey,
    fallbackPrefix: fallbackPrefix,
  );
  return current == legacy ? <String>[current] : <String>[current, legacy];
}
