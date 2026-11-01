import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../security/encryption_service.dart';
import '../privacy/memory_preview.dart' show SensitiveByteBuffer;
import '../shared/release_runtime_config.dart';
import '../storage/cloud_storage_provider.dart';
import '../storage/transfer_journal.dart';
import '../storage/upload_metadata_service.dart';
import '../storage/upload_coordinator.dart';
import '../storage/upload_source_snapshot.dart';
import 'drive_provider_protocol.dart';
import 'drive_relative_path.dart';

String nativeDriveFileVersion(String id, Map<String, dynamic> data) => crypto
    .sha256
    .convert(
      utf8.encode(
        jsonEncode([
          'native-drive-file-v1',
          id,
          data['fileName'] ?? '',
          data['encryptedName'] ?? '',
          data['folderId'] ?? '',
          data['sizeBytes'] ?? 0,
          data['encryptionMode'] ?? '',
          data['storageLayout'] ?? '',
          data['contentEncryption'] ?? '',
          data['revision'] ?? 1,
          data['lifecycleState'] ?? 'active',
        ]),
      ),
    )
    .toString();

bool nativeDriveStandardFile(Map<String, dynamic> data, String uid) =>
    data['uid'] == uid &&
    (data['ownerUid'] == null || data['ownerUid'] == uid) &&
    (data['storageScope'] == null || data['storageScope'] == 'personal') &&
    data['companyId'] == null &&
    (data['sharedKeyEnvelopes'] == null ||
        (data['sharedKeyEnvelopes'] is Map &&
            (data['sharedKeyEnvelopes'] as Map).isEmpty)) &&
    data['encryptionMode'] == 'standard' &&
    data['contentEncryption'] == 'standard' &&
    data['storageLayout'] == 'single' &&
    (data['lifecycleState'] ?? 'active') == 'active';

