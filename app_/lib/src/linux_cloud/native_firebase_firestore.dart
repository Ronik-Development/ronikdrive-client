import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firestore_wire/google/firestore/v1/document.pb.dart' as wire;
import 'firestore_wire/google/firestore/v1/firestore.pbgrpc.dart' as rpc;
import 'firestore_wire/google/firestore/v1/write.pb.dart' as write;
import 'native_auth_session.dart';
import 'native_firestore_codec.dart';
import 'native_firestore_query_spec.dart';
import 'native_firestore_rpc.dart';
import 'native_firestore_writes.dart';

part 'native_firestore_references.dart';
part 'native_firestore_transactions.dart';

/// User-authenticated Firestore transport for the native Linux application.
/// Encrypted offline files are managed by the app, not a plaintext SDK cache.
class NativeFirebaseFirestore extends FirebaseFirestorePlatform {
  NativeFirebaseFirestore({
    required this.sessionFor,
    this.emulatorPort,
    FirebaseApp? app,
    String databaseId = '(default)',
  }) : super(appInstance: app, databaseChoice: databaseId);

  final NativeAuthSession Function(String appName) sessionFor;
  final int? emulatorPort;
  final _delegates = <String, NativeFirebaseFirestore>{};
  final _pending = <Future<void>>{};
  NativeFirestoreRpc? _connection;
  bool _terminated = false;
  Settings _settings = const Settings(persistenceEnabled: false);
  late final codec = NativeFirestoreCodec(this);
  late final writes = NativeFirestoreWrites(codec);
  NativeAuthSession get session => sessionFor(app.name);

  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) => _delegates.putIfAbsent(
    '${app.name}|$databaseId',
    () => NativeFirebaseFirestore(
      sessionFor: sessionFor,
      emulatorPort: emulatorPort,
      app: app,
      databaseId: databaseId,
    ),
  );

  void _check({String? uid, bool fence = false}) {
    if (_terminated) throw NativeFirestoreCodec.invalid('failed-precondition');
    if (fence && session.currentIdentity?.uid != uid) {
      throw NativeFirestoreCodec.invalid('cancelled');
    }
  }

  NativeFirestoreRpc get connection {
    _check();
    return _connection ??= NativeFirestoreRpc(
      session: session,
      apiKey: app.options.apiKey,
      databaseId: databaseId,
      emulatorPort: emulatorPort,
    );
  }

  @override
  Settings get settings => _settings;
  @override
  set settings(Settings value) {
    _check();
    if (_connection != null) {
      throw NativeFirestoreCodec.invalid('failed-precondition');
    }
    final expectedHost = emulatorPort == null
        ? 'firestore.googleapis.com'
        : '127.0.0.1:$emulatorPort';
    if (value.persistenceEnabled == true ||
        (value.host != null && value.host != expectedHost) ||
        (value.sslEnabled != null &&
            value.sslEnabled != (emulatorPort == null))) {
      throw NativeFirestoreCodec.invalid('failed-precondition');
    }
    _settings = value.copyWith(persistenceEnabled: false);
  }

  @override
  void useEmulator(String host, int port) {
    _check();
    if (!const {'127.0.0.1', 'localhost'}.contains(host) ||
        port != emulatorPort ||
        session.transport.emulatorPort == null) {
      throw NativeFirestoreCodec.invalid('failed-precondition');
    }
  }

  @override
  DocumentReferencePlatform doc(String documentPath) {
    _check();
    writes.resource(documentPath);
    return _NativeDocument(this, documentPath);
  }

  @override
  CollectionReferencePlatform collection(String collectionPath) {
    _check();
    return _NativeCollection(this, collectionPath);
  }

  @override
  QueryPlatform collectionGroup(String collectionPath) {
    _check();
    return _NativeQuery(
      this,
      NativeFirestoreQuerySpec(
        codec: codec,
        path: collectionPath,
        collectionGroup: true,
      ),
    );
  }

  DocumentSnapshotPlatform snapshot(String path, wire.Document? document) {
    if (document != null && document.name != writes.resource(path)) {
      throw NativeFirestoreCodec.invalid('data-loss');
    }
    return DocumentSnapshotPlatform(
      this,
      path,
      document?.fields.map((key, value) => MapEntry(key, codec.decode(value))),
      PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
    );
  }

  String documentPath(wire.Document document) {
    final prefix = '${codec.documentsRoot}/';
    if (!document.name.startsWith(prefix)) {
      throw NativeFirestoreCodec.invalid('data-loss');
    }
    final path = document.name.substring(prefix.length);
    writes.resource(path);
    return path;
  }

  void requireServer(GetOptions options) {
    _check();
    if (options.source == Source.cache) {
      throw NativeFirestoreCodec.invalid('unavailable');
    }
  }

  Stream<List<wire.Document>> watch(rpc.Target target, ListenSource source) {
    if (source == ListenSource.cache) {
      return Stream.error(NativeFirestoreCodec.invalid('unavailable'));
    }
    return connection.watch(target);
  }

  Future<void> commit(List<write.Write> entries, String? uid) {
    _check(uid: uid, fence: true);
    if (entries.length > 500) throw NativeFirestoreCodec.invalid();
    final future = connection
        .invoke(
          (client, options) => client.commit(
            rpc.CommitRequest(database: connection.database, writes: entries),
            options: options,
          ),
        )
        .then<void>((_) => _check(uid: uid, fence: true));
    _pending.add(future);
    // Register cleanup without creating an unhandled error future.
    unawaited(
      future.then(
        (_) {
          _pending.remove(future);
        },
        onError: (Object error, StackTrace stack) {
          _pending.remove(future);
        },
      ),
    );
    return future;
  }

  @override
  WriteBatchPlatform batch() {
    _check();
    return _NativeBatch(this);
  }

  @override
  Future<void> waitForPendingWrites() async {
    _check();
    final uid = session.currentIdentity?.uid;
    await Future.wait(_pending.toList());
    _check(uid: uid, fence: true);
  }

  @override
  Future<void> clearPersistence() async {
    if (_connection != null && !_terminated) {
      throw NativeFirestoreCodec.invalid('failed-precondition');
    }
    // No local Firestore persistence is created by this transport.
  }

  @override
  Future<void> setLoggingEnabled(bool enabled) async {
    if (enabled) throw NativeFirestoreCodec.invalid('unimplemented');
  }

  @override
  PersistentCacheIndexManagerPlatform? persistentCacheIndexManager() => null;

  @override
  Future<void> terminate() async {
    if (_terminated) return;
    _terminated = true;
    await _connection?.close();
  }

  Future<void> disposeApp(String appName) async {
    final matching = _delegates.entries
        .where((entry) => entry.value.app.name == appName)
        .toList();
    for (final entry in matching) {
      _delegates.remove(entry.key);
      await entry.value.terminate();
    }
  }

  @override
  Future<T?> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) => _runNativeTransaction(this, transactionHandler, timeout, maxAttempts);
}
