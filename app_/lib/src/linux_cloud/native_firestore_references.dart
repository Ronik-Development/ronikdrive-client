part of 'native_firebase_firestore.dart';

class _NativeDocument extends DocumentReferencePlatform {
  _NativeDocument(this.database, String path) : super(database, path);
  final NativeFirebaseFirestore database;

  @override
  Future<DocumentSnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async {
    database.requireServer(options);
    try {
      final result = await database.connection.invoke(
        (client, callOptions) => client.getDocument(
          rpc.GetDocumentRequest(name: database.writes.resource(path)),
          options: callOptions,
        ),
      );
      return database.snapshot(path, result);
    } on FirebaseException catch (error) {
      if (error.code != 'not-found') rethrow;
      return database.snapshot(path, null);
    }
  }

  @override
  Stream<DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) => database
      .watch(
        rpc.Target(
          documents: rpc.Target_DocumentsTarget(
            documents: [database.writes.resource(path)],
          ),
        ),
        listenSource,
      )
      .distinct(
        (a, b) =>
            a.length == b.length &&
            (a.isEmpty || _sameFields(a.single, b.single)),
      )
      .map((documents) {
        if (documents.length > 1) {
          throw NativeFirestoreCodec.invalid('data-loss');
        }
        return database.snapshot(
          path,
          documents.isEmpty ? null : documents.single,
        );
      });

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      database.commit([
        database.writes.set(path, data, options),
      ], database.session.currentIdentity?.uid);
  @override
  Future<void> update(Map<FieldPath, dynamic> data) => database.commit([
    database.writes.update(path, data),
  ], database.session.currentIdentity?.uid);
  @override
  Future<void> delete() => database.commit([
    database.writes.delete(path),
  ], database.session.currentIdentity?.uid);
}

bool _sameFields(wire.Document a, wire.Document b) =>
    a.name == b.name &&
    wire.MapValue(fields: a.fields.entries) ==
        wire.MapValue(fields: b.fields.entries);

class _ScopedNativeSnapshot {
  _ScopedNativeSnapshot(this.uid, this.snapshot);
  final String? uid;
  final QuerySnapshotPlatform snapshot;
}

