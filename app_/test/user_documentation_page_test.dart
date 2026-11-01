import 'package:cloud_storage/src/documentation/user_documentation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('encryption topic documents the implemented standards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: UserDocumentationPage(initialTopic: 'encryption'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RonikCloud Documentation'), findsOneWidget);
    expect(find.text('Encryption standards and boundaries'), findsOneWidget);
    expect(find.text('AES-256-CTR with HMAC-SHA-256'), findsOneWidget);
    expect(find.text('AES-256-GCM'), findsNWidgets(2));
    expect(find.text('Folder labels'), findsOneWidget);
    expect(
      find.textContaining('wrapped separately for each authorized member'),
      findsOneWidget,
    );
    expect(find.text('PBKDF2-HMAC-SHA-256'), findsOneWidget);
    expect(find.textContaining('300,000 iterations'), findsOneWidget);
    expect(
      find.textContaining('Encrypted file, Secure file, or Encrypted folder'),
      findsOneWidget,
    );
    expect(
      find.textContaining('never fall back to the Personal password-derived'),
      findsOneWidget,
    );
    expect(find.textContaining('canonical encrypted label'), findsOneWidget);
    expect(
      find.textContaining('still require an authorized device'),
      findsOneWidget,
    );
    expect(
      find.textContaining('not a claim of formal certification'),
      findsOneWidget,
    );
  });

  testWidgets('documentation tabs fit a narrow mobile viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: UserDocumentationPage()));
    await tester.pumpAndSettle();

    expect(find.text('Start here'), findsOneWidget);
    expect(find.text('Encryption'), findsOneWidget);
    expect(find.text('Storage & sync'), findsOneWidget);
    expect(find.text('Sharing'), findsOneWidget);
    expect(find.text('Account & privacy'), findsOneWidget);
    expect(find.text('Platforms'), findsOneWidget);
    expect(find.text('Start using RonikCloud'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform documentation links to downloads and support', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: UserDocumentationPage(initialTopic: 'platforms')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Platforms, installation, and support'), findsOneWidget);
    expect(find.text('View platform downloads'), findsOneWidget);
    expect(find.text('Get help'), findsOneWidget);
    expect(find.text('Windows and Linux'), findsOneWidget);
  });

  testWidgets('storage documentation explains private provider recovery', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: UserDocumentationPage(initialTopic: 'storage-sync'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Large photos and browser uploads'), findsOneWidget);
    expect(find.textContaining('small repeatable slices'), findsOneWidget);
    expect(
      find.textContaining('capped, decoded, and normalized'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Unlock or retry image preview'),
      findsOneWidget,
    );
    expect(find.textContaining('neutral opaque storage names'), findsOneWidget);
    expect(
      find.textContaining('does not record whether a file has a preview'),
      findsOneWidget,
    );
    expect(find.textContaining('automatic finalization'), findsOneWidget);
    expect(find.text('Safe file and folder changes'), findsOneWidget);
    expect(
      find.textContaining('last verified workspace stays visible'),
      findsOneWidget,
    );
    expect(
      find.textContaining('does not display provider responses'),
      findsOneWidget,
    );
    expect(find.text('Private provider import recovery'), findsOneWidget);
    expect(
      find.textContaining('storage provider rejects sign-in'),
      findsOneWidget,
    );
    expect(find.textContaining('Completed RonikCloud uploads'), findsOneWidget);
  });

  testWidgets('Business documentation explains minimal cross-device state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: UserDocumentationPage(initialTopic: 'sharing')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Teams, comments, and reviews'), findsOneWidget);
    expect(find.text('Confirm sensitive Business changes'), findsOneWidget);
    expect(find.text('Reliable private Business history'), findsOneWidget);
    expect(find.textContaining('verified empty history'), findsOneWidget);
    expect(
      find.textContaining('load the authoritative result'),
      findsOneWidget,
    );
    expect(
      find.textContaining('required/completed revision counters'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'does not receive the reminder reason, member, file, or label',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('secret-derived proof'), findsOneWidget);
    expect(find.textContaining('without the password or private fragment key'), findsOneWidget);
    expect(find.textContaining('your own email app'), findsOneWidget);
    expect(find.text('Private link recovery'), findsOneWidget);
    expect(
      find.textContaining('never display an API response body'),
      findsOneWidget,
    );
    expect(find.textContaining('visible Retry action'), findsOneWidget);
    expect(find.text('Safe Business refresh'), findsOneWidget);
    expect(
      find.textContaining('keeps the last verified encrypted workspace'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'tracked independently and merged by opaque record ID',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('source categories needed to rebuild that split'),
      findsOneWidget,
    );
    expect(find.textContaining('quota contribution'), findsOneWidget);
    expect(
      find.textContaining('member IDs, object references, filenames'),
      findsOneWidget,
    );

    expect(find.text('Safe collaboration recovery'), findsOneWidget);
    expect(
      find.textContaining('never copies a provider response'),
      findsOneWidget,
    );
    expect(find.textContaining('unavailable with Retry'), findsOneWidget);
    expect(find.textContaining('same encrypted payload'), findsOneWidget);
    expect(find.textContaining('legacy-content fingerprint'), findsOneWidget);
  });

  testWidgets('privacy documentation explains minimal automatic diagnostics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: UserDocumentationPage(initialTopic: 'account-privacy'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account security and privacy'), findsOneWidget);
    expect(find.text('Private failure recovery'), findsOneWidget);
    expect(find.textContaining('does not copy exception text'), findsOneWidget);
    expect(find.textContaining('Use the visible Retry action'), findsOneWidget);
    expect(
      find.textContaining('billing-management action leaves current access'),
      findsOneWidget,
    );
    expect(
      find.textContaining('App Store purchase remains available to restore'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Automatic diagnostics are off by default'),
      findsOneWidget,
    );
    expect(
      find.textContaining('do not supply readable company labels'),
      findsOneWidget,
    );
    expect(
      find.textContaining('labels decrypted for your authorized session'),
      findsOneWidget,
    );
    expect(
      find.textContaining('not an account ID or Support code'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Authentication is used transiently'),
      findsOneWidget,
    );
    expect(find.textContaining('for at most 30 days'), findsOneWidget);
  });
}
