import 'dart:async';
import 'package:cloud_storage/src/authentication/account_bound_token.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

// MockUser intentionally exposes mutable profile fields for authentication tests.
// ignore: must_be_immutable
class DelayedUser extends MockUser {
  DelayedUser() : super(uid: 'original');
  final requested = Completer<void>();
  final token = Completer<String>();
  @override
  Future<String> getIdToken([bool forceRefresh = false]) {
    requested.complete();
    return token.future;
  }
}

void main() {
  test(
    'signed-out and different accounts cannot authorize an old storage service',
    () async {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'original'),
        signedIn: true,
      );
      final provider = accountBoundTokenProvider(auth: auth, uid: 'original');
      expect(await provider(), isNotNull);
      expect(
        await accountBoundTokenProvider(auth: auth, uid: 'another')(),
        isNull,
      );
      await auth.signOut();
      expect(await provider(), isNull);
    },
  );
  test(
    'sign-out during token refresh discards the refreshed credential',
    () async {
      final user = DelayedUser();
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final pending = accountBoundTokenProvider(auth: auth, uid: user.uid)();
      await user.requested.future;
      await auth.signOut();
      user.token.complete('old-account-token');
      expect(await pending, isNull);
    },
  );
}