class FirestoreDriveBackend
    implements DriveProviderBackend, RecoverableDriveCreates {
  FirestoreDriveBackend({
    required this.firestore,
    required this.auth,
    required this.uid,
    required this.key,
    required this.storage,
    required this.ownerPrefix,
    required this.metadata,
    required this.journal,
    required this.authorized,
  });
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final String uid, ownerPrefix;
  final SecretKey key;
  final CloudStorageProvider storage;
  final UploadMetadataService metadata;
  final TransferJournal journal;
  final Future<bool> Function() authorized;
  static const _server = GetOptions(source: Source.server);
  bool _mutating = false;
  bool _revoked = false;
  final _reads = <StreamIterator<List<int>>>{};
  @override
  void invalidate() {
    _revoked = true;
    for (final read in _reads.toList()) {
      unawaited(read.cancel().catchError((Object _) {}));
    }
  }

  Future<void> _check() async {
    if (_revoked ||
        auth.currentUser?.uid != uid ||
        !await authorized() ||
        _revoked) {
      throw const ProviderFailure('unauthorized');
    }
  }

  bool _folderAllowed(Map<String, dynamic> d) =>
      d['uid'] == uid &&
      (d['storageScope'] == null || d['storageScope'] == 'personal') &&
      d['companyId'] == null &&
      d['sharedKeyEnvelopes'] == null &&
      d['metadataEncryption'] == 'standard-aes-gcm-v1' &&
      d['systemFolder'] != true;

  String _version(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    if (doc.reference.parent.id == 'files') {
      return nativeDriveFileVersion(doc.id, d);
    }
    return crypto.sha256
        .convert(
          utf8.encode(
            jsonEncode([
              doc.id,
              d['encryptedName'],
              d['parentId'],
              d['metadataEncryption'],
              d['systemFolder'],
              d['systemKey'],
            ]),
          ),
        )
        .toString();
  }

  String _id(DocumentSnapshot<Map<String, dynamic>> doc) =>
      doc.reference.parent.id == 'folders'
      ? 'd:${doc.id}'
      : 'f:${doc.data()!['versionGroupId'] ?? doc.id}';
  Future<ProviderItem> _item(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final d = doc.data()!;
    final directory = doc.reference.parent.id == 'folders';
    if (directory ? !_folderAllowed(d) : !nativeDriveStandardFile(d, uid)) {
      throw const ProviderFailure('not-found');
    }
    final cipherName = d['encryptedName'];
    if (cipherName is! String) throw const ProviderFailure('not-found');
    final name = await EncryptionService.instance.decryptFileName(
      cipherName,
      key,
    );
    if (name == null) throw const ProviderFailure('unauthorized');
    final parent = d[directory ? 'parentId' : 'folderId'];
    return ProviderItem(
      id: _id(doc),
      parentId: parent == null || parent == '' ? 'root' : 'd:$parent',
      name: name,
      version: _version(doc),
      directory: directory,
      size: directory ? 0 : (d['sizeBytes'] as num).toInt(),
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _all(
    String collection,
  ) async {
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      Query<Map<String, dynamic>> query = firestore
          .collection(collection)
          .where('uid', isEqualTo: uid)
          .orderBy(FieldPath.documentId)
          .limit(500);
      if (last != null) query = query.startAfterDocument(last);
      final page = await query.get(_server);
      docs.addAll(page.docs);
      if (docs.length > 10000) throw const ProviderFailure('too-large');
      if (page.docs.length < 500) return docs;
      last = page.docs.last;
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _document(String id) async {
    await _check();
    if (id.length > 2048 || id.contains('/') || id.length < 3) {
      throw const ProviderFailure('invalid');
    }
    if (id.startsWith('d:')) {
      final doc = await firestore
          .collection('folders')
          .doc(id.substring(2))
          .get(_server);
      if (!doc.exists || !_folderAllowed(doc.data()!)) {
        throw const ProviderFailure('not-found');
      }
      return doc;
    }
    if (!id.startsWith('f:')) throw const ProviderFailure('invalid');
    // Existing versionGroupId is stable across encrypted object replacement.
    final matches = (await _all('files'))
        .where(
          (doc) => nativeDriveStandardFile(doc.data(), uid) && _id(doc) == id,
        )
        .toList();
    if (matches.length != 1) throw const ProviderFailure('not-found');
    return matches.single;
  }

  Future<void> _parent(String id) async {
    final seen = <String>{};
    while (id != 'root') {
      if (!id.startsWith('d:') || !seen.add(id) || seen.length > 64) {
        throw const ProviderFailure('invalid');
      }
      id = (await _item(await _document(id))).parentId;
    }
  }

  @override
  Future<List<ProviderItem>> list(String parentId) async {
    await _check();
    if (parentId != 'working-set') await _parent(parentId);
    final result = <ProviderItem>[];
    final folders = await _all('folders');
    final visible = <String>{'root'};
    final pending = folders.where((doc) => _folderAllowed(doc.data())).toList();
    for (var depth = 0; depth < 64 && pending.isNotEmpty; depth++) {
      var added = false;
      for (final doc in List.of(pending)) {
        final data = doc.data();
        final parent = data['parentId'] == null || data['parentId'] == ''
            ? 'root'
            : 'd:${data['parentId']}';
        if (!visible.contains(parent)) continue;
        final entry = await _item(doc);
        visible.add(entry.id);
        pending.remove(doc);
        added = true;
        if (parentId == 'working-set' || entry.parentId == parentId) {
          result.add(entry);
        }
      }
      if (!added) break;
    }
    for (final doc in await _all('files')) {
      if (!nativeDriveStandardFile(doc.data(), uid)) continue;
      final entry = await _item(doc);
      if (visible.contains(entry.parentId) &&
          (parentId == 'working-set' || entry.parentId == parentId)) {
        result.add(entry);
      }
    }
    // Do not partially publish an ambiguous or malformed directory listing.
    final byParent = <String, List<DriveRelativePath>>{};
    for (final entry in result) {
      byParent
          .putIfAbsent(entry.parentId, () => [])
          .add(DriveRelativePath([entry.name]));
    }
    for (final paths in byParent.values) {
      validateDrivePathBatch(paths);
    }
    await _check();
    return result;
  }

  @override
  Future<ProviderItem> item(String id) async {
    await _check();
    if (id == 'root') {
      return ProviderItem(
        id: 'root',
        parentId: 'root',
        name: 'RonikCloud',
        version: '1',
        directory: true,
        size: 0,
      );
    }
    final entry = await _item(await _document(id));
    await _parent(entry.parentId);
    await _check();
    return entry;
  }

  @override
  Future<Uint8List> read(String id, String version) async {
    final doc = await _document(id);
    final entry = await _item(doc);
    await _parent(entry.parentId);
    if (entry.directory || entry.version != version) {
      throw const ProviderFailure('conflict');
    }
    if (entry.size > nativeDriveMaximumFileBytes) {
      throw const ProviderFailure('too-large');
    }
    final buffer = SensitiveByteBuffer(
      maximumBytes: nativeDriveMaximumFileBytes,
    );
    StreamIterator<List<int>>? iterator;
    try {
      final stream = await storage.download(
        objectKey: doc.data()!['fileName'] as String,
        encryptionKey: key,
        maxPlaintextBytes: nativeDriveMaximumFileBytes,
      );
      iterator = StreamIterator(stream.timeout(const Duration(seconds: 30)));
      _reads.add(iterator);
      var next = iterator.moveNext();
      unawaited(next.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
      await _check();
      while (await next) {
        await _check();
        final chunk = iterator.current;
        if (buffer.length + chunk.length > nativeDriveMaximumFileBytes) {
          throw const ProviderFailure('too-large');
        }
        buffer.add(chunk);
        next = iterator.moveNext();
      }
      // Whole-object MAC verification happens at stream completion. Nothing
      // is delivered to Explorer/Finder before it succeeds.
      await _check();
      if (buffer.length != entry.size || (await item(id)).version != version) {
        throw const ProviderFailure('conflict');
      }
      return buffer.takeBytes();
    } finally {
      buffer.clear();
      if (iterator != null) {
        _reads.remove(iterator);
        await iterator.cancel();
      }
    }
  }

  Future<T> _mutate<T>(Future<T> Function() work) async {
    if (_mutating) throw const ProviderFailure('busy');
    _mutating = true;
    try {
      await _check();
      return await work();
    } finally {
      _mutating = false;
    }
  }

  Future<void> _availableName(
    String parent,
    String name, {
    String? except,
  }) async {
    final key = DriveRelativePath([name]).collisionKey;
    if ((await list(parent)).any(
      (entry) =>
          entry.id != except &&
          DriveRelativePath([entry.name]).collisionKey == key,
    )) {
      throw const ProviderFailure('conflict');
    }
  }

  @override
  Future<ProviderItem> createWithRequestId(
    String requestId,
    String parentId,
    String name,
    bool directory,
    Uint8List contents,
  ) => _mutate(() async {
    if (requestId.isEmpty ||
        requestId.length > 2048 ||
        contents.length > nativeDriveMaximumFileBytes ||
        (directory && contents.isNotEmpty)) {
      throw const ProviderFailure('invalid');
    }
    await _parent(parentId);
    DriveRelativePath([name]);
    // Keyed digest avoids exposing a plaintext filename/content dictionary hash
    // in the cloud object key. Identical OS retries reuse the same destination.
    final secret = await key.extractBytes();
    final nonce = crypto.Hmac(crypto.sha256, secret)
        .convert(
          utf8.encode(
            jsonEncode([
              'native-create-v1',
              uid,
              ownerPrefix,
              requestId,
              parentId,
              name,
              directory,
              crypto.sha256.convert(contents).toString(),
            ]),
          ),
        )
        .toString();
    if (!directory) {
      final existing = await _uploadedItem('$ownerPrefix/objects/$nonce.bin');
      if (existing != null) return existing;
      await _availableName(parentId, name);
      return _upload(parentId, name, contents, nonce: nonce);
    }
    final ref = firestore.collection('folders').doc('native-$nonce');
    final existing = await ref.get(_server);
    if (existing.exists) {
      final result = await item('d:${ref.id}');
      if (result.parentId != parentId || result.name != name) {
        throw const ProviderFailure('conflict');
      }
      return result;
    }
    await _availableName(parentId, name);
    final encrypted = await EncryptionService.instance.encryptFileName(
      name,
      key,
    );
    await firestore.runTransaction((transaction) async {
      final fresh = await transaction.get(ref);
      await _check();
      if (fresh.exists) return;
      transaction.set(ref, {
        'uid': uid,
        'ownerUid': uid,
        'storageScope': 'personal',
        'metadataEncryption': 'standard-aes-gcm-v1',
        'encryptedName': encrypted,
        'color': '#dbe4ff',
        'createdAt': FieldValue.serverTimestamp(),
        if (parentId != 'root') 'parentId': parentId.substring(2),
      });
    });
    return item('d:${ref.id}');
  });

  Future<ProviderItem?> _uploadedItem(String object) async {
    final docs = await firestore
        .collection('files')
        .where('uid', isEqualTo: uid)
        .where('fileName', isEqualTo: object)
        .limit(2)
        .get(_server);
    if (docs.docs.isEmpty) return null;
    if (docs.docs.length != 1) throw const ProviderFailure('conflict');
    final result = await _item(docs.docs.single);
    await _parent(result.parentId);
    await _check();
    return result;
  }

  Future<String> _updateNonce(
    String id,
    String version,
    String? parent,
    String? name,
    Uint8List contents,
  ) async => crypto.Hmac(crypto.sha256, await key.extractBytes())
      .convert(
        utf8.encode(
          jsonEncode([
            'native-update-v1',
            uid,
            ownerPrefix,
            id,
            version,
            parent,
            name,
            crypto.sha256.convert(contents).toString(),
          ]),
        ),
      )
      .toString();

  @override
  Future<ProviderItem> create(
    String parentId,
    String name,
    bool directory,
    Uint8List contents,
  ) => _mutate(() async {
    await _parent(parentId);
    await _availableName(parentId, name);
    if (directory) {
      if (contents.isNotEmpty) throw const ProviderFailure('invalid');
      final ref = firestore.collection('folders').doc();
      final encrypted = await EncryptionService.instance.encryptFileName(
        name,
        key,
      );
      await _check();
      await ref.set({
        'uid': uid,
        'ownerUid': uid,
        'storageScope': 'personal',
        'metadataEncryption': 'standard-aes-gcm-v1',
        'encryptedName': encrypted,
        'color': '#dbe4ff',
        'createdAt': FieldValue.serverTimestamp(),
        if (parentId != 'root') 'parentId': parentId.substring(2),
      });
      return item('d:${ref.id}');
    }
    return _upload(parentId, name, contents);
  });
  @override
  Future<ProviderItem> update(
    String id,
    String version,
    String? parentId,
    String? name,
    Uint8List? contents,
  ) => _mutate(() async {
    String? replayNonce;
    if (contents != null) {
      if (contents.length > nativeDriveMaximumFileBytes) {
        throw const ProviderFailure('too-large');
      }
      replayNonce = await _updateNonce(id, version, parentId, name, contents);
      final replay = await _uploadedItem(
        '$ownerPrefix/objects/$replayNonce.bin',
      );
      if (replay != null) {
        if (replay.id != id) throw const ProviderFailure('conflict');
        return replay;
      }
    }
    final doc = await _document(id);
    final original = await _item(doc);
    if (original.version != version) throw const ProviderFailure('conflict');
    final parent = parentId ?? original.parentId;
    final label = name ?? original.name;
    await _parent(parent);
    await _availableName(parent, label, except: id);
    if (original.directory &&
        (contents != null || parent != original.parentId)) {
      throw const ProviderFailure('read-only');
    }
    if (contents != null) {
      return _upload(
        parent,
        label,
        contents,
        previous: doc,
        expected: version,
        nonce: replayNonce,
      );
    }
    if (name == null && parentId == null) return item(id);
    final encrypted = name == null
        ? null
        : await EncryptionService.instance.encryptFileName(label, key);
    await _check();
    await firestore.runTransaction((transaction) async {
      final fresh = await transaction.get(doc.reference);
      if (!fresh.exists ||
          _version(fresh) != version ||
          (original.directory
              ? !_folderAllowed(fresh.data()!)
              : !nativeDriveStandardFile(fresh.data()!, uid))) {
        throw const ProviderFailure('conflict');
      }
      await _check();
      transaction.update(doc.reference, {
        if (encrypted != null) 'encryptedName': encrypted,
        if (parentId != null)
          (original.directory ? 'parentId' : 'folderId'): parent == 'root'
              ? FieldValue.delete()
              : parent.substring(2),
      });
    });
    return item(id);
  });
  Future<ProviderItem> _upload(
    String parent,
    String name,
    Uint8List bytes, {
    DocumentSnapshot<Map<String, dynamic>>? previous,
    String? expected,
    String? nonce,
  }) async {
    if (bytes.length > nativeDriveMaximumFileBytes) {
      throw const ProviderFailure('too-large');
    }
    if (!journal.storageAvailable) throw const ProviderFailure('unavailable');
    nonce ??= List.generate(
      24,
      (_) => Random.secure().nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final object = '$ownerPrefix/objects/$nonce.bin';
    final transferId = 'native-$nonce';
    // Replay the exact staged metadata instead of uploading new ciphertext over
    // a blob whose first commit may already have succeeded.
    final pending = journal.entries
        .where(
          (entry) => entry.id == transferId && entry.metadataPayload != null,
        )
        .firstOrNull;
    if (pending != null) {
      await _check();
      await metadata.recordUploadedFilePayload(pending.metadataPayload!);
      await journal.complete(transferId);
      final result = await _uploadedItem(object);
      if (result == null) throw const ProviderFailure('unavailable');
      return result;
    }
    final payload = metadata.buildRecordUploadedFilePayload(
      objectKey: object,
      size: bytes.length,
      folderId: parent == 'root' ? null : parent.substring(2),
      encryptionMode: 'standard',
      contentEncryption: 'standard',
      storageLayout: 'single',
      storageScope: 'personal',
      encryptedName: await EncryptionService.instance.encryptFileName(
        name,
        key,
      ),
      supersedesFileId: previous?.id,
    )..['nativeExpectedVersion'] = expected ?? 'create';
    final sourceSnapshot = UploadCoordinator.enabled
      ? await UploadSourceSnapshot.capture(Stream.value(bytes)) : null;
    if (!UploadCoordinator.enabled || journal.uploadCheckpoint(transferId) == null) {
    await journal.begin(
      id: transferId,
      kind: TransferJournalKind.upload,
      label: 'Desktop drive upload',
      objectKey: object,
      totalBytes: bytes.length,
    );
    }
    try {
      await _check();
      await storage.upload(
        objectKey: object,
        stream: sourceSnapshot?.verify(Stream.value(bytes)) ?? Stream.value(bytes),
        length: bytes.length,
        encryptionKey: key,
        transferId: transferId,
        checkpointSink: journal,
        sourceFingerprint: sourceSnapshot?.fingerprint,
      );
      await journal.stageMetadataCommit(transferId, payload: payload);
      await _check();
      await metadata.recordUploadedFilePayload(payload);
      await journal.complete(transferId);
    } catch (error) {
      await journal.metadataCommitFailed(transferId, error);
      if (previous != null) {
        try {
          if ((await item(_id(previous))).version != expected) {
            throw const ProviderFailure('conflict');
          }
        } on ProviderFailure {
          rethrow;
        } catch (_) {
          /* Preserve the recoverable upload and local edit. */
        }
      }
      rethrow;
    }
    final docs = await _all('files');
    final matches = docs
        .where((doc) => doc.data()['fileName'] == object)
        .toList();
    if (matches.length != 1) throw const ProviderFailure('unavailable');
    await _check();
    return _item(matches.single);
  }

  @override
  Future<void> recycle(String id, String version) => _mutate(() async {
    final doc = await _document(id);
    final current = await _item(doc);
    if (current.version != version) throw const ProviderFailure('conflict');
    // Folder deletion needs atomic descendant coordination with all clients.
    // Until then, refuse rather than orphaning concurrent uploads.
    if (current.directory) throw const ProviderFailure('read-only');
    final token = await auth.currentUser?.getIdToken();
    if (token == null) throw const ProviderFailure('unauthorized');
    final response = await http
        .post(
          ReleaseRuntimeConfig.resolveCallableRestUri(
            projectId: auth.app.options.projectId,
            functionName: 'recycleDesktopDriveFile',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'data': {'fileId': doc.id, 'version': version},
          }),
        )
        .timeout(const Duration(seconds: 30));
    await _check();
    if (response.statusCode == 409) throw const ProviderFailure('conflict');
    if (response.statusCode != 200) throw const ProviderFailure('unavailable');
  });
}
