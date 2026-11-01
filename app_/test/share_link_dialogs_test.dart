import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_storage/app_theme.dart';
import 'package:cloud_storage/src/share/share_email_service.dart';
import 'package:cloud_storage/src/share/share_link_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _privateLink = Uri.parse(
  'https://share.example.test/share/synthetic-share-token#key=${'A' * 43}',
);

Future<void> capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (!const bool.fromEnvironment('SHARE_CAPTURE')) return;
  final image =
      await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('build/review/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

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

  testWidgets(
    'creation defaults to password protection and validates recipient and custom password',
    (tester) async {
      ShareLinkDraft? created;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    created = await showDialog<ShareLinkDraft>(
                      context: context,
                      builder: (_) => const CreateShareLinkDialog(),
                    ),
                child: const Text('Share'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const Key('share-recipient-email')),
        'not an email',
      );
      await tester.tap(find.text('Create share link'));
      await tester.pumpAndSettle();
      expect(find.text('Enter one valid email address.'), findsOneWidget);
      expect(created, isNull);
      await tester.enterText(
        find.byKey(const Key('share-recipient-email')),
        'Recipient@example.test',
      );
      await tester.enterText(
        find.byKey(const Key('share-custom-password')),
        'short',
      );
      await tester.tap(find.text('Create share link'));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 12 characters.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('share-custom-password')),
        'a long synthetic password',
      );
      await tester.tap(find.text('Create share link'));
      await tester.pumpAndSettle();
      expect(created!.passwordProtected, isTrue);
      expect(created!.password, 'a long synthetic password');
      expect(created!.recipientEmail, 'Recipient@example.test');
      expect(created!.maxDownloads, 10);
      expect(created!.expiryDays, 7);
    },
  );
  testWidgets(
    'password-free selection explains own email app and keeps no stale password',
    (tester) async {
      ShareLinkDraft? created;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    created = await showDialog<ShareLinkDraft>(
                      context: context,
                      builder: (_) => const CreateShareLinkDialog(),
                    ),
                child: const Text('Share'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('share-custom-password')),
        'a long synthetic password',
      );
      await tapVisible(tester, find.byType(SwitchListTile));
      expect(find.byKey(const Key('share-custom-password')), findsNothing);
      expect(find.textContaining('your own email app'), findsOneWidget);
      await tester.tap(find.text('Create share link'));
      await tester.pumpAndSettle();
      expect(created!.passwordProtected, isFalse);
      expect(created!.password, isNull);
    },
  );
  testWidgets(
    'uncertain direct email retries same identity and preserves copy controls',
    (tester) async {
      final requests = <String>[];
      final copied = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareCreatedDialog(
              shareUrl: _privateLink.replace(fragment: ''),
              password: 'synthetic separate password',
              expiresAt: DateTime.utc(2099, 1, 1),
              maxDownloads: 10,
              recipientEmail: 'Recipient@example.test',
              copyText: (text) async => copied.add(text),
              sendPasswordLink:
                  ({required recipientEmail, required requestId}) async {
                    requests.add(requestId);
                    if (requests.length == 1) {
                      throw const ShareEmailException(
                        'Email acceptance could not be confirmed. Retry this send safely, or copy the link.',
                      );
                    }
                  },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Email link'));
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(copied.single, _privateLink.replace(fragment: '').toString());
      await tapVisible(tester, find.text('Retry email'));
      expect(requests, hasLength(2));
      expect(requests.first, requests.last);
      expect(find.textContaining('Delivery is not confirmed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find
                  .ancestor(
                    of: find.text('Email accepted'),
                    matching: find.byWidgetPredicate(
                      (widget) => widget is FilledButton,
                    ),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'password-free email never invokes backend and offers fallback when app missing',
    (tester) async {
      Uri? opened;
      var directSends = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareCreatedDialog(
              shareUrl: _privateLink,
              password: null,
              expiresAt: DateTime.utc(2099, 1, 1),
              maxDownloads: 10,
              recipientEmail: 'Recipient@example.test',
              sendPasswordLink:
                  ({required recipientEmail, required requestId}) async =>
                      directSends++,
              emailOpener: (uri) async {
                opened = uri;
                return false;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Open email app'));
      expect(directSends, 0);
      expect(
        opened!.queryParameters['body'],
        contains(_privateLink.toString()),
      );
      expect(
        find.textContaining('No email app could be opened'),
        findsOneWidget,
      );
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Open email app'), findsOneWidget);
    },
  );
  testWidgets('clipboard failure keeps selectable complete link without exposing provider errors', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ShareCreatedDialog(
      shareUrl: _privateLink, password: null, expiresAt: DateTime.utc(2099, 1, 1), maxDownloads: 10,
      sendPasswordLink: ({required recipientEmail, required requestId}) async {},
      copyText: (_) async => throw StateError('private@example.test provider-secret'),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Clipboard access is unavailable'), findsOneWidget);
    expect(find.textContaining('provider-secret'), findsNothing);
    await tapVisible(tester, find.text('Link and access details'));
    expect(find.byWidgetPredicate((widget) => widget is SelectableText && widget.data == _privateLink.toString()), findsOneWidget);
  });
  testWidgets(
    'account change hides link and password and prevents later sends',
    (tester) async {
      final sessions = StreamController<bool>();
      var sends = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareCreatedDialog(
              shareUrl: _privateLink.replace(fragment: ''),
              password: 'synthetic separate password',
              expiresAt: DateTime.utc(2099, 1, 1),
              maxDownloads: 10,
              recipientEmail: 'Recipient@example.test',
              sessionStates: sessions.stream,
              sendPasswordLink:
                  ({required recipientEmail, required requestId}) async =>
                      sends++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      sessions.add(false);
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('Copy password'), findsNothing);
      expect(find.text('Email link'), findsNothing);
      expect(
        find.textContaining('sign-in or sharing access changed'),
        findsOneWidget,
      );
      expect(sends, 0);
      await tester.pumpWidget(const SizedBox());
      unawaited(sessions.close());
      await tester.pump();
    },
  );

  for (final compact in [false, true]) {
    for (final mode in ['create', 'password', 'link']) {
      testWidgets(
        'share $mode layout ${compact ? 'compact at 200 percent' : 'desktop'}',
        (tester) async {
          tester.view.physicalSize = compact
              ? const Size(390, 844)
              : const Size(1400, 1000);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = compact ? 2 : 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: AppTheme.light(),
                home: Scaffold(
                  body: mode == 'create'
                      ? const CreateShareLinkDialog()
                      : ShareCreatedDialog(
                          shareUrl: mode == 'password'
                              ? _privateLink.replace(fragment: '')
                              : _privateLink,
                          password: mode == 'password'
                              ? 'synthetic-separate-password'
                              : null,
                          expiresAt: DateTime.utc(2099, 1, 1),
                          maxDownloads: 10,
                          recipientEmail: 'Recipient@example.test',
                          sendPasswordLink:
                              ({
                                required recipientEmail,
                                required requestId,
                              }) async {},
                        ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.runAsync(
            () => capture(
              tester,
              boundary,
              'share-$mode-${compact ? 'compact' : 'desktop'}',
            ),
          );
          await tester.ensureVisible(
            find.text(
              mode == 'create'
                  ? 'Create share link'
                  : mode == 'password'
                  ? 'Email link'
                  : 'Open email app',
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
