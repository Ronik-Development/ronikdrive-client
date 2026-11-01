import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cloud_storage/src/business/business_reconciliation_queue.dart';
import 'package:cloud_storage/src/business/business_workspace_page.dart';

void main() {
  testWidgets('opens an authorized affected encrypted space', (tester) async {
    final target = BusinessReconciliationTarget(
      location: BusinessReconciliationLocation.group(
        companyId: 'company-one',
        groupId: 'group-one',
      ),
      reasons: const <BusinessReconciliationReason>{
        BusinessReconciliationReason.groupMembershipChanged,
      },
    );
    BusinessReconciliationTarget? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessReconciliationQueueBanner(
            targets: <BusinessReconciliationTarget>[target],
            cacheLocked: false,
            recoveredCorruptValue: false,
            labelFor: (_) => 'Design',
            canOpen: (_) => true,
            onOpen: (value) => opened = value,
          ),
        ),
      ),
    );

    expect(find.text('1 encrypted space needs attention'), findsOneWidget);
    expect(find.text('Design'), findsOneWidget);
    expect(find.textContaining('File content stays on that device'), findsOne);

    await tester.tap(find.text('Design'));
    await tester.pump();

    expect(opened, same(target));
  });

  testWidgets('identifies spaces that require another trusted member', (
    tester,
  ) async {
    final target = BusinessReconciliationTarget(
      location: BusinessReconciliationLocation.group(
        companyId: 'company-one',
        groupId: 'group-one',
      ),
      reasons: const <BusinessReconciliationReason>{
        BusinessReconciliationReason.memberStatusChanged,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessReconciliationQueueBanner(
            targets: <BusinessReconciliationTarget>[target],
            cacheLocked: false,
            recoveredCorruptValue: false,
            labelFor: (_) => 'Finance',
            canOpen: (_) => false,
            onOpen: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Finance - trusted member'), findsOneWidget);
    expect(find.byIcon(Icons.person_search_outlined), findsOneWidget);
  });

  testWidgets('explains credential-store lock without exposing queue data', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessReconciliationQueueBanner(
            targets: const <BusinessReconciliationTarget>[],
            cacheLocked: true,
            recoveredCorruptValue: false,
            labelFor: (_) => '',
            canOpen: (_) => false,
            onOpen: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.text('Unlock this device to restore encrypted follow-up'),
      findsOneWidget,
    );
    expect(
      find.textContaining('not replaced with readable state'),
      findsOneWidget,
    );
  });
}
