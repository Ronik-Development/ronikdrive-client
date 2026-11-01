import 'package:cloud_storage/src/home/file_collaboration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpNotice(
    WidgetTester tester, {
    required LegacyCollaborationEntryKind kind,
    required bool canProtect,
    required bool failed,
    required bool busy,
    VoidCallback? onRetry,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LegacyCollaborationProtectionNotice(
            kind: kind,
            canProtect: canProtect,
            failed: failed,
            busy: busy,
            onRetry: onRetry,
          ),
        ),
      ),
    );
  }

  testWidgets('failed protection offers an explicit safe retry', (
    tester,
  ) async {
    var retries = 0;
    await pumpNotice(
      tester,
      kind: LegacyCollaborationEntryKind.review,
      canProtect: true,
      failed: true,
      busy: false,
      onRetry: () => retries += 1,
    );

    expect(find.textContaining('could not be confirmed'), findsOneWidget);
    expect(find.textContaining('same encrypted payload'), findsOneWidget);
    expect(find.text('Retry protection'), findsOneWidget);
    await tester.tap(find.text('Retry protection'));
    expect(retries, 1);
  });

  testWidgets('busy protection prevents duplicate retry', (tester) async {
    await pumpNotice(
      tester,
      kind: LegacyCollaborationEntryKind.comment,
      canProtect: true,
      failed: true,
      busy: true,
      onRetry: () {},
    );

    final button = tester.widget<TextButton>(
      find.byWidgetPredicate((widget) => widget is TextButton),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('another member receives honest migration guidance', (
    tester,
  ) async {
    await pumpNotice(
      tester,
      kind: LegacyCollaborationEntryKind.comment,
      canProtect: false,
      failed: false,
      busy: false,
    );

    expect(find.textContaining('original author must open it'), findsOneWidget);
    expect(find.textContaining('readable provider copy'), findsOneWidget);
    expect(find.text('Retry protection'), findsNothing);
  });
}
