import 'dart:async';

import 'package:cloud_storage/src/privacy/temporary_plaintext_files_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(CleanupPlaintextTemporaryFiles onClear) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TemporaryPlaintextFilesControl(onClear: onClear),
        ),
      ),
    );
  }

  testWidgets('explains external retention and reports cleared files', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      app(() async {
        calls += 1;
        return 2;
      }),
    );

    expect(find.text('Temporary decrypted files'), findsOneWidget);
    expect(find.textContaining('receiving app may retain'), findsOneWidget);

    await tester.tap(find.text('Clear temporary files'));
    await tester.pump();

    expect(calls, 1);
    expect(find.text('Cleared 2 temporary decrypted files.'), findsOneWidget);
  });

  testWidgets('disables repeated cleanup while a clear is running', (
    tester,
  ) async {
    final result = Completer<int>();
    var calls = 0;
    await tester.pumpWidget(
      app(() {
        calls += 1;
        return result.future;
      }),
    );

    await tester.tap(find.text('Clear temporary files'));
    await tester.pump();

    expect(find.text('Clearing...'), findsOneWidget);
    expect(calls, 1);

    await tester.tap(find.text('Clearing...'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);

    result.complete(0);
    await tester.pump();

    expect(
      find.text('No RonikCloud temporary decrypted files were found.'),
      findsOneWidget,
    );
  });
}