class _NativeQuery extends QueryPlatform {
  _NativeQuery(this.database, this.spec) : super(database, spec.parameters);
  final NativeFirebaseFirestore database;
  final NativeFirestoreQuerySpec spec;
  @override
  bool get isCollectionGroupQuery => spec.collectionGroup;
  _NativeQuery _copy(Map<String, dynamic> changes) =>
      _NativeQuery(database, spec.copy(changes));
  @override
  QueryPlatform where(List<List<dynamic>> conditions) =>
      _copy({'where': conditions.map((row) => List<dynamic>.of(row)).toList()});
  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) =>
      _copy({'orderBy': orders.map((row) => List<dynamic>.of(row)).toList()});
  @override
  QueryPlatform limit(int limit) =>
      _copy({'limit': limit, 'limitToLast': null});
  @override
  QueryPlatform limitToLast(int limit) =>
      _copy({'limitToLast': limit, 'limit': null});
  @override
  QueryPlatform startAt(Iterable<dynamic> fields) =>
      _copy({'startAt': fields.toList(), 'startAfter': null});
  @override
  QueryPlatform startAfter(Iterable<dynamic> fields) =>
      _copy({'startAfter': fields.toList(), 'startAt': null});
  @override
  QueryPlatform endAt(Iterable<dynamic> fields) =>
      _copy({'endAt': fields.toList(), 'endBefore': null});
  @override
  QueryPlatform endBefore(Iterable<dynamic> fields) =>
      _copy({'endBefore': fields.toList(), 'endAt': null});
  @override
  QueryPlatform startAtDocument(
    Iterable<dynamic> orders,
    Iterable<dynamic> values,
  ) => _copy({
    'orderBy': orders.toList(),
    'startAt': values.toList(),
    'startAfter': null,
  });
  @override
  QueryPlatform startAfterDocument(
    List<dynamic> orders,
    List<dynamic> values,
  ) => _copy({'orderBy': orders, 'startAfter': values, 'startAt': null});
  @override
  QueryPlatform endAtDocument(List<dynamic> orders, List<dynamic> values) =>
      _copy({'orderBy': orders, 'endAt': values, 'endBefore': null});
  @override
  QueryPlatform endBeforeDocument(
    Iterable<dynamic> orders,
    Iterable<dynamic> values,
  ) => _copy({
    'orderBy': orders.toList(),
    'endBefore': values.toList(),
    'endAt': null,
  });

  QuerySnapshotPlatform _snapshot(
    List<wire.Document> previous,
    List<wire.Document> documents,
  ) {
    final sorted = spec.sorted(documents);
    final current = previous.toList();
    final changes = <DocumentChangePlatform>[];
    final names = sorted.map((entry) => entry.name).toSet();
    for (var index = current.length - 1; index >= 0; index--) {
      final removed = current[index];
      if (!names.contains(removed.name)) {
        current.removeAt(index);
        changes.add(
          DocumentChangePlatform(
            DocumentChangeType.removed,
            index,
            -1,
            database.snapshot(database.documentPath(removed), removed),
          ),
        );
      }
    }
    final old = {for (final document in previous) document.name: document};
    for (final document in sorted) {
      final prior = old[document.name];
      if (prior != null && _sameFields(prior, document)) continue;
      final oldIndex = current.indexWhere(
        (entry) => entry.name == document.name,
      );
      if (oldIndex >= 0) current.removeAt(oldIndex);
      current.add(document);
      final reordered = spec.sorted(current);
      final newIndex = reordered.indexWhere(
        (entry) => entry.name == document.name,
      );
      current
        ..clear()
        ..addAll(reordered);
      changes.add(
        DocumentChangePlatform(
          prior == null
              ? DocumentChangeType.added
              : DocumentChangeType.modified,
          oldIndex,
          newIndex,
          database.snapshot(database.documentPath(document), document),
        ),
      );
    }
    return QuerySnapshotPlatform(
      sorted
          .map(
            (document) =>
                database.snapshot(database.documentPath(document), document),
          )
          .toList(),
      changes,
      SnapshotMetadataPlatform(false, false),
    );
  }

  @override
  Future<QuerySnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async {
    database.requireServer(options);
    final structuredQuery = spec.build();
    final rows = await database.connection.invoke(
      (client, callOptions) => client
          .runQuery(
            rpc.RunQueryRequest(
              parent: spec.parent,
              structuredQuery: structuredQuery,
            ),
            options: callOptions,
          )
          .toList(),
    );
    return _snapshot(
      [],
      rows
          .where((row) => row.hasDocument())
          .map((row) => row.document)
          .toList(),
    );
  }

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) {
    final query = rpc.Target(
      query: rpc.Target_QueryTarget(
        parent: spec.parent,
        structuredQuery: spec.build(),
      ),
    );
    // State belongs to each subscription, never to the reusable query object.
    return Stream<_ScopedNativeSnapshot>.multi((controller) {
      final uid = database.session.currentIdentity?.uid;
      var previous = <wire.Document>[];
      var initial = true;
      final subscription = database
          .watch(query, listenSource)
          .listen(
            (documents) {
              try {
                final snapshot = _snapshot(previous, documents);
                previous = spec.sorted(documents);
                if (initial || snapshot.docChanges.isNotEmpty) {
                  controller.add(_ScopedNativeSnapshot(uid, snapshot));
                }
                initial = false;
              } catch (error, stack) {
                controller.addError(error, stack);
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = subscription.cancel;
      controller.onPause = subscription.pause;
      controller.onResume = subscription.resume;
    }).map((event) {
      // The multi-stream controller can queue a completed snapshot while its
      // consumer is paused. Check its owner again when the event is delivered.
      database._check(uid: event.uid, fence: true);
      return event.snapshot;
    });
  }
}

// Like FlutterFire's collection adapter, this inherits the complete query
// implementation while satisfying the collection platform contract.
// ignore: avoid_implementing_value_types
class _NativeCollection extends _NativeQuery
    implements CollectionReferencePlatform {
  _NativeCollection(NativeFirebaseFirestore database, String path)
    : super(
        database,
        NativeFirestoreQuerySpec(codec: database.codec, path: path),
      );
  @override
  String get path => spec.path;
  @override
  String get id => path.split('/').last;
  @override
  DocumentReferencePlatform? get parent => path.contains('/')
      ? database.doc(path.substring(0, path.lastIndexOf('/')))
      : null;
  static final _random = Random.secure();
  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  @override
  DocumentReferencePlatform doc([String? path]) => database.doc(
    '${this.path}/${path ?? List.generate(20, (_) => _alphabet[_random.nextInt(_alphabet.length)]).join()}',
  );
}
