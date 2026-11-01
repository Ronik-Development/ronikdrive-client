import 'package:cloud_storage/src/business/company_admin_page.dart';
import 'package:cloud_storage/src/business/company_admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDashboard(WidgetTester tester, CompanyDashboard dashboard) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BusinessAccessMetricsView(dashboard: dashboard)),
      ),
    );
  }

  testWidgets('legacy mixed-account metrics fail closed in the UI', (
    tester,
  ) async {
    await pumpDashboard(tester, const CompanyDashboard());

    expect(find.text('Business privacy boundary'), findsOneWidget);
    expect(find.textContaining('privacy-scoped server update'), findsOneWidget);
    expect(find.textContaining('Personal workspace counts'), findsOneWidget);
    expect(find.text('Business files'), findsNothing);
  });

  testWidgets('Business-only metrics resolve a response-local member ordinal', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      const CompanyDashboard(
        accessPatternsAvailable: true,
        accessPatternsComplete: true,
        members: <CompanyMember>[
          CompanyMember(
            id: 'member-record',
            uid: 'private-member-uid',
            displayName: 'Authorized admin label',
          ),
        ],
        accessPatterns: <CompanyAccessPattern>[
          CompanyAccessPattern(
            memberIndex: 0,
            role: 'admin',
            accessScopes: <String>['company_workspace'],
            fileCount: 3,
            folderCount: 2,
            sharedFileCount: 1,
            usageBytes: 4096,
          ),
        ],
      ),
    );

    expect(find.text('Authorized admin label'), findsOneWidget);
    expect(find.text('Business files'), findsOneWidget);
    expect(find.text('Business folders'), findsOneWidget);
    expect(find.text('Business usage'), findsOneWidget);
    expect(
      find.textContaining(
        'Personal files, usage, and account activity are excluded',
      ),
      findsOneWidget,
    );
    expect(find.text('private-member-uid'), findsNothing);
  });

  testWidgets('bounded Business aggregation is visibly incomplete', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      const CompanyDashboard(
        accessPatternsAvailable: true,
        accessPatternsComplete: false,
        members: <CompanyMember>[CompanyMember(id: 'member-record')],
        accessPatterns: <CompanyAccessPattern>[
          CompanyAccessPattern(memberIndex: 0),
        ],
      ),
    );

    expect(
      find.text('Business metrics are still being indexed'),
      findsOneWidget,
    );
    expect(find.textContaining('may be incomplete'), findsOneWidget);
  });
}
