import 'package:cloud_storage/src/business/company_admin_page.dart';
import 'package:cloud_storage/src/business/company_admin_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('admin invitation collects policy but no recipient identity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <String, Map<String, Object?>>{};
    final service = CompanyAdminService(
      callable: (functionName, payload) async {
        calls[functionName] = Map<String, Object?>.from(payload);
        return _dashboard(
          pendingInvitation: functionName == 'addCompanyMember',
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CompanyAdminPage(
          auth: MockFirebaseAuth(),
          firestore: FakeFirebaseFirestore(),
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add user'));
    await tester.pumpAndSettle();

    expect(find.text('Invite company user'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    expect(
      find.textContaining('does not ask for an email address'),
      findsOneWidget,
    );
    expect(find.textContaining('recipient must claim it'), findsOneWidget);

    await tester.tap(find.text('Generate code'));
    await tester.pumpAndSettle();

    expect(calls['addCompanyMember'], isNot(contains('email')));
    expect(calls['addCompanyMember'], isNot(contains('displayName')));
    expect(calls['addCompanyMember']?['invitationMode'], 'token_v2');
    expect(find.text('Share the one-time invitation code'), findsOneWidget);
    expect(
      find.textContaining('No email address or account lookup'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Anyone with this code can claim'),
      findsOneWidget,
    );
  });

  testWidgets('pending invitation has an explicit atomic revoke flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <String, Map<String, Object?>>{};
    final service = CompanyAdminService(
      callable: (functionName, payload) async {
        calls[functionName] = Map<String, Object?>.from(payload);
        return _dashboard(
          pendingInvitation: false,
          pendingMember: functionName != 'revokeCompanyInvitation',
        );
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CompanyAdminPage(
          auth: MockFirebaseAuth(),
          firestore: FakeFirebaseFirestore(),
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Revoke invitation'), findsOneWidget);
    await tester.tap(find.byTooltip('Revoke invitation'));
    await tester.pumpAndSettle();

    expect(find.text('Revoke this invitation?'), findsOneWidget);
    expect(
      find.textContaining('will stop working immediately'),
      findsOneWidget,
    );
    expect(find.textContaining('No active member is removed'), findsOneWidget);
    await tester.tap(find.text('Revoke code'));
    await tester.pumpAndSettle();

    expect(calls['revokeCompanyInvitation'], <String, Object?>{
      'memberId': 'invite_opaque_member',
    });
    expect(find.byTooltip('Revoke invitation'), findsNothing);
  });
}

Map<String, Object?> _dashboard({
  required bool pendingInvitation,
  bool pendingMember = false,
}) {
  return <String, Object?>{
    'company': <String, Object?>{
      'id': 'company-1',
      'name': 'Protected company',
      'status': 'active',
      'storagePolicy': <String, Object?>{},
    },
    'currentMember': <String, Object?>{
      'id': 'owner-1',
      'uid': 'owner-1',
      'role': 'owner',
      'status': 'active',
    },
    'canCreate': false,
    'canManage': true,
    'members': <Object?>[
      if (pendingMember)
        <String, Object?>{
          'id': 'invite_opaque_member',
          'role': 'member',
          'status': 'invited',
          'invitationFingerprint': 'A1B2C3D4E5',
          'invitationExpiresAt': '2026-08-09T12:00:00.000Z',
        },
    ],
    'groups': const <Object?>[],
    'accessPatternsScope': 'business_v1',
    'accessPatternsComplete': true,
    'accessPatterns': const <Object?>[],
    'auditLogsScope': 'business_privacy_v2',
    'auditLogsComplete': true,
    'auditLogs': const <Object?>[],
    if (pendingInvitation)
      'pendingInvitation': <String, Object?>{
        'version': 1,
        'code': 'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc',
        'fingerprint': 'A1B2C3D4E5',
        'expiresAt': '2026-08-09T12:00:00.000Z',
      },
  };
}
