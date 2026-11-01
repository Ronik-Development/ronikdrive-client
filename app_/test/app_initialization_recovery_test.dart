import 'dart:async';

import 'package:cloud_storage/main.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'startup failure hides provider details and retries a fresh future',
    (tester) async {
      final initial = Completer<FirebaseApp>();
      final retry = Completer<FirebaseApp>();
      var attempts = 0;
      await tester.pumpWidget(
        CloudStorageApp(
          firebaseAppFuture: initial.future,
          firebaseInitializer: () {
            attempts++;
            return retry.future;
          },
        ),
      );
      initial.completeError(Exception('Bearer synthetic-private-token'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('synthetic-private-token'), findsNothing);
      expect(find.textContaining('firebase_options.dart'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(attempts, 1);
      expect(find.text('Preparing your workspace…'), findsOneWidget);
      retry.completeError(StateError('synthetic-provider-detail'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('synthetic-provider-detail'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('synchronous initialization failure remains retryable', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      CloudStorageApp(
        firebaseInitializer: () {
          attempts++;
          throw StateError('synthetic-configuration-detail');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('synthetic-configuration-detail'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
