import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as platform;
import 'package:cloud_storage/src/linux_cloud/firestore_wire/google/firestore/v1/document.pb.dart'
    as wire;
import 'package:cloud_storage/src/linux_cloud/firestore_wire/google/firestore/v1/firestore.pbgrpc.dart'
    as rpc;
import 'package:cloud_storage/src/linux_cloud/firestore_wire/google/firestore/v1/write.pb.dart'
    as write;
import 'package:cloud_storage/src/linux_cloud/native_firebase_firestore.dart';
import 'package:cloud_storage/src/linux_cloud/native_firestore_codec.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as proto;

import 'support/native_cloud_fixture.dart';

class _LiveQuery {
  _LiveQuery(this.request, this.responses);
  final rpc.ListenRequest request;
  final StreamController<rpc.ListenResponse> responses;
  void document(wire.Document value) => responses.add(
    rpc.ListenResponse(
      documentChange: write.DocumentChange(document: value, targetIds: [1]),
    ),
  );
  void remove(String name) => responses.add(
    rpc.ListenResponse(
      documentDelete: write.DocumentDelete(
        document: name,
        removedTargetIds: [1],
      ),
    ),
  );
  void checkpoint(int sequence) {
    responses.add(
      rpc.ListenResponse(
        targetChange: rpc.TargetChange(
          targetChangeType: rpc.TargetChange_TargetChangeType.CURRENT,
          targetIds: [1],
        ),
      ),
    );
    responses.add(
      rpc.ListenResponse(
        targetChange: rpc.TargetChange(
          targetChangeType: rpc.TargetChange_TargetChangeType.NO_CHANGE,
          readTime: proto.Timestamp(seconds: Int64(sequence)),
          resumeToken: [sequence],
        ),
      ),
    );
  }
}

/// A protocol fixture, not a Firestore emulator: captures requests and supplies
/// explicit server results so the public SDK's native adaptation is exercised.
class _ProtocolService extends rpc.FirestoreServiceBase {
  final documents = <String, wire.Document>{};
  final commits = <rpc.CommitRequest>[];
  final queries = <rpc.RunQueryRequest>[];
  final reads = <rpc.BatchGetDocumentsRequest>[];
  final rollbacks = <rpc.RollbackRequest>[];
  final opened = StreamController<_LiveQuery>();
  List<wire.Document> queryResult = [];
  int begins = 0;
  int abortCommits = 0;
  int? getError;
  Future<void> Function()? beforeCommit;
  @override
  Future<wire.Document> getDocument(
    grpc.ServiceCall call,
    rpc.GetDocumentRequest request,
  ) async {
    if (getError != null) {
      throw grpc.GrpcError.custom(getError!, 'private-provider-message');
    }
    final value = documents[request.name];
    if (value == null) {
      throw const grpc.GrpcError.notFound('private-provider-message');
    }
    return value;
  }

  @override
  Future<rpc.CommitResponse> commit(
    grpc.ServiceCall call,
    rpc.CommitRequest request,
  ) async {
    commits.add(request);
    await beforeCommit?.call();
    if (abortCommits > 0) {
      abortCommits--;
      throw const grpc.GrpcError.aborted('private-provider-message');
    }
    return rpc.CommitResponse();
  }

  @override
  Stream<rpc.RunQueryResponse> runQuery(
    grpc.ServiceCall call,
    rpc.RunQueryRequest request,
  ) async* {
    queries.add(request);
    for (final document in queryResult) {
      yield rpc.RunQueryResponse(document: document);
    }
    yield rpc.RunQueryResponse(readTime: proto.Timestamp(seconds: Int64(1)));
  }

