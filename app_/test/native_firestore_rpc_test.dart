import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:cloud_storage/src/linux_cloud/firestore_wire/google/firestore/v1/document.pb.dart'
    as wire;
import 'package:cloud_storage/src/linux_cloud/firestore_wire/google/firestore/v1/firestore.pbgrpc.dart'
    as rpc;
import 'package:cloud_storage/src/linux_cloud/firestore_wire/google/firestore/v1/write.pb.dart'
    as write;
import 'package:cloud_storage/src/linux_cloud/native_firestore_rpc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'support/native_cloud_fixture.dart';

class _Connection {
  _Connection(this.request, this.responses, this.metadata);
  final rpc.ListenRequest request;
  final StreamController<rpc.ListenResponse> responses;
  final Map<String, String> metadata;
  final cancelled = Completer<void>();
  void document(wire.Document document) => responses.add(
    rpc.ListenResponse(
      documentChange: write.DocumentChange(document: document, targetIds: [1]),
    ),
  );
  void current() => responses.add(
    rpc.ListenResponse(
      targetChange: rpc.TargetChange(
        targetChangeType: rpc.TargetChange_TargetChangeType.CURRENT,
        targetIds: [1],
      ),
    ),
  );
  void checkpoint(int token) => responses.add(
    rpc.ListenResponse(
      targetChange: rpc.TargetChange(
        targetChangeType: rpc.TargetChange_TargetChangeType.NO_CHANGE,
        readTime: Timestamp(seconds: Int64(100 + token)),
        resumeToken: [token],
      ),
    ),
  );
  void reset() => responses.add(
    rpc.ListenResponse(
      targetChange: rpc.TargetChange(
        targetChangeType: rpc.TargetChange_TargetChangeType.RESET,
        targetIds: [1],
      ),
    ),
  );
}

class _Service extends rpc.FirestoreServiceBase {
  final opened = StreamController<_Connection>();
  Future<wire.Document> Function(grpc.ServiceCall, rpc.GetDocumentRequest)? get;
  @override
  Future<wire.Document> getDocument(
    grpc.ServiceCall call,
    rpc.GetDocumentRequest request,
  ) async => get == null
      ? wire.Document(name: request.name)
      : await get!(call, request);
  @override
  Stream<rpc.ListenResponse> listen(
    grpc.ServiceCall call,
    Stream<rpc.ListenRequest> requests,
  ) {
    final responses = StreamController<rpc.ListenResponse>();
    _Connection? connection;
    final subscription = requests.listen((request) {
      connection = _Connection(
        request,
        responses,
        Map.from(call.clientMetadata ?? {}),
      );
      opened.add(connection!);
    });
    responses.onCancel = () async {
      await subscription.cancel();
      if (connection case final value?) {
        if (!value.cancelled.isCompleted) value.cancelled.complete();
      }
    };
    return responses.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unused test RPC');
}

Matcher _code(String code) =>
    isA<FirebaseException>().having((e) => e.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativeCloudFixture fixture;
  late _Service service;
  late grpc.Server server;
  late NativeFirestoreRpc database;
  late StreamQueue<_Connection> opened;
  setUp(() async {
    fixture = NativeCloudFixture();
    await fixture.initialize(emulator: true);
    await fixture.auth.signInWithEmailAndPassword(
      email: 'user@example.test',
      password: 'synthetic-password',
    );
    service = _Service();
    opened = StreamQueue(service.opened.stream);
    server = grpc.Server.create(services: [service]);
    await server.serve(address: InternetAddress.loopbackIPv4, port: 0);
    database = NativeFirestoreRpc(
      session: fixture.sessions[fixture.app.name]!,
      apiKey: 'synthetic-public-key',
      emulatorPort: server.port!,
    );
  });
  tearDown(() async {
    await database.close();
    await server.shutdown();
    await opened.cancel();
    await service.opened.close();
    await fixture.dispose();
  });
  rpc.Target target() => rpc.Target(
    documents: rpc.Target_DocumentsTarget(
      documents: ['${database.documentsRoot}/files/a'],
    ),
  );
  wire.Document document(String id, int value) => wire.Document(
    name: '${database.documentsRoot}/files/$id',
    fields: [MapEntry('value', wire.Value(integerValue: Int64(value)))],
  );
  Future<_Connection> connection() =>
      opened.next.timeout(const Duration(seconds: 10));

  test(
    'unary RPC sends only the signed-in user token and its own database resource',
    () async {
      service.get = (call, request) async {
        final metadata = call.clientMetadata!;
        expect(
          NativeCloudFixture.tokenUid(metadata['authorization']!.substring(7)),
          'existing-web-customer',
        );
        expect(metadata['google-cloud-resource-prefix'], database.database);
        expect(metadata['x-goog-api-key'], 'synthetic-public-key');
        return document('a', 7);
      };
      final result = await database.invoke(
        (client, options) => client.getDocument(
          rpc.GetDocumentRequest(name: '${database.documentsRoot}/files/a'),
          options: options,
        ),
      );
      expect(result.fields['value']!.integerValue.toInt(), 7);
    },
  );

  test(
    'permission errors keep their category without returning server diagnostics',
    () async {
      service.get = (_, _) async => throw const grpc.GrpcError.permissionDenied(
        'private provider diagnostic token',
      );
      try {
        await database.invoke(
          (client, options) => client.getDocument(
            rpc.GetDocumentRequest(name: '${database.documentsRoot}/files/a'),
            options: options,
          ),
        );
        fail('Expected denial');
      } on FirebaseException catch (error) {
        expect(error.code, 'permission-denied');
        expect(error.message, isNot(contains('private provider diagnostic')));
      }
    },
  );

  test(
    'watch publishes only a complete initial snapshot and reset can publish an empty result',
    () async {
      final events = <List<wire.Document>>[];
      final subscription = database.watch(target()).listen(events.add);
      final first = await connection();
      first.document(document('a', 7));
      first.current();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events, isEmpty);
      first.checkpoint(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events.single.single.fields['value']!.integerValue.toInt(), 7);
      expect(events.single.single.isFrozen, true);
      first.reset();
      first.current();
      first.checkpoint(2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events.last, isEmpty);
      await subscription.cancel();
      await first.cancelled.future.timeout(const Duration(seconds: 10));
    },
  );

