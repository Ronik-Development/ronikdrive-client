import 'package:cloud_firestore/cloud_firestore.dart';

/// Saves protected folder metadata without reading a possibly absent document.
Future<void> upsertEncryptedFolderDocument(
  DocumentReference<Map<String, dynamic>> reference,
  Map<String, dynamic> payload,
) async {
  try {
    await reference.update(<String, dynamic>{
      ...payload,
      'name': FieldValue.delete(),
      'path': FieldValue.delete(),
      'pathSegments': FieldValue.delete(),
    });
  } on FirebaseException catch (error) {
    // Owner-only update rules inspect resource.data.uid. For an absent folder,
    // that check can return permission-denied before the SDK reports not-found.
    // A create is still subject to the normal ownership and encryption rules.
    // Merge preserves unrelated fields if another writer created the folder;
    // the rules also forbid changing an existing folder's createdAt timestamp.
    if (error.code != 'not-found' && error.code != 'permission-denied') {
      rethrow;
    }
    await reference.set(<String, dynamic>{
      ...payload,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
