import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_storage/app_theme.dart';
import 'package:cloud_storage/src/authentication/business_landing_page.dart';
import 'package:cloud_storage/src/authentication/account_environment.dart';
import 'package:cloud_storage/src/business/business_demo_page.dart';
import 'package:cloud_storage/src/business/business_overview.dart';
import 'package:cloud_storage/src/business/company_admin_page.dart';
import 'package:cloud_storage/src/business/company_admin_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Source Sans 3');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/SourceSans3-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('overview routes to the real settings and invitation flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyAdminPage(
          auth: MockFirebaseAuth(),
          firestore: FakeFirebaseFirestore(),
          service: CompanyAdminService(
            callable: (_, _) async => {
              'canManage': true,
              'company': {'id': 'company', 'name': 'Test team'},
              'members': <Object?>[],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your team’s workspace'), findsOneWidget);
    await tester.tap(find.text('Manage storage'));
    await tester.pumpAndSettle();
    expect(find.text('Company profile'), findsOneWidget);
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite a teammate'));
    await tester.pumpAndSettle();
    expect(find.text('Invite company user'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'member search combines with status and expiration filters locally',
    (tester) async {
      var mutations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessMembersView(
              dashboard: _directory,
              busy: false,
              onAdd: () => mutations++,
              onEdit: (_) => mutations++,
              onRevokeInvitation: (_) => mutations++,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), ' RIVERA ');
      await tester.pump();
      expect(find.text('Sam Rivera'), findsOneWidget);
      expect(find.text('Alex Morgan'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Suspended'));
      await tester.pump();
      expect(find.text('No users match your search or filter'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear user search'));
      await tester.pump();
      expect(find.text('Taylor Reed'), findsOneWidget);
      await tester.tap(
      find.widgetWithText(ChoiceChip, 'Needs setup'),
      );
      await tester.pump();
      expect(find.text('Sam Rivera'), findsOneWidget);
      expect(find.text('Taylor Reed'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Expired invitations'));
      await tester.pump();
      expect(find.textContaining('EXPIRED1234'), findsWidgets);
      expect(find.textContaining('FUTURE1234'), findsNothing);
      await tester.enterText(find.byType(TextField), 'expired1234');
      await tester.pump();
      expect(find.textContaining('Showing 1 of 5'), findsOneWidget);
      await tester.tap(find.byTooltip('Revoke invitation'));
      expect(mutations, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('group search uses readable descriptions and preserves actions', (
    tester,
  ) async {
    String? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessGroupsView(
            dashboard: _directory,
            busy: false,
            onAdd: () {},
            onEdit: (group) => edited = group.id,
            onRefreshProtectedLabels: (_) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), ' invoices ');
    await tester.pump();
    expect(find.text('Finance'), findsOneWidget);
    expect(find.text('Design'), findsNothing);
    await tester.tap(find.byTooltip('Group actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit group'));
    await tester.pumpAndSettle();
    expect(edited, 'finance');
    await tester.enterText(find.byType(TextField), 'no match');
    await tester.pump();
    expect(find.text('No groups match your search'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear group search'));
    await tester.pump();
    expect(find.textContaining('Showing 2 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'overview keeps unavailable inventory and pending access explicit',
    (tester) async {
      final sections = <BusinessAdminSection>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessOverview(
              dashboard: _directory,
              onOpenSection: sections.add,
            ),
          ),
        ),
      );
      final pending = find.text('1 shared space needs access reconciliation');
      await tester.scrollUntilVisible(pending, 250);
      expect(pending, findsOneWidget);
      final inventory = find.text('Storage inventory is not yet confirmed');
      await tester.scrollUntilVisible(inventory, 150);
      await tester.tap(inventory);
      expect(sections.last, BusinessAdminSection.profile);
      expect(find.text('Storage inventory matches'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('incomplete healthy inventory cannot be presented as matching', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BusinessStorageInventoryCard(
            inventory: CompanyStorageInventory(
              available: true,
              status: 'healthy',
              complete: false,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Business storage check is incomplete'), findsOneWidget);
    expect(find.text('Business storage matches'), findsNothing);
  });

  testWidgets(
    'public sample works without cloud setup and converts to Business signup',
    (tester) async {
      final calls = <(AccountEnvironment, bool)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessLandingPage(
            openAccount: (environment, register) async =>
                calls.add((environment, register)),
          ),
        ),
      );
      final explore = find.byKey(const ValueKey('business-explore-demo'));
      await tester.ensureVisible(explore);
      await tester.tap(explore);
      await tester.pumpAndSettle();
      expect(find.byType(BusinessDemoPage), findsOneWidget);
      expect(find.textContaining('Read-only sample data.'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Users'));
      await tester.pumpAndSettle();
      expect(find.text('Search users'), findsOneWidget);
      expect(find.text('Add user'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Alex');
      await tester.pump();
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('Sam Rivera'), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('Create your Business account'));
      await tester.tap(find.text('Create your Business account'));
      await tester.pumpAndSettle();
      expect(find.byType(BusinessDemoPage), findsNothing);
      expect(calls, [(AccountEnvironment.business, true)]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, height, scale, dark) in [
    (1280.0, 900.0, 1.0, false),
    (390.0, 844.0, 1.0, false),
    (320.0, 640.0, 2.0, false),
    (1280.0, 900.0, 1.0, true),
  ]) {
    testWidgets(
      'sample supports all sections at $width, scale $scale, dark $dark',
      (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: key,
              child: BusinessDemoPage(onCreateAccount: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_BUSINESS_PREVIEWS')) {
          await _capture(
            tester,
            key,
            'suite-${width.toInt()}-${scale.toInt()}-${dark ? 'dark' : 'light'}-overview',
          );
        }
        // At enlarged text sizes the introduction can fill the viewport.
        await tester.scrollUntilVisible(
          find.byType(TabBar),
          200,
          scrollable: find
              .descendant(
                of: find.byType(NestedScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        for (final label in ['Profile', 'Users', 'Groups', 'Access', 'Logs']) {
          final tab = find.widgetWithText(Tab, label);
          await tester.ensureVisible(tab);
          await tester.tap(tab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'section $label');
          if (label == 'Users' &&
              const bool.fromEnvironment('CAPTURE_BUSINESS_PREVIEWS')) {
            await _capture(
              tester,
              key,
              'suite-${width.toInt()}-${scale.toInt()}-${dark ? 'dark' : 'light'}-users',
            );
          }
        }
      },
    );
  }
}

final _directory = CompanyDashboard(
  canManage: true,
  company: const CompanyProfile(
    id: 'company',
    name: 'Test team',
    reconciliation: BusinessReconciliationState(
      requiredRevision: 2,
      completedRevision: 1,
    ),
  ),
  members: [
    const CompanyMember(
      id: 'owner',
      displayName: 'Alex Morgan',
      role: 'owner',
      encryptionReady: true,
    ),
    const CompanyMember(id: 'member', displayName: 'Sam Rivera'),
    const CompanyMember(
      id: 'suspended',
      displayName: 'Taylor Reed',
      status: 'suspended',
    ),
    CompanyMember(
      id: 'expired',
      status: 'invited',
      invitationFingerprint: 'EXPIRED1234',
      invitationExpiresAt: DateTime.utc(2000),
    ),
    CompanyMember(
      id: 'future',
      status: 'invited',
      invitationFingerprint: 'FUTURE1234',
      invitationExpiresAt: DateTime.utc(2099),
    ),
  ],
  groups: const [
    CompanyGroup(
      id: 'finance',
      name: 'Finance',
      description: 'Invoices and purchasing',
    ),
    CompanyGroup(id: 'design', name: 'Design'),
  ],
);

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory('../.audit/business-previews');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}
