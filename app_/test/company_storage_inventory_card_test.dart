import 'package:cloud_storage/src/business/company_admin_page.dart';
import 'package:cloud_storage/src/business/company_admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpInventory(
    WidgetTester tester,
    CompanyStorageInventory inventory,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessStorageInventoryCard(inventory: inventory),
        ),
      ),
    );
  }

  testWidgets('explains aggregate-only healthy Business inventory', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const CompanyStorageInventory(
        available: true,
        status: 'healthy',
        complete: true,
        objectCount: 1,
      ),
    );

    expect(find.text('Business storage matches'), findsOneWidget);
    expect(
      find.textContaining('1 encrypted storage object match'),
      findsOneWidget,
    );
    expect(find.textContaining('aggregate counts and sizes'), findsOneWidget);
  });

  testWidgets('partial scan promises no restriction', (tester) async {
    await pumpInventory(
      tester,
      const CompanyStorageInventory(available: true, status: 'partial'),
    );

    expect(find.text('Business storage check is incomplete'), findsOneWidget);
    expect(find.textContaining('No storage restriction'), findsOneWidget);
  });

  testWidgets('divergence shows only counts and privacy boundary', (
    tester,
  ) async {
    await pumpInventory(
      tester,
      const CompanyStorageInventory(
        available: true,
        status: 'diverged',
        complete: true,
        orphanObjectCount: 1,
        missingObjectCount: 2,
      ),
    );

    expect(find.text('Business storage needs reconciliation'), findsOneWidget);
    expect(find.textContaining('1 unindexed object'), findsOneWidget);
    expect(find.textContaining('2 missing objects'), findsOneWidget);
    expect(
      find.textContaining('File names and contents were not inspected'),
      findsOneWidget,
    );
  });

  testWidgets('missing snapshot describes the planned private check', (
    tester,
  ) async {
    await pumpInventory(tester, const CompanyStorageInventory());

    expect(find.text('Business storage check is waiting'), findsOneWidget);
    expect(
      find.textContaining('File contents and names are never inspected'),
      findsOneWidget,
    );
  });
}
