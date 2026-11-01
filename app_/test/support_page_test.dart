import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cloud_storage/src/support/support_page.dart';
import 'package:cloud_storage/src/legal/legal_documents_page.dart';

void main() {
  testWidgets('support email has visible recovery when the handler fails', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'no-handler'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SupportPage()));
    await tester.tap(find.text('Email RonikCloud support'));
    await tester.pumpAndSettle();
    expect(
      find.text('Email support at support@ronikcloud.com.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('public legal documents identify the controller', () {
    expect(LegalDocuments.legalVersion, '2026-09-10');
    expect(
      LegalDocuments.controllerIdentity,
      'Tomáš Názler, 24. dubna 145, Zeleice 664 43, Czech Republic',
    );
    expect(LegalDocuments.privacy.lastUpdated, 'October 16, 2026');
    expect(
      LegalDocuments.privacy.sections
          .expand((section) => section.paragraphs)
          .join(' '),
      contains(LegalDocuments.controllerIdentity),
    );
    expect(
      LegalDocuments.privacy.sections
          .expand((section) => section.bullets)
          .join(' '),
      contains('required and completed reconciliation counters'),
    );
    expect(
      LegalDocuments.privacy.sections
          .expand((section) => section.bullets)
          .join(' '),
      allOf(
        contains('Password-share operational data'),
        contains('password-derived verifier'),
        contains('no recipient, filename, token, or source-file identifier'),
      ),
    );

    final termsText = LegalDocuments.terms.sections
        .expand((section) => [...section.paragraphs, ...section.bullets])
        .join(' ');
    expect(termsText, contains('never receives or stores a full card number'));
    expect(termsText, contains('Canceling renewal'));
    expect(termsText, isNot(contains('should be reviewed by counsel')));

    final cancellationText = LegalDocuments.cancellationRefund.sections
        .expand((section) => [...section.paragraphs, ...section.bullets])
        .join(' ');
    expect(cancellationText, contains('does not automatically issue a refund'));
    expect(
      cancellationText,
      contains('verified linked Stripe customer profile'),
    );
    expect(cancellationText, contains('does not cancel an Apple subscription'));
    expect(
      cancellationText,
      contains('does not immediately sign the user out'),
    );
    expect(cancellationText, contains('within two Czech business days'));
    expect(cancellationText, contains('When a verified closure is completed'));
    expect(
      cancellationText,
      isNot(contains('immediately ends RonikCloud access')),
    );

    final privacyText = LegalDocuments.privacy.sections
        .expand((section) => [...section.paragraphs, ...section.bullets])
        .join(' ');
    expect(privacyText, contains('Deleted-account suppression data'));
    expect(privacyText, contains('Account-closure request data'));
    expect(privacyText, contains('support-notification delivery status'));
    expect(privacyText, contains('notification timestamps and attempt count'));
    expect(privacyText, contains('no email copy, free-text reason'));
    expect(privacyText, contains('expiry 90 days after resolution'));
    expect(privacyText, contains('After deletion succeeds'));
    expect(privacyText, contains('assigned an expiry 400 days'));
    expect(privacyText, contains('assigned a 48-hour expiry'));
    expect(privacyText, contains('Firebase-user-ID-addressed'));
    expect(privacyText, contains('If closure is incomplete'));
    expect(privacyText, contains('delayed maintenance run'));

    final retentionText = LegalDocuments.dataRetention.sections
        .expand((section) => [...section.paragraphs, ...section.bullets])
        .join(' ');
    expect(retentionText, contains('personal stored file objects'));
    expect(retentionText, contains('does not immediately change sign-in'));
    expect(retentionText, contains('pending request has no automatic expiry'));
    expect(retentionText, contains('expiry 90 days after resolution'));
    expect(retentionText, contains('After deletion succeeds'));
    expect(retentionText, contains('assigned an expiry 400 days'));
    expect(retentionText, contains('assigned a 48-hour expiry'));
    expect(
      retentionText,
      contains('closing-state deletion and enforcement records remain'),
    );
    expect(
      retentionText,
      contains('Scheduled maintenance removes completed-deletion records'),
    );
    expect(retentionText, contains('delayed maintenance run'));

    final subprocessorText = LegalDocuments.subprocessors.sections
        .expand((section) => [...section.paragraphs, ...section.bullets])
        .join(' ');
    expect(subprocessorText, contains('support operational notifications'));
    expect(subprocessorText, contains('opaque closure-request code'));
    expect(subprocessorText, contains('not a raw Firebase user ID'));
  });

  testWidgets('support page exposes contact and account guidance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SupportPage()));

    expect(find.text('RonikCloud Support'), findsOneWidget);
    expect(find.text(SupportPage.supportEmail), findsOneWidget);
    expect(find.text('Protect your account'), findsOneWidget);
    expect(find.text('Account and data controls'), findsOneWidget);
    expect(find.text('Payment-detail privacy'), findsOneWidget);
    expect(find.text('Stripe refund or billing help'), findsOneWidget);
    expect(find.text('Request Apple refund'), findsOneWidget);
    expect(
      find.text('Your Support code from Data safety center > Privacy.'),
      findsOneWidget,
    );
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Request account closure'), findsOneWidget);
    expect(find.text('Cancellation and refunds'), findsOneWidget);
  });
}
