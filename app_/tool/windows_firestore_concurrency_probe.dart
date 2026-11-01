// Isolated synthetic project; no customer data, credentials or remote writes.
import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_storage/src/shared/configured_firestore.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final app = await Firebase.initializeApp(
    options: const FirebaseOptions(apiKey:'fake-api-key',appId:'fake-app-id',messagingSenderId:'123',projectId:'demo-ronik-concurrency'),
  );
  final db = ConfiguredFirestore.instanceFor(app:app);
  db.useFirestoreEmulator('127.0.0.1', 59999);
  debugPrint('[concurrency-probe] process=$pid persistence=${db.settings.persistenceEnabled} starting');
  unawaited(db.collection('synthetic').doc('probe').get().catchError((Object error) {
    throw error;
  }).then<void>((_) {}, onError:(Object _) {}));
  await Future<void>.delayed(const Duration(seconds:15));
  debugPrint('[concurrency-probe] process=$pid survived');
  exit(0);
}
