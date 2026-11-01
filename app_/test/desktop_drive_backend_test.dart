import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_storage/src/storage/wasabi_storage_service.dart';
import 'package:cloud_storage/src/desktop_drive/firestore_drive_backend.dart';
import 'package:cloud_storage/src/desktop_drive/drive_provider_protocol.dart';
import 'package:cloud_storage/src/security/encryption_service.dart';
import 'package:cloud_storage/src/storage/cloud_storage_provider.dart';
import 'package:cloud_storage/src/storage/transfer_journal.dart';
import 'package:cloud_storage/src/storage/upload_metadata_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

class ReadStorage implements CloudStorageProvider {
  Stream<List<int>> Function() source = () => Stream.value([1, 2, 3]);
  @override
  Future<Stream<List<int>>> download({
    required String objectKey,
    SecretKey? encryptionKey,
    bool preferProxy = false,
    int? maxPlaintextBytes,
  }) async {
    expect(encryptionKey, isNotNull);
    return source();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnusedJournal implements TransferJournal {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnusedMetadata implements UploadMetadataService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UploadStorage extends ReadStorage {
  int uploads = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #upload) {
      uploads++;
      return Future.value(
        WasabiUploadResult(
          objectKey: invocation.namedArguments[#objectKey] as String,
          bucket: 'test',
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

class MemoryJournal extends UnusedJournal {
  @override
  Map<String, dynamic>? uploadCheckpoint(String transferId) => null;
  @override
  bool get storageAvailable => true;
  @override
  List<TransferJournalEntry> get entries => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class RecordingMetadata extends UnusedMetadata {
  RecordingMetadata(this.db);
  final FakeFirebaseFirestore db;
  int commits = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #buildRecordUploadedFilePayload) {
      final args = invocation.namedArguments;
      return <String, dynamic>{
        'uid': 'user',
        'fileName': args[#objectKey],
        'sizeBytes': args[#size],
        'encryptedName': args[#encryptedName],
        'encryptionMode': 'standard',
        'contentEncryption': 'standard',
        'storageLayout': 'single',
        'lifecycleState': 'active',
        'revision': 2,
        if (args[#supersedesFileId] != null)
          'versionGroupId': args[#supersedesFileId],
      };
    }
    return super.noSuchMethod(invocation);
  }

  @override
  Future<void> recordUploadedFilePayload(Map<String, dynamic> payload) async {
    commits++;
    if (payload['versionGroupId'] != null) {
      await db.collection('files').doc(payload['versionGroupId']).update({
        'lifecycleState': 'version',
      });
    }
    await db.collection('files').doc('uploaded').set(payload);
    throw StateError('Response lost after successful commit');
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreDriveBackend backend;
  late ReadStorage storage;
  late Map<String, dynamic> standard;
  var authorized = true;
  setUp(() async {
    db = FakeFirebaseFirestore();
    storage = ReadStorage();
    authorized = true;
    final key = SecretKey(List.filled(32, 7));
    standard = {
      'uid': 'user',
      'fileName': 'opaque/objects/test.bin',
      'encryptedName': await EncryptionService.instance.encryptFileName(
        'Test.txt',
        key,
      ),
      'sizeBytes': 3,
      'encryptionMode': 'standard',
      'contentEncryption': 'standard',
      'storageLayout': 'single',
      'revision': 1,
      'lifecycleState': 'active',
    };
    await db.collection('files').doc('file').set(standard);
    backend = FirestoreDriveBackend(
      firestore: db,
      auth: MockFirebaseAuth(mockUser: MockUser(uid: 'user'), signedIn: true),
      uid: 'user',
      key: key,
      storage: storage,
      ownerPrefix: 'opaque',
      journal: UnusedJournal(),
      metadata: UnusedMetadata(),
      authorized: () async => authorized,
    );
  });
  for (final updating in [false, true]) {
    test(
      'lost ${updating ? "update" : "create"} response replays without uploading again',
      () async {
        final uploader = UploadStorage();
        final recorder = RecordingMetadata(db);
        FirestoreDriveBackend session() => FirestoreDriveBackend(
          firestore: db,
          auth: MockFirebaseAuth(
            mockUser: MockUser(uid: 'user'),
            signedIn: true,
          ),
          uid: 'user',
          key: SecretKey(List.filled(32, 7)),
          storage: uploader,
          ownerPrefix: 'opaque',
          journal: MemoryJournal(),
          metadata: recorder,
          authorized: () async => authorized,
        );
        final original = await backend.item('f:file');
        Future<ProviderItem> operation(FirestoreDriveBackend target) => updating
            ? target.update(
                original.id,
                original.version,
                null,
                null,
                Uint8List.fromList([4, 5, 6]),
              )
            : target.createWithRequestId(
                'create-request',
                'root',
                'New.txt',
                false,
                Uint8List.fromList([4, 5, 6]),
              );
        await expectLater(
          operation(session()),
          throwsA(updating ? isA<ProviderFailure>() : isA<StateError>()),
        );
        final result = await operation(session());
        expect(result.id, updating ? original.id : 'f:uploaded');
        expect(uploader.uploads, 1);
        expect(recorder.commits, 1);
        expect((await db.collection('files').get()).docs.length, 2);
      },
    );
  }
  test(
    'native directory create is stable across broker restart and replay',
    () async {
      final first = await backend.createWithRequestId(
        'os-create-1',
        'root',
        'Documents',
        true,
        Uint8List(0),
      );
      final second = await backend.createWithRequestId(
        'os-create-1',
        'root',
        'Documents',
        true,
        Uint8List(0),
      );
      expect(second.id, first.id);
      expect((await db.collection('folders').get()).docs.length, 1);
      await expectLater(
        backend.createWithRequestId(
          'different-os-item',
          'root',
          'Documents',
          true,
          Uint8List(0),
        ),
        throwsA(isA<ProviderFailure>()),
      );
    },
  );
  test('replayed directory create rechecks authorization', () async {
    await backend.createWithRequestId(
      'os-create-1',
      'root',
      'Documents',
      true,
      Uint8List(0),
    );
    authorized = false;
    await expectLater(
      backend.createWithRequestId(
        'os-create-1',
        'root',
        'Documents',
        true,
        Uint8List(0),
      ),
      throwsA(isA<ProviderFailure>()),
    );
    expect((await db.collection('folders').get()).docs.length, 1);
  });
  test(
    'only standard personal files are enumerated and decrypted locally',
    () async {
      await db.collection('files').doc('secure').set({
        ...standard,
        'encryptionMode': 'secured',
      });
      await db.collection('files').doc('business').set({
        ...standard,
        'storageScope': 'company_private',
      });
      await db.collection('files').doc('trash').set({
        ...standard,
        'lifecycleState': 'trashed',
      });
      expect((await backend.list('root')).map((item) => item.name), [
        'Test.txt',
      ]);
      expect(() => backend.item('f:secure'), throwsA(isA<ProviderFailure>()));
    },
  );
  test('successful read returns contents only after completion', () async {
    final item = await backend.item('f:file');
    expect(
      await backend.read(item.id, item.version),
      Uint8List.fromList([1, 2, 3]),
    );
  });
  test(
    'authentication failure after partial decryption never returns bytes',
    () async {
      storage.source = () async* {
        yield [1, 2, 3];
        throw StateError('invalid MAC');
      };
      final item = await backend.item('f:file');
      await expectLater(backend.read(item.id, item.version), throwsStateError);
    },
  );
  test('revocation during transfer prevents native disclosure', () async {
    storage.source = () async* {
      yield [1];
      authorized = false;
      yield [2, 3];
    };
    final item = await backend.item('f:file');
    await expectLater(
      backend.read(item.id, item.version),
      throwsA(isA<ProviderFailure>()),
    );
  });
  test(
    'a remote edit during download invalidates the completed result',
    () async {
      storage.source = () async* {
        yield [1, 2, 3];
        await db.collection('files').doc('file').update({'revision': 2});
      };
      final item = await backend.item('f:file');
      await expectLater(
        backend.read(item.id, item.version),
        throwsA(isA<ProviderFailure>()),
      );
    },
  );
  test(
    'revocation cancels a stalled native read without waiting for another chunk',
    () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      storage.source = () => source.stream;
      final item = await backend.item('f:file');
      final pending = backend.read(item.id, item.version);
      final rejected = expectLater(pending, throwsA(isA<ProviderFailure>()));
      while (!source.hasListener) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      backend.invalidate();
      await rejected.timeout(const Duration(seconds: 2));
      expect(cancelled, true);
      await source.close();
    },
  );
  test('revoked backend cannot be reused after consent is restored', () async {
    backend.invalidate();
    authorized = true;
    await expectLater(backend.item('root'), throwsA(isA<ProviderFailure>()));
  });
  test(
    'version group keeps native identity across replacement uploads',
    () async {
      await db.collection('files').doc('file').update({
        'lifecycleState': 'version',
      });
      await db.collection('files').doc('replacement').set({
        ...standard,
        'versionGroupId': 'file',
        'revision': 2,
      });
      expect((await backend.item('f:file')).id, 'f:file');
      expect((await backend.list('root')).single.id, 'f:file');
    },
  );
}