  @override
  Future<rpc.BeginTransactionResponse> beginTransaction(
    grpc.ServiceCall call,
    rpc.BeginTransactionRequest request,
  ) async => rpc.BeginTransactionResponse(transaction: [++begins]);
  @override
  Stream<rpc.BatchGetDocumentsResponse> batchGetDocuments(
    grpc.ServiceCall call,
    rpc.BatchGetDocumentsRequest request,
  ) async* {
    reads.add(request);
    for (final name in request.documents) {
      yield documents.containsKey(name)
          ? rpc.BatchGetDocumentsResponse(found: documents[name])
          : rpc.BatchGetDocumentsResponse(missing: name);
    }
  }

  @override
  Future<Empty> rollback(
    grpc.ServiceCall call,
    rpc.RollbackRequest request,
  ) async {
    rollbacks.add(request);
    return Empty();
  }

  @override
  Stream<rpc.ListenResponse> listen(
    grpc.ServiceCall call,
    Stream<rpc.ListenRequest> requests,
  ) {
    final responses = StreamController<rpc.ListenResponse>();
    final subscription = requests.listen(
      (request) => opened.add(_LiveQuery(request, responses)),
    );
    responses.onCancel = subscription.cancel;
    return responses.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unused protocol fixture RPC');
}

Matcher _code(String code) =>
    isA<FirebaseException>().having((error) => error.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativeCloudFixture fixture;
  late _ProtocolService service;
  late grpc.Server server;
  late NativeFirebaseFirestore root;
  late FirebaseFirestore database;
  late StreamQueue<_LiveQuery> opened;
  final previousFactory = platform.FieldValueFactoryPlatform.instance;
  setUpAll(() {
    platform.FieldValueFactoryPlatform.instance = NativeFieldValueFactory();
  });
  tearDownAll(() {
    platform.FieldValueFactoryPlatform.instance = previousFactory;
  });
  setUp(() async {
    fixture = NativeCloudFixture();
    await fixture.initialize(emulator: true);
    await fixture.auth.signInWithEmailAndPassword(
      email: 'user@example.test',
      password: 'synthetic-password',
    );
    service = _ProtocolService();
    opened = StreamQueue(service.opened.stream);
    server = grpc.Server.create(services: [service]);
    await server.serve(address: InternetAddress.loopbackIPv4, port: 0);
    root = NativeFirebaseFirestore(
      sessionFor: (name) => fixture.sessions[name]!,
      emulatorPort: server.port!,
    );
    platform.FirebaseFirestorePlatform.instance = root;
    database = FirebaseFirestore.instanceFor(app: fixture.app);
  });
  tearDown(() async {
    await root.disposeApp(fixture.app.name);
    await server.shutdown();
    await opened.cancel();
    await service.opened.close();
    await fixture.dispose();
  });
  String name(String path) =>
      'projects/${fixture.app.options.projectId}/databases/(default)/documents/$path';
  wire.Document document(String path, int rank) => wire.Document(
    name: name(path),
    fields: [MapEntry('rank', wire.Value(integerValue: Int64(rank)))],
  );
  Future<_LiveQuery> connection() =>
      opened.next.timeout(const Duration(seconds: 10));

  test(
    'public document API preserves types, references and missing documents',
    () async {
      final value = document('files/a', 9);
      value.fields['owner'] = wire.Value(
        referenceValue: name('users/existing-web-customer'),
      );
      service.documents[value.name] = value;
      final snapshot = await database.doc('files/a').get();
      expect(snapshot.exists, true);
      expect(snapshot.data()!['rank'], 9);
      expect(
        (snapshot.data()!['owner'] as DocumentReference).path,
        'users/existing-web-customer',
      );
      expect(snapshot.metadata.isFromCache, false);
      final missing = await database.doc('files/missing').get();
      expect(missing.exists, false);
      expect(missing.data(), null);
    },
  );

  test(
    'public writes translate sentinels, literal field paths and batches',
    () async {
      final reference = database.doc('files/a');
      await reference.set({
        'rank': FieldValue.increment(3),
        'owner': database.doc('users/one'),
      }, SetOptions(merge: true));
      expect(
        service
            .commits
            .single
            .writes
            .single
            .updateTransforms
            .single
            .increment
            .integerValue
            .toInt(),
        3,
      );
      expect(
        service
            .commits
            .single
            .writes
            .single
            .update
            .fields['owner']!
            .referenceValue,
        name('users/one'),
      );
      final batch = database.batch();
      batch.update(reference, {
        'obsolete': FieldValue.delete(),
        'profile.name': 'New',
      });
      batch.delete(database.doc('files/b'));
      await batch.commit();
      final entries = service.commits.last.writes;
      expect(entries, hasLength(2));
      expect(entries.first.currentDocument.exists, true);
      expect(
        entries.first.updateMask.fieldPaths,
        containsAll(['obsolete', 'profile.name']),
      );
      expect(entries.last.delete, name('files/b'));
      await expectLater(Future<void>.sync(batch.commit), throwsA(anything));
    },
  );

  test(
    'collection references retain query defaults, parents and random IDs',
    () async {
      final collection = database.collection('users/one/files');
      expect(collection.parent!.path, 'users/one');
      final generated = List.generate(100, (_) => collection.doc().id);
      expect(generated.toSet(), hasLength(100));
      expect(
        generated.every((id) => RegExp(r'^[a-zA-Z0-9]{20}$').hasMatch(id)),
        true,
      );
      expect(database.collection('files').parent, null);
      await collection
          .where('rank', isGreaterThan: 2)
          .orderBy('rank')
          .limit(3)
          .get();
      final request = service.queries.single;
      expect(request.parent, name('users/one'));
      expect(request.structuredQuery.limit.value, 3);
      expect(
        request.structuredQuery.where.fieldFilter.field_1.fieldPath,
        'rank',
      );
    },
  );

  test(
    'snapshot cursors and limitToLast preserve the public query ordering',
    () async {
      final value = document('files/a', 5);
      service.documents[value.name] = value;
      final cursor = await database.doc('files/a').get();
      service.queryResult = [document('files/d', 9), document('files/c', 8)];
      final result = await database
          .collection('files')
          .orderBy('rank')
          .startAfterDocument(cursor)
          .limitToLast(2)
          .get();
      expect(result.docs.map((doc) => doc.id), ['c', 'd']);
      final query = service.queries.single.structuredQuery;
      expect(query.endAt.values.last.referenceValue, name('files/a'));
      expect(query.endAt.before, true);
    },
  );

  test(
    'live query changes can be applied sequentially with their advertised indices',
    () async {
      final queue = StreamQueue(
        database.collection('files').orderBy('rank').snapshots(),
      );
      addTearDown(queue.cancel);
      final initialFuture = queue.next;
      final live = await connection();
      live.document(document('files/a', 1));
      live.document(document('files/b', 2));
      live.document(document('files/c', 3));
      live.checkpoint(1);
      final initial = await initialFuture;
      final ids = <String>[];
      void apply(QuerySnapshot<Map<String, dynamic>> snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.oldIndex >= 0) {
            expect(ids.removeAt(change.oldIndex), change.doc.id);
          }
          if (change.newIndex >= 0) ids.insert(change.newIndex, change.doc.id);
        }
        expect(ids, snapshot.docs.map((doc) => doc.id).toList());
      }

      apply(initial);
      final nextFuture = queue.next;
      live.remove(name('files/b'));
      live.document(document('files/a', 7));
      live.document(document('files/c', 0));
      live.document(document('files/d', 4));
      live.checkpoint(2);
      final next = await nextFuture;
      apply(next);
      expect(ids, ['c', 'd', 'a']);
      expect(
        next.docChanges.where(
          (change) => change.type == DocumentChangeType.modified,
        ),
        hasLength(2),
      );
    },
  );

  test(
    'document listener reports a missing document after a complete checkpoint',
    () async {
      final queue = StreamQueue(database.doc('files/missing').snapshots());
      addTearDown(queue.cancel);
      final future = queue.next;
      final live = await connection();
      expect(live.request.addTarget.documents.documents, [
        name('files/missing'),
      ]);
      live.checkpoint(1);
      expect((await future).exists, false);
    },
  );

  test('a batch cannot move writes into a newly signed-in account', () async {
    final batch = database.batch()..set(database.doc('files/a'), {'rank': 1});
    await fixture.auth.signOut();
    fixture.nextSignInUid = 'another-customer';
    await fixture.auth.signInWithEmailAndPassword(
      email: 'other@example.test',
      password: 'synthetic-password',
    );
    await expectLater(
      Future<void>.sync(batch.commit),
      throwsA(_code('cancelled')),
    );
    expect(service.commits, isEmpty);
  });

  test(
    'transaction retries aborted commits with fresh server transactions',
    () async {
      service.abortCommits = 1;
      final stored = document('files/a', 10);
      service.documents[stored.name] = stored;
      var attempts = 0;
      final result = await database.runTransaction<int>((transaction) async {
        attempts++;
        final snapshot = await transaction.get(database.doc('files/a'));
        transaction.update(snapshot.reference, {
          'rank': (snapshot.data()!['rank'] as int) + 1,
        });
        return 11;
      });
      expect(result, 11);
      expect(attempts, 2);
      expect(service.begins, 2);
      expect(service.reads.map((read) => read.transaction.single), [1, 2]);
      expect(service.commits.map((commit) => commit.transaction.single), [
        1,
        2,
      ]);
      expect(service.rollbacks, hasLength(1));
    },
  );

  test(
    'transactions preserve missing reads and reject reading after writes',
    () async {
      await expectLater(
        database.runTransaction((transaction) async {
          final missing = await transaction.get(database.doc('files/missing'));
          expect(missing.exists, false);
          transaction.set(missing.reference, {'rank': 1});
          await transaction.get(database.doc('files/other'));
        }),
        throwsA(_code('failed-precondition')),
      );
      expect(service.commits, isEmpty);
      expect(service.rollbacks, hasLength(1));
    },
  );

  test(
    'transaction timeout prevents a late callback from committing',
    () async {
      final gate = Completer<void>();
      final finished = Completer<void>();
      Object? lateError;
      final result = database.runTransaction((transaction) async {
        await gate.future;
        try {
          transaction.set(database.doc('files/a'), {'rank': 1});
        } catch (error) {
          lateError = error;
        }
        finished.complete();
      }, timeout: const Duration(milliseconds: 150));
      await expectLater(result, throwsA(_code('deadline-exceeded')));
      gate.complete();
      await finished.future;
      expect(lateError, _code('failed-precondition'));
      expect(service.commits, isEmpty);
    },
  );

  test(
    'transaction account changes cancel its writes without switching ownership',
    () async {
      await expectLater(
        database.runTransaction((transaction) async {
          await fixture.auth.signOut();
          transaction.set(database.doc('files/a'), {'rank': 1});
        }),
        throwsA(_code('cancelled')),
      );
      expect(service.commits, isEmpty);
    },
  );

  test(
    'permission denial is neither an empty document nor a provider-message leak',
    () async {
      service.getError = grpc.StatusCode.permissionDenied;
      try {
        await database.doc('files/private').get();
        fail('Expected denial');
      } on FirebaseException catch (error) {
        expect(error.code, 'permission-denied');
        expect(error.toString(), isNot(contains('private-provider-message')));
      }
    },
  );

  test(
    'plaintext persistence and arbitrary endpoints cannot be enabled',
    () async {
      expect(
        () => database.settings = const Settings(persistenceEnabled: true),
        throwsA(_code('failed-precondition')),
      );
      expect(
        () => database.settings = const Settings(
          host: 'other.example',
          sslEnabled: false,
        ),
        throwsA(_code('failed-precondition')),
      );
      await expectLater(
        database.doc('files/a').get(const GetOptions(source: Source.cache)),
        throwsA(_code('unavailable')),
      );
    },
  );
}
