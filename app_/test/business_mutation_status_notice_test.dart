import 'dart:io';

import 'package:cloud_storage/src/business/company_admin_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uncertain Business mutations require a status refresh', (
    tester,
  ) async {
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessMutationStatusNotice(
            refreshing: false,
            onRefresh: () async {
              refreshes += 1;
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('could not confirm'), findsOneWidget);
    expect(find.textContaining('last verified dashboard'), findsOneWidget);
    expect(find.textContaining('before repeating'), findsOneWidget);
    expect(find.text('Refresh status'), findsOneWidget);

    await tester.tap(find.text('Refresh status'));
    await tester.pump();
    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status refresh prevents duplicate taps while checking', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessMutationStatusNotice(
            refreshing: true,
            onRefresh: () async {},
          ),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Checking status'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  test('Business mutation and stream boundaries preserve verified state', () {
    final adminSource = File(
      'lib/src/business/company_admin_page.dart',
    ).readAsStringSync();
    final workspaceSource = File(
      'lib/src/home/workspace_home_page.dart',
    ).readAsStringSync();

    expect(
      adminSource,
      contains('error.kind == CompanyAdminFailureKind.cloud'),
    );
    expect(adminSource, contains('if (_mutationStatusUncertain)'));
    expect(adminSource, contains('busy: _busy || _mutationStatusUncertain'));
    expect(adminSource, contains('onRefresh: _loadDashboard'));
    expect(
      workspaceSource,
      isNot(contains("debugPrint('Failed to load company files: \$error')")),
    );
    expect(
      workspaceSource,
      isNot(contains("debugPrint('Failed to load company folders: \$error')")),
    );
  });
}
