import 'dart:async';

import 'package:cloud_storage/src/share/share_preparation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('browsing can continue and completion preserves another dialog', (
    tester,
  ) async {
    final work = Completer<int>();
    late BuildContext host;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  await runSharePreparation<int>(
                    context: context,
                    initialStatus: 'Downloading…',
                    prepare: (_) => work.future,
                  );
                  completed = true;
                },
                child: const Text('Share'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Share'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue browsing'));
    await tester.pumpAndSettle();
    expect(completed, isFalse);
    unawaited(
      showDialog<void>(
        context: host,
        builder: (_) => const AlertDialog(title: Text('Other task')),
      ),
    );
    await tester.pumpAndSettle();
    work.complete(42);
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(find.text('Other task'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'preparation shows stages and closes on ${fails ? 'failure' : 'success'}',
      (tester) async {
        final work = Completer<int>();
        ValueChanged<String>? update;
        Object? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    try {
                      result = await runSharePreparation<int>(
                        context: context,
                        initialStatus: 'Downloading…',
                        prepare: (updateStatus) {
                          update = updateStatus;
                          return work.future;
                        },
                      );
                    } catch (error) {
                      result = error;
                    }
                  },
                  child: const Text('Share'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Share'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Downloading…'), findsOneWidget);
        update!('Uploading…');
        await tester.pump();
        expect(find.text('Uploading…'), findsOneWidget);
        if (fails) {
          work.completeError(StateError('unavailable'));
        } else {
          work.complete(42);
        }
        await tester.pumpAndSettle();
        expect(find.text('Preparing share'), findsNothing);
        expect(find.text('Share'), findsOneWidget);
        if (fails) {
          expect(result, isA<StateError>());
        } else {
          expect(result, 42);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
