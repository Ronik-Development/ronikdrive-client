import 'package:cloud_storage/src/business/company_admin_page.dart';
import 'package:cloud_storage/src/business/company_admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpView(
    WidgetTester tester,
    CompanyDashboard dashboard, {
    Future<void> Function()? onRefresh,
    bool refreshing = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessAuditLogView(
            dashboard: dashboard,
            onRefresh: onRefresh,
            refreshing: refreshing,
          ),
        ),
      ),
    );
  }

  testWidgets('unavailable history is never presented as empty', (
    tester,
  ) async {
    var refreshCount = 0;
    await pumpView(
      tester,
      const CompanyDashboard(),
      onRefresh: () async {
        refreshCount += 1;
      },
    );

    expect(find.text('Activity history unavailable'), findsOneWidget);
    expect(
      find.textContaining('never shown as an empty history'),
      findsOneWidget,
    );
    expect(find.text('No recorded Business activity'), findsNothing);

    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(refreshCount, 1);
  });

  testWidgets('verified empty history is labelled accurately', (tester) async {
    await pumpView(
      tester,
      const CompanyDashboard(auditLogsAvailable: true, auditLogsComplete: true),
    );

    expect(find.text('No recorded Business activity'), findsOneWidget);
    expect(find.textContaining('verified activity history'), findsOneWidget);
    expect(find.text('Activity history unavailable'), findsNothing);
    expect(find.text('Showing recent activity'), findsNothing);
  });

  testWidgets('bounded history discloses that older events may exist', (
    tester,
  ) async {
    final entry = CompanyAuditLogEntry.fromMap(<String, Object?>{
      'action': 'company.member_permissions_updated',
      'title': 'Private free-form title person@example.test',
    });
    await pumpView(
      tester,
      CompanyDashboard(
        auditLogsAvailable: true,
        auditLogsComplete: false,
        auditLogs: <CompanyAuditLogEntry>[entry],
      ),
    );

    expect(find.text('Showing recent activity'), findsOneWidget);
    expect(find.textContaining('Older events may exist'), findsOneWidget);
    expect(find.text('Company user permissions updated'), findsOneWidget);
    expect(find.textContaining('person@example.test'), findsNothing);
    expect(find.textContaining('raw account identifiers'), findsOneWidget);
  });

  testWidgets('refresh control is disabled while history is reloading', (
    tester,
  ) async {
    await pumpView(
      tester,
      const CompanyDashboard(),
      refreshing: true,
      onRefresh: () async {},
    );

    final button = tester.widget<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Refreshing'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('unavailable history remains usable in a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpView(tester, const CompanyDashboard(), onRefresh: () async {});

    expect(find.text('Activity history unavailable'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
