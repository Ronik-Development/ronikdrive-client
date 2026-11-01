import 'package:cloud_storage/src/home/workspace_storage_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact footer keeps full limits available on request', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: Text('Files')),
              WorkspaceStorageFooter(),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(WorkspaceStorageFooter)).height,
      lessThanOrEqualTo(52),
    );
    expect(find.textContaining('remaining capacity'), findsNothing);
    await tester.tap(find.text('Storage limits'));
    await tester.pumpAndSettle();
    expect(find.textContaining('remaining capacity'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
