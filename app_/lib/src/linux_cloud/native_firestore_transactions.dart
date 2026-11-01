part of 'native_firebase_firestore.dart';

class _NativeBatch extends WriteBatchPlatform {
  _NativeBatch(this.database) : uid = database.session.currentIdentity?.uid;
  final NativeFirebaseFirestore database;
  final String? uid;
  final entries = <write.Write>[];
  bool _committed = false;
  void _add(write.Write value) {
    database._check(uid: uid, fence: true);
    if (_committed || entries.length >= 500) {
      throw NativeFirestoreCodec.invalid('failed-precondition');
    }
    entries.add(value);
  }

  @override
  void set(
    String documentPath,
    Map<String, dynamic> data, [
    SetOptions? options,
  ]) => _add(database.writes.set(documentPath, data, options));
  @override
  void update(String documentPath, Map<String, dynamic> data) =>
      _add(database.writes.update(documentPath, data));
  @override
  void delete(String documentPath) =>
      _add(database.writes.delete(documentPath));
  @override
  Future<void> commit() {
    if (_committed) throw NativeFirestoreCodec.invalid('failed-precondition');
    _committed = true;
    return database.commit(entries, uid);
  }
}

class _NativeTransaction extends TransactionPlatform {
  _NativeTransaction(this.database, this.uid, this.token, this.deadline);
  final NativeFirebaseFirestore database;
  final String? uid;
  final List<int> token;
  final DateTime deadline;
  final entries = <write.Write>[];
  bool active = true;
  Duration remaining() {
    database._check(uid: uid, fence: true);
    if (!active) throw NativeFirestoreCodec.invalid('failed-precondition');
    final value = deadline.difference(DateTime.now());
    if (value <= Duration.zero) {
      throw NativeFirestoreCodec.invalid('deadline-exceeded');
    }
    return value;
  }

  void _add(write.Write value) {
    remaining();
    if (entries.length >= 500) throw NativeFirestoreCodec.invalid();
    entries.add(value);
  }

  @override
  TransactionPlatform set(
    String documentPath,
    Map<String, dynamic> data, [
    SetOptions? options,
  ]) {
    _add(database.writes.set(documentPath, data, options));
    return this;
  }

  @override
  TransactionPlatform update(String documentPath, Map<String, dynamic> data) {
    _add(database.writes.update(documentPath, data));
    return this;
  }

  @override
  TransactionPlatform delete(String documentPath) {
    _add(database.writes.delete(documentPath));
    return this;
  }

  @override
  Future<DocumentSnapshotPlatform> get(String documentPath) async {
    if (entries.isNotEmpty) {
      throw NativeFirestoreCodec.invalid('failed-precondition');
    }
    final name = database.writes.resource(documentPath);
    final rows = await database.connection.invoke(
      (client, options) => client
          .batchGetDocuments(
            rpc.BatchGetDocumentsRequest(
              database: database.connection.database,
              documents: [name],
              transaction: token,
            ),
            options: options,
          )
          .toList(),
      timeout: remaining(),
    );
    remaining();
    final values = rows
        .where((row) => row.hasFound() || row.hasMissing())
        .toList();
    if (values.length != 1 ||
        (values.single.hasFound()
                ? values.single.found.name
                : values.single.missing) !=
            name) {
      throw NativeFirestoreCodec.invalid('data-loss');
    }
    return database.snapshot(
      documentPath,
      values.single.hasFound() ? values.single.found : null,
    );
  }
}

Future<T?> _runNativeTransaction<T>(
  NativeFirebaseFirestore database,
  TransactionHandler<T> handler,
  Duration timeout,
  int maxAttempts,
) async {
  if (timeout <= Duration.zero ||
      timeout > const Duration(minutes: 10) ||
      maxAttempts < 1 ||
      maxAttempts > 100) {
    throw NativeFirestoreCodec.invalid();
  }
  final uid = database.session.currentIdentity?.uid;
  final deadline = DateTime.now().add(timeout);
  Duration remaining() {
    database._check(uid: uid, fence: true);
    final value = deadline.difference(DateTime.now());
    if (value <= Duration.zero) {
      throw NativeFirestoreCodec.invalid('deadline-exceeded');
    }
    return value;
  }

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final connection = database.connection;
    final begin = await connection.invoke(
      (client, options) => client.beginTransaction(
        rpc.BeginTransactionRequest(database: connection.database),
        options: options,
      ),
      timeout: remaining(),
    );
    if (begin.transaction.isEmpty) {
      throw NativeFirestoreCodec.invalid('data-loss');
    }
    final transaction = _NativeTransaction(
      database,
      uid,
      List.of(begin.transaction),
      deadline,
    );
    var committed = false;
    try {
      // The callback can synchronously sign out before its first await. Attach
      // its error handler without another account check leaving it unobserved.
      final callbackTimeout = remaining();
      final result = await Future<T?>.sync(
        () => handler(transaction),
      ).timeout(callbackTimeout);
      transaction.remaining();
      transaction.active = false;
      await connection.invoke(
        (client, options) => client.commit(
          rpc.CommitRequest(
            database: connection.database,
            transaction: transaction.token,
            writes: transaction.entries,
          ),
          options: options,
        ),
        timeout: remaining(),
      );
      committed = true;
      database._check(uid: uid, fence: true);
      return result;
    } on TimeoutException {
      throw NativeFirestoreCodec.invalid('deadline-exceeded');
    } on FirebaseException catch (error) {
      if (error.code != 'aborted' || attempt + 1 >= maxAttempts) rethrow;
    } finally {
      transaction.active = false;
      if (!committed &&
          database.session.currentIdentity?.uid == uid &&
          !database._terminated) {
        try {
          await connection.invoke(
            (client, options) => client.rollback(
              rpc.RollbackRequest(
                database: connection.database,
                transaction: transaction.token,
              ),
              options: options,
            ),
            timeout: const Duration(seconds: 3),
          );
        } catch (_) {
          /* Original transaction failure takes precedence. */
        }
      }
    }
    final backoff = Duration(
      milliseconds:
          min(1000, 50 * (1 << min(attempt, 4))) + Random.secure().nextInt(50),
    );
    if (backoff < remaining()) await Future<void>.delayed(backoff);
  }
  throw NativeFirestoreCodec.invalid('aborted');
}
