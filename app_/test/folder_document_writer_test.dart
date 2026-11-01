import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_storage/src/storage/folder_document_writer.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Simulate the rules rejecting an update before checking document existence.
// Delegate successful writes to the fake so the stored data is also verified.
// This test double intentionally implements the SDK facade.
// ignore: subtype_of_sealed_class
class _RejectedUpdateReference
    implements DocumentReference<Map<String, dynamic>> {
  _RejectedUpdateReference(this.delegate, this.updateCode, {this.setCode});

  final DocumentReference<Map<String, dynamic>> delegate;
  final String updateCode;
  final String? setCode;
  final _createAttempts = <Map<String, dynamic>>[];
  int get creates => _createAttempts.length;

  @override
  Future<void> update(Map<Object, Object?> data) async {
    throw FirebaseException(plugin: 'cloud_firestore', code: updateCode);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    _createAttempts.add(data);
    if (setCode != null) {
      throw FirebaseException(plugin: 'cloud_firestore', code: setCode!);
    }
    await delegate.set(data, options);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Map<String, dynamic> payload() => <String, dynamic>{
    'uid': 'owner',
    'encryptedName': 'enc--protected-folder-label',
    'metadataEncryption': 'standard-aes-gcm-v1',
    'color': '#445566',
    'updatedAt': FieldValue.serverTimestamp(),
    'systemFolder': false,
  };

  for (final code in ['permission-denied', 'not-found']) {
    test(
      'creates a root folder after a missing update returns $code',
      () async {
        final folder = FakeFirebaseFirestore().doc('folders/new-folder');
        final reference = _RejectedUpdateReference(folder, code);

        await upsertEncryptedFolderDocument(reference, payload());

        final data = (await folder.get()).data()!;
        expect(reference.creates, 1);
        expect(data['encryptedName'], payload()['encryptedName']);
        expect(data['createdAt'], isA<Timestamp>());
        expect(data.containsKey('parentId'), isFalse);
        for (final field in ['name', 'path', 'pathSegments']) {
          expect(data.containsKey(field), isFalse);
        }
      },
    );
  }

  test(
    'creates nested backup folders with their parent and system fields',
    () async {
      final folder = FakeFirebaseFirestore().doc('folders/nested-backup');
      final reference = _RejectedUpdateReference(folder, 'permission-denied');

      await upsertEncryptedFolderDocument(reference, {
        ...payload(),
        'parentId': 'backup-root',
        'systemFolder': true,
        'systemKey': 'backup',
      });

      final data = (await folder.get()).data()!;
      expect(data['parentId'], 'backup-root');
      expect(data['systemFolder'], isTrue);
      expect(data['systemKey'], 'backup');
    },
  );

  test(
    'updates existing folders without replacing their creation date',
    () async {
      final folder = FakeFirebaseFirestore().doc('folders/existing');
      final createdAt = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
      await folder.set({
        ...payload(),
        'createdAt': createdAt,
        'parentId': 'parent',
        'name': 'Legacy readable name',
        'path': 'Legacy path',
        'pathSegments': ['Legacy path'],
      });

      await upsertEncryptedFolderDocument(folder, {
        ...payload(),
        'encryptedName': 'enc--renamed-folder-label',
      });

      final data = (await folder.get()).data()!;
      expect(data['createdAt'], createdAt);
      expect(data['parentId'], 'parent');
      expect(data['encryptedName'], 'enc--renamed-folder-label');
      for (final field in ['name', 'path', 'pathSegments']) {
        expect(data.containsKey(field), isFalse);
      }
    },
  );

  test('propagates a denied create instead of reporting success', () async {
    final folder = FakeFirebaseFirestore().doc('folders/denied');
    final reference = _RejectedUpdateReference(
      folder,
      'permission-denied',
      setCode: 'permission-denied',
    );

    await expectLater(
      upsertEncryptedFolderDocument(reference, payload()),
      throwsA(
        isA<FirebaseException>().having(
          (error) => error.code,
          'code',
          'permission-denied',
        ),
      ),
    );
    expect((await folder.get()).exists, isFalse);
  });

  for (final code in ['unavailable', 'unauthenticated', 'deadline-exceeded']) {
    test('does not attempt creation after $code', () async {
      final folder = FakeFirebaseFirestore().doc('folders/uncertain');
      final reference = _RejectedUpdateReference(folder, code);

      await expectLater(
        upsertEncryptedFolderDocument(reference, payload()),
        throwsA(
          isA<FirebaseException>().having((error) => error.code, 'code', code),
        ),
      );
      expect(reference.creates, 0);
      expect((await folder.get()).exists, isFalse);
    });
  }
}
