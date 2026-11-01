import 'dart:async';

import 'package:cloud_storage/src/support/product_feedback.dart';
import 'package:cloud_storage/src/support/support_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'prompt cooldown and opt-out are isolated by account and environment',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.utc(2026, 9, 10);
      final policy = FeedbackPromptPreferences('staging:alice');
      expect(policy.isDue(prefs, now), isTrue);
      await policy.postpone(prefs, now);
      expect(policy.isDue(prefs, now.add(const Duration(days: 29))), isFalse);
      expect(policy.isDue(prefs, now.add(const Duration(days: 30))), isTrue);
      expect(
        FeedbackPromptPreferences('production:alice').isDue(prefs, now),
        isTrue,
      );
      expect(
        FeedbackPromptPreferences('staging:bob').isDue(prefs, now),
        isTrue,
      );
      await prefs.setBool('${policy.key}-disabled', true);
      expect(policy.isDue(prefs, now.add(const Duration(days: 365))), isFalse);
    },
  );

  test(
    'issue UI eligibility excludes trials, expired sources and free accounts',
    () {
      final now = DateTime.utc(2026, 9, 10);
      final paid = {
        'tier': 'pro',
        'status': 'active',
        'currentPeriodEnd': now.add(const Duration(days: 1)),
      };
      expect(
        canSubmitIssueReport({
          'billingSources': {'stripe': paid},
        }, now: now),
        isTrue,
      );
      for (final status in [
        'trialing',
        'expired',
        'free',
        'billing_grace_period',
      ]) {
        expect(
          canSubmitIssueReport({
            'billingSources': {
              'stripe': {...paid, 'status': status},
            },
          }, now: now),
          isFalse,
        );
      }
      expect(
        canSubmitIssueReport({
          'billingSources': {
            'stripe': {...paid, 'currentPeriodEnd': now},
          },
        }, now: now),
        isFalse,
      );
      expect(canSubmitIssueReport(null, now: now), isFalse);
    },
  );

  testWidgets(
    'feedback validates empty answers, preserves failed drafts and prevents duplicate sends',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<void>();
      var calls = 0;
      String? answer;
      await tester.pumpWidget(
        MaterialApp(
          home: ProductFeedbackPage(
            onSubmit: (description) {
              calls++;
              answer = description;
              return pending.future;
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('Send feedback'));
      await tester.tap(find.text('Send feedback'));
      await tester.pump();
      expect(calls, 0);
      expect(
        find.text('Answer at least one question before sending.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).first, 'Add calendar sync');
      await tester.ensureVisible(find.text('Send feedback'));
      await tester.tap(find.text('Send feedback'));
      await tester.pump();
      expect(calls, 1);
      expect(answer, contains('Add calendar sync'));
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((widget) => widget is FilledButton),
            )
            .onPressed,
        isNull,
      );
      pending.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Your answers are still here'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Add calendar sync',
      );
    },
  );

  testWidgets('prompt waits for workspace readiness and remembers opt-out', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    Widget app(bool enabled) => MaterialApp(
      home: Scaffold(
        body: ProductFeedbackPrompt(
          accountScope: 'test:alice',
          enabled: enabled,
          onOpen: () {},
        ),
      ),
    );
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(find.text('Share feedback'), findsNothing);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Don’t ask again'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(find.text('Share feedback'), findsNothing);
  });
}
