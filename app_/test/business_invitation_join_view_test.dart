import 'package:cloud_storage/src/business/company_admin_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('company setup offers a privacy-explained invitation claim', (
    tester,
  ) async {
    final companyController = TextEditingController();
    final domainController = TextEditingController();
    final invitationController = TextEditingController();
    addTearDown(companyController.dispose);
    addTearDown(domainController.dispose);
    addTearDown(invitationController.dispose);
    var claims = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessCompanySetupView(
            nameController: companyController,
            domainController: domainController,
            invitationCodeController: invitationController,
            busy: false,
            onCreate: () {},
            onClaimInvitation: () => claims += 1,
          ),
        ),
      ),
    );

    expect(find.text('Join an existing company'), findsOneWidget);
    expect(find.textContaining('stores only a random hash'), findsOneWidget);
    expect(find.textContaining('expires after seven days'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).last,
      'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc',
    );
    await tester.scrollUntilVisible(
      find.text('Accept invitation'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Accept invitation'));
    await tester.pump();

    expect(claims, 1);
  });

  testWidgets('company setup remains scrollable on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final companyController = TextEditingController();
    final domainController = TextEditingController();
    final invitationController = TextEditingController();
    addTearDown(companyController.dispose);
    addTearDown(domainController.dispose);
    addTearDown(invitationController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessCompanySetupView(
            nameController: companyController,
            domainController: domainController,
            invitationCodeController: invitationController,
            busy: false,
            onCreate: () {},
            onClaimInvitation: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Accept invitation'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Accept invitation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
