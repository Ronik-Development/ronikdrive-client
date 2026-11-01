import 'package:cloud_storage/src/support/support_report_privacy.dart';
import 'package:cloud_storage/src/support/support_report_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'preview filters sensitive text and supports editing before sending',
    (tester) async {
      bool? approved;
      final report = SupportReportPayload.prepare(
        title: 'Upload issue',
        description: r'Cannot open C:\Users\Alice\secret.txt',
        stepsToReproduce: '',
        platform: 'windows',
        buildMode: 'release',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                approved = await reviewSupportReport(context, report);
              },
              child: const Text('Review'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text(report.description), findsOneWidget);
      expect(find.textContaining('Alice'), findsNothing);
      await tester.tap(find.text('Back to editing'));
      await tester.pumpAndSettle();
      expect(approved, isFalse);
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(approved, isTrue);
    },
  );
}
