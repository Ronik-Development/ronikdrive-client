import 'package:cloud_storage/src/settings/encryption_recovery_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app({
    required bool busy,
    required VoidCallback onCreate,
    required VoidCallback onRestore,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: EncryptionRecoveryPanel(
          busy: busy,
          onCreate: onCreate,
          onRestore: onRestore,
        ),
      ),
    );
  }

  testWidgets('explains provider-blind Personal and Business recovery', (
    tester,
  ) async {
    var createCalls = 0;
    var restoreCalls = 0;
    await tester.pumpWidget(
      app(
        busy: false,
        onCreate: () => createCalls += 1,
        onRestore: () => restoreCalls += 1,
      ),
    );

    expect(find.text('Encryption recovery kit'), findsOneWidget);
    expect(find.textContaining('Business encryption identity'), findsOneWidget);
    expect(find.textContaining('does not upload'), findsOneWidget);
    expect(find.textContaining('keep them separately'), findsOneWidget);

    await tester.tap(find.text('Create recovery kit'));
    await tester.tap(find.text('Restore from kit'));
    expect(createCalls, 1);
    expect(restoreCalls, 1);
  });

  testWidgets('disables both recovery actions while processing', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      app(busy: true, onCreate: () => calls += 1, onRestore: () => calls += 1),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is FilledButton && widget.onPressed == null,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is OutlinedButton && widget.onPressed == null,
      ),
      findsOneWidget,
    );
    expect(calls, 0);
  });
}
