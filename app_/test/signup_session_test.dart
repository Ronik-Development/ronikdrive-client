import 'package:cloud_storage/src/authentication/signup_session.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

class _ExistingAuth extends MockFirebaseAuth {
  _ExistingAuth({this.rejectPassword = false})
    : super(
        mockUser: MockUser(
          uid: 'partial',
          email: '333@users.ronikcloud.invalid',
        ),
      );
  final bool rejectPassword;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async => throw FirebaseAuthException(code: 'email-already-in-use');
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    if (rejectPassword) throw FirebaseAuthException(code: 'wrong-password');
    return super.signInWithEmailAndPassword(email: email, password: password);
  }
}

void main() {
  Future<({UserCredential credential, bool created})> signup(
    FirebaseAuth auth,
    FakeFirebaseFirestore db,
  ) => createOrResumeSignup(
    auth: auth,
    firestore: db,
    email: '333@users.ronikcloud.invalid',
    password: 'test-password',
  );
  test('new accounts remain marked newly created', () async {
    expect(
      (await signup(MockFirebaseAuth(), FakeFirebaseFirestore())).created,
      isTrue,
    );
  });
  test(
    'authenticated partial account resumes without being treated as disposable',
    () async {
      final auth = _ExistingAuth();
      final result = await signup(auth, FakeFirebaseFirestore());
      expect(result.created, isFalse);
      expect(result.credential.user!.uid, 'partial');
      expect(auth.currentUser, isNotNull);
    },
  );
  test('complete account cannot be re-registered and is signed out', () async {
    final auth = _ExistingAuth();
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('partial').set({'username': '333'});
    await expectLater(
      signup(auth, db),
      throwsA(
        isA<FirebaseAuthException>().having(
          (e) => e.code,
          'code',
          'email-already-in-use',
        ),
      ),
    );
    expect(auth.currentUser, isNull);
    expect((await db.collection('users').doc('partial').get()).exists, isTrue);
  });
  test(
    'encryption-only profile resumes with its existing salt intact',
    () async {
      final auth = _ExistingAuth();
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('partial').set({
        'encryptionSalt': 'existing-salt',
        'subscriptionStatus': 'pending',
        'capacity': 'pending',
        'currentPeriodEnd': 'pending',
        'email': '333@users.ronikcloud.invalid',
        'usageBytes': 123,
        'storageInventory': {'objects': 1},
        'storageInventoryUpdatedAt': 'server-time',
      });
      expect((await signup(auth, db)).created, isFalse);
      expect(auth.currentUser, isNotNull);
      expect(
        (await db.collection('users').doc('partial').get())
            .data()!['encryptionSalt'],
        'existing-salt',
      );
    },
  );
  test('paid or billing-linked profiles cannot be resumed as free signup', () {
    for (final profile in <Map<String, dynamic>>[
      {'subscriptionStatus': 'active'},
      {'stripeCustomerId': 'customer'},
      {'capacityBytes': 1073741824},
      {'companyId': 'company'},
    ]) {
      expect(isIncompleteRegistrationProfile(profile), isFalse);
    }
  });
  test('wrong password cannot resume an existing partial account', () async {
    await expectLater(
      signup(_ExistingAuth(rejectPassword: true), FakeFirebaseFirestore()),
      throwsA(
        isA<FirebaseAuthException>().having(
          (e) => e.code,
          'code',
          'wrong-password',
        ),
      ),
    );
  });
}
