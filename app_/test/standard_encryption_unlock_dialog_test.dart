import 'package:cloud_storage/src/security/standard_encryption_unlock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unlock dialog explains the device-only key boundary', (
    WidgetTester tester,
  ) async {
    String? submittedPassword;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                submittedPassword = await showDialog<String>(
                  context: context,
                  builder: (_) => const StandardEncryptionUnlockDialog(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock encrypted files'), findsOneWidget);
    expect(
      find.text(StandardEncryptionUnlockDialog.privacyNotice),
      findsOneWidget,
    );
    expect(find.textContaining('current RonikCloud account'), findsOneWidget);
    expect(find.textContaining('Restore from recovery kit'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);

    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    final controller = field.controller!;
    await tester.enterText(find.byType(TextFormField), 'local-test-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    expect(controller.text, isEmpty);
    await tester.pumpAndSettle();

    expect(submittedPassword, 'local-test-password');
  });

  testWidgets('unlock dialog validates an empty password locally', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => const StandardEncryptionUnlockDialog(),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pump();

    expect(find.text('Enter your password.'), findsOneWidget);
    expect(find.text('Unlock encrypted files'), findsOneWidget);
  });

  testWidgets('cancel clears the password field before closing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => const StandardEncryptionUnlockDialog(),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    final controller = field.controller!;
    await tester.enterText(find.byType(TextFormField), 'discard-this-value');

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    expect(controller.text, isEmpty);
    await tester.pumpAndSettle();

    expect(find.text('Unlock encrypted files'), findsNothing);
  });
}
