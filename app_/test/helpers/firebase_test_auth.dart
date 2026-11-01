import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';

class TestFirebaseAuth extends MockFirebaseAuth {
  TestFirebaseAuth({super.mockUser, super.signedIn = false});
  @override
  FirebaseApp get app => TestFirebaseApp();
}

class TestFirebaseApp implements FirebaseApp {
  @override
  String get name => '[DEFAULT]';
  @override
  FirebaseOptions get options => const FirebaseOptions(
    apiKey: 'test',
    appId: 'test',
    messagingSenderId: 'test',
    projectId: 'test',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