  test(
    'reconnect resumes the last complete snapshot and discards partial changes',
    () async {
      final snapshots = StreamQueue(database.watch(target()));
      addTearDown(snapshots.cancel);
      final initialSnapshot = snapshots.next.timeout(
        const Duration(seconds: 10),
      );
      final first = await connection();
      first.document(document('a', 7));
      first.current();
      first.checkpoint(1);
      expect(
        (await initialSnapshot).single.fields['value']!.integerValue.toInt(),
        7,
      );
      final nextSnapshot = snapshots.next.timeout(const Duration(seconds: 10));
      first.document(document('a', 999));
      first.responses.addError(
        const grpc.GrpcError.unavailable('synthetic disconnect'),
      );
      unawaited(first.responses.close());
      final second = await connection();
      expect(second.request.addTarget.resumeToken, [1]);
      second.document(document('b', 2));
      second.current();
      second.checkpoint(2);
      final values = await nextSnapshot;
      expect(values.map((doc) => doc.fields['value']!.integerValue.toInt()), [
        7,
        2,
      ]);
    },
  );

  test(
    'sign-out cancels a watcher and prevents queued old-account data from being delivered',
    () async {
      final documents = <String>[];
      final error = Completer<Object>();
      final subscription = database
          .watch(target())
          .listen(
            (docs) => documents.addAll(docs.map((doc) => doc.name)),
            onError: (Object value) {
              if (!error.isCompleted) error.complete(value);
            },
          );
      final first = await connection();
      first.document(document('private-after-signout', 1));
      first.current();
      first.checkpoint(1);
      await fixture.auth.signOut();
      expect(
        await error.future.timeout(const Duration(seconds: 10)),
        _code('cancelled'),
      );
      expect(documents, isEmpty);
      await subscription.cancel();
    },
  );

  test('closing a paused listener does not block database shutdown', () async {
    final subscription = database.watch(target()).listen((_) {});
    final first = await connection();
    subscription.pause();
    await database.close().timeout(const Duration(seconds: 5));
    await first.cancelled.future.timeout(const Duration(seconds: 5));
    await subscription.cancel();
  });

  test(
    'existence mismatch restarts a full target and can replace old data with an empty snapshot',
    () async {
      final snapshots = StreamQueue(database.watch(target()));
      addTearDown(snapshots.cancel);
      final initial = snapshots.next;
      final first = await connection();
      first.document(document('a', 1));
      first.current();
      first.checkpoint(1);
      expect(await initial, hasLength(1));
      final replacement = snapshots.next;
      first.responses.add(
        rpc.ListenResponse(
          filter: write.ExistenceFilter(targetId: 1, count: 0),
        ),
      );
      final second = await connection();
      expect(second.request.addTarget.resumeToken, isEmpty);
      second.current();
      second.checkpoint(2);
      expect(await replacement.timeout(const Duration(seconds: 5)), isEmpty);
    },
  );

  test('database shutdown terminates an unfinished unary request', () async {
    final started = Completer<void>();
    final response = Completer<wire.Document>();
    service.get = (_, _) {
      started.complete();
      return response.future;
    };
    final request = database.invoke(
      (client, options) => client.getDocument(
        rpc.GetDocumentRequest(name: '${database.documentsRoot}/files/a'),
        options: options,
      ),
    );
    final rejected = expectLater(request, throwsA(_code('cancelled')));
    await started.future;
    await database.close().timeout(const Duration(seconds: 5));
    await rejected;
    response.complete(document('a', 1));
  });

  test('a cold listener binds the account at subscription time', () async {
    final stream = database.watch(target());
    await fixture.auth.signOut();
    fixture.nextSignInUid = 'next-customer';
    await fixture.auth.signInWithEmailAndPassword(
      email: 'next@example.test',
      password: 'synthetic-password',
    );
    final queue = StreamQueue(stream);
    addTearDown(queue.cancel);
    final pending = queue.next;
    final live = await connection();
    expect(
      NativeCloudFixture.tokenUid(live.metadata['authorization']!.substring(7)),
      'next-customer',
    );
    live.current();
    live.checkpoint(1);
    expect(await pending, isEmpty);
  });

  test(
    'a unary result cannot be delivered after its account signs out',
    () async {
      final started = Completer<void>();
      final response = Completer<wire.Document>();
      service.get = (_, _) {
        started.complete();
        return response.future;
      };
      final pending = database.invoke(
        (client, options) => client.getDocument(
          rpc.GetDocumentRequest(name: '${database.documentsRoot}/files/a'),
          options: options,
        ),
      );
      final rejected = expectLater(pending, throwsA(_code('cancelled')));
      await started.future;
      await fixture.auth.signOut();
      response.complete(document('a', 1));
      await rejected;
    },
  );
}
