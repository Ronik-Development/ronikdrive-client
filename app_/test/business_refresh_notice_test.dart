import 'package:cloud_storage/src/business/business_workspace_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Business refresh notice preserves work and offers recovery', (
    tester,
  ) async {
    var retries = 0;
    var dismissals = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessAccessRefreshNotice(
            message:
                'Company access could not be refreshed. Check your connection and try again.',
            refreshing: false,
            onRetry: () async {
              retries += 1;
            },
            onDismiss: () {
              dismissals += 1;
            },
          ),
        ),
      ),
    );

    expect(find.text('Using the last verified company access'), findsOneWidget);
    expect(
      find.textContaining('current encrypted workspace remains open'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);

    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(dismissals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Business refresh notice disables duplicate actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessAccessRefreshNotice(
            message: 'Refreshing company access.',
            refreshing: true,
            onRetry: () async {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    final retry = tester.widget<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    final dismiss = tester.widget<TextButton>(find.byType(TextButton));
    expect(retry.onPressed, isNull);
    expect(dismiss.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
