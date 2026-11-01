import 'dart:convert';

import 'package:cloud_storage/l10n/app_localizations.dart';
import 'package:cloud_storage/src/analytics/growth_analytics.dart';
import 'package:cloud_storage/src/home/tester_access_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget _testerApp({
  required http.Client client,
  Uri? campaignUri,
  GrowthAttribution? attribution,
  GrowthCtaPlacement? ctaPlacement,
  Locale locale = const Locale('en'),
  TesterReferralShareHandler? referralShareHandler,
  TesterGrowthEventRecorder? growthEventRecorder,
  double textScale = 1,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routes: <String, WidgetBuilder>{
      '/download': (_) => const Scaffold(body: Text('Downloads')),
    },
    home: TesterAccessPage(
      client: client,
      campaignUri: campaignUri,
      attribution: attribution,
      ctaPlacement: ctaPlacement,
      referralShareHandler: referralShareHandler,
      growthEventRecorder: growthEventRecorder,
    ),
  );
}

http.Response _downloadStatusResponse({
  bool android = true,
  bool ios = true,
  bool macos = true,
  bool windows = false,
  bool linux = false,
}) {
  return http.Response(
    jsonEncode(<String, Object>{
      'platforms': <String, Object>{
        'android': <String, bool>{'available': android},
        'ios': <String, bool>{'available': ios},
        'macos': <String, bool>{'available': macos},
        'windows': <String, bool>{'available': windows},
        'linux': <String, bool>{'available': linux},
      },
    }),
    200,
  );
}

MockClient _successfulClient({void Function(http.Request)? onPost}) {
  return MockClient((request) async {
    if (request.method == 'GET') {
      return _downloadStatusResponse();
    }
    onPost?.call(request);
    return http.Response('{"emailSent":true}', 201);
  });
}

Future<void> _submitEmail(
  WidgetTester tester, {
  String email = 'tester@example.com',
}) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('tester-email-field')),
    email,
  );
  await tester.ensureVisible(
    find.byKey(const ValueKey<String>('tester-submit')),
  );
  await tester.tap(find.byKey(const ValueKey<String>('tester-submit')));
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in [const Locale('en'), const Locale('cs')]) {
    for (final width in [320.0, 800.0]) {
      testWidgets('tester channels and signup reflow at $width in $locale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _testerApp(client: _successfulClient(), locale: locale, textScale: 2),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final strings = AppLocalizations.of(
          tester.element(find.byType(TesterAccessPage)),
        )!;
        await tester.scrollUntilVisible(
          find.text(strings.testerCheckDownloads),
          350,
          scrollable: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
          maxScrolls: 60,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(strings.testerPlatformLinux), findsOneWidget);
      });
    }
  }

  testWidgets('tester page leads with a specific audience and primary ask', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testerApp(client: _successfulClient()));
    await tester.pumpAndSettle();

    expect(find.text('RonikCloud founding beta'), findsOneWidget);
    expect(find.text('Test one real file workflow'), findsOneWidget);
    expect(
      find.textContaining('freelancers, creators, consultants'),
      findsOneWidget,
    );
    expect(find.textContaining('non-critical copies'), findsOneWidget);
    expect(find.text('Request beta access'), findsNWidgets(2));
    expect(find.text('Participate in product testing'), findsOneWidget);
    expect(find.text('Receive weekly product news'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary signup form appears before the supporting workflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testerApp(client: _successfulClient()));
    await tester.pumpAndSettle();

    final submitTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('tester-submit')),
    );
    final workflowTop = tester.getTopLeft(
      find.text('What we ask from testers'),
    );

    expect(submitTop.dy, lessThan(workflowTop.dy));
  });

  testWidgets(
    'shows live platform availability without implying missing builds',
    (tester) async {
      await tester.pumpWidget(_testerApp(client: _successfulClient()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Available beta builds'),
        500,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Available beta builds'), findsOneWidget);
      expect(find.text('Available now'), findsNWidgets(3));
      expect(find.text('Not published'), findsNWidgets(2));
      expect(find.text('Google Play beta'), findsOneWidget);
      expect(find.text('Apple TestFlight beta'), findsNWidgets(2));
    },
  );

  testWidgets('states beta and independent-audit boundaries', (tester) async {
    await tester.pumpWidget(_testerApp(client: _successfulClient()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Founding-beta boundaries'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.textContaining('has not been independently audited'),
      findsOneWidget,
    );
    expect(
      find.textContaining('do not depend on RonikCloud as your only copy'),
      findsOneWidget,
    );
  });

  testWidgets('tester signup submits explicit consent and fixed attribution', (
    tester,
  ) async {
    http.Request? submittedRequest;
    final client = _successfulClient(
      onPost: (request) {
        submittedRequest = request;
      },
    );

    await tester.pumpWidget(
      _testerApp(
        client: client,
        campaignUri: Uri.parse(
          'https://ronikcloud.com/testers?utm_source=linkedin&'
          'utm_medium=organic&utm_campaign=founding_beta_2026&'
          'utm_content=private-free-text',
        ),
      ),
    );
    await _submitEmail(tester);

    expect(submittedRequest, isNotNull);
    expect(submittedRequest!.url.path, endsWith('/tester-signups'));
    final body = jsonDecode(submittedRequest!.body) as Map<String, dynamic>;
    expect(body, <String, dynamic>{
      'email': 'tester@example.com',
      'source': 'testers_page',
      'growthSource': 'organic_social',
      'channel': 'linkedin',
      'entryPage': 'testers',
      'ctaPlacement': 'unknown',
      'wantsProductNews': false,
      'wantsTesting': true,
    });
    expect(submittedRequest!.body, isNot(contains('founding_beta_2026')));
    expect(submittedRequest!.body, isNot(contains('private-free-text')));
    expect(
      find.textContaining('Beta access is reviewed manually'),
      findsOneWidget,
    );
  });

  testWidgets(
    'successful signup exposes a click-only privacy-safe referral loop',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? sharedMessage;
      Rect? sharedPositionOrigin;
      var shareCalls = 0;
      GrowthEvent? recordedEvent;
      GrowthSource? recordedSource;
      GrowthEventProperties? recordedProperties;

      await tester.pumpWidget(
        _testerApp(
          client: _successfulClient(),
          campaignUri: Uri.parse(
            'https://ronikcloud.com/testers?utm_source=linkedin&'
            'utm_medium=organic&utm_campaign=private-incoming-campaign&'
            'utm_content=private-incoming-content',
          ),
          referralShareHandler: (message, sharePositionOrigin) async {
            shareCalls += 1;
            sharedMessage = message;
            sharedPositionOrigin = sharePositionOrigin;
          },
          growthEventRecorder:
              ({required event, required source, required properties}) async {
                recordedEvent = event;
                recordedSource = source;
                recordedProperties = properties;
              },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('tester-referral-share')),
        findsNothing,
      );
      expect(shareCalls, 0);

      await _submitEmail(tester);

      final referralButton = find.byKey(
        const ValueKey<String>('tester-referral-share'),
      );
      expect(referralButton, findsOneWidget);
      expect(find.text('Invite one workflow peer'), findsOneWidget);
      expect(shareCalls, 0);

      await tester.ensureVisible(referralButton);
      final expectedShareOrigin = tester.getRect(referralButton);
      await tester.tap(referralButton);
      await tester.pumpAndSettle();

      expect(shareCalls, 1);
      expect(sharedPositionOrigin, expectedShareOrigin);
      expect(sharedMessage, isNotNull);
      expect(sharedMessage, contains(testerReferralUrl));
      expect(sharedMessage, contains('has not been independently audited'));
      expect(sharedMessage, contains('non-critical copies'));
      expect(sharedMessage, isNot(contains('tester@example.com')));
      expect(sharedMessage, isNot(contains('private-incoming-campaign')));
      expect(sharedMessage, isNot(contains('private-incoming-content')));
      expect(recordedEvent, GrowthEvent.ctaClick);
      expect(recordedSource, GrowthSource.organicSocial);
      expect(recordedProperties?.placement, GrowthPlacement.testerReferral);
      expect(recordedProperties?.channel, GrowthChannel.linkedin);
      expect(recordedProperties?.entryPage, GrowthEntryPage.testers);
      expect(
        recordedProperties?.ctaPlacement,
        GrowthCtaPlacement.postSignupReferral,
      );
    },
  );

  testWidgets('fixed referral URL submits only the user-referral category', (
    tester,
  ) async {
    http.Request? submittedRequest;
    await tester.pumpWidget(
      _testerApp(
        client: _successfulClient(
          onPost: (request) {
            submittedRequest = request;
          },
        ),
        campaignUri: Uri.parse(testerReferralUrl),
      ),
    );

    await _submitEmail(tester);

    final body = jsonDecode(submittedRequest!.body) as Map<String, dynamic>;
    expect(body['growthSource'], 'user_referral');
    expect(body['channel'], 'user_referral');
    expect(body['entryPage'], 'testers');
    expect(body['ctaPlacement'], 'post_signup_referral');
    expect(submittedRequest!.body, isNot(contains('founding_beta_2026')));
    expect(submittedRequest!.body, isNot(contains('tester_success')));
    expect(submittedRequest!.body, isNot(contains('utm_')));
  });

  testWidgets(
    'tester start and completion request keep first-touch route and CTA categories',
    (tester) async {
      http.Request? submittedRequest;
      final events = <GrowthEvent>[];
      final recordedProperties = <GrowthEventProperties>[];
      await tester.pumpWidget(
        _testerApp(
          client: _successfulClient(
            onPost: (request) {
              submittedRequest = request;
            },
          ),
          attribution: const GrowthAttribution(
            source: GrowthSource.organicSocial,
            channel: GrowthChannel.linkedin,
            entryPage: GrowthEntryPage.secureCloudStorage,
          ),
          ctaPlacement: GrowthCtaPlacement.hero,
          growthEventRecorder:
              ({required event, required source, required properties}) async {
                expect(source, GrowthSource.organicSocial);
                events.add(event);
                recordedProperties.add(properties);
              },
        ),
      );

      await _submitEmail(tester);

      expect(events, <GrowthEvent>[GrowthEvent.testerSignupStarted]);
      expect(recordedProperties.single.placement, GrowthPlacement.testerPage);
      expect(recordedProperties.single.channel, GrowthChannel.linkedin);
      expect(
        recordedProperties.single.entryPage,
        GrowthEntryPage.secureCloudStorage,
      );
      expect(recordedProperties.single.ctaPlacement, GrowthCtaPlacement.hero);
      final body = jsonDecode(submittedRequest!.body) as Map<String, dynamic>;
      expect(body['growthSource'], 'organic_social');
      expect(body['channel'], 'linkedin');
      expect(body['entryPage'], 'secure_cloud_storage');
      expect(body['ctaPlacement'], 'hero');
      expect(submittedRequest!.body, isNot(contains('https://')));
      expect(submittedRequest!.body, isNot(contains('utm_')));

      await _submitEmail(tester);
      expect(events, <GrowthEvent>[GrowthEvent.testerSignupStarted]);
    },
  );

  testWidgets('news-only success hides referral until a later testing opt-in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final submittedBodies = <Map<String, dynamic>>[];
    final events = <GrowthEvent>[];
    await tester.pumpWidget(
      _testerApp(
        client: _successfulClient(
          onPost: (request) {
            submittedBodies.add(
              jsonDecode(request.body) as Map<String, dynamic>,
            );
          },
        ),
        referralShareHandler: (_, _) async {},
        growthEventRecorder:
            ({required event, required source, required properties}) async {
              events.add(event);
            },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Participate in product testing'));
    await tester.tap(find.text('Receive weekly product news'));
    await tester.pump();
    await _submitEmail(tester);

    expect(submittedBodies.single['wantsTesting'], false);
    expect(submittedBodies.single['wantsProductNews'], true);
    expect(
      events.where((event) => event == GrowthEvent.testerSignupStarted),
      isEmpty,
    );
    expect(
      find.text('Your product news preference has been saved.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('tester-referral-share')),
      findsNothing,
    );

    await tester.tap(find.text('Participate in product testing'));
    await tester.pump();
    await _submitEmail(tester);

    expect(submittedBodies, hasLength(2));
    expect(submittedBodies.last['wantsTesting'], true);
    expect(
      events.where((event) => event == GrowthEvent.testerSignupStarted),
      <GrowthEvent>[GrowthEvent.testerSignupStarted],
    );
    expect(
      find.byKey(const ValueKey<String>('tester-referral-share')),
      findsOneWidget,
    );
  });

  testWidgets('analytics and share failures do not undo successful signup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testerApp(
        client: _successfulClient(),
        referralShareHandler: (_, _) async {
          throw StateError('share unavailable');
        },
        growthEventRecorder:
            ({required event, required source, required properties}) async {
              throw StateError('analytics unavailable');
            },
      ),
    );
    await _submitEmail(tester);

    final referralButton = find.byKey(
      const ValueKey<String>('tester-referral-share'),
    );
    await tester.ensureVisible(referralButton);
    await tester.tap(referralButton);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Beta access is reviewed manually'),
      findsOneWidget,
    );
    expect(referralButton, findsOneWidget);
    expect(
      find.text(
        'The share sheet could not be opened. Your beta request is still saved.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tester signup validates the email locally', (tester) async {
    var postCount = 0;
    final client = _successfulClient(
      onPost: (_) {
        postCount += 1;
      },
    );

    await tester.pumpWidget(_testerApp(client: client));
    await _submitEmail(tester, email: 'not-an-email');

    expect(postCount, 0);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('tester signup does not claim immediate Google Play access', (
    tester,
  ) async {
    await tester.pumpWidget(_testerApp(client: _successfulClient()));
    await _submitEmail(tester);

    expect(
      find.textContaining('Beta access is reviewed manually'),
      findsOneWidget,
    );
    expect(
      find.textContaining('You now have Google Play testing access.'),
      findsNothing,
    );
  });

  testWidgets('tester signup never displays an API response body', (
    tester,
  ) async {
    const privateServerDetail =
        'Bearer secret-token for private@example.com at /srv/customers/a';
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return _downloadStatusResponse();
      }
      return http.Response(
        jsonEncode(<String, String>{'detail': privateServerDetail}),
        500,
      );
    });

    await tester.pumpWidget(_testerApp(client: client));
    await _submitEmail(tester);

    expect(
      find.text('Unable to join the tester list. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining(privateServerDetail), findsNothing);
    expect(find.textContaining('secret-token'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('tester-referral-share')),
      findsNothing,
    );
  });

  testWidgets('tester conversion copy is localized in Czech', (tester) async {
    await tester.pumpWidget(
      _testerApp(
        client: _successfulClient(),
        locale: const Locale('cs'),
        referralShareHandler: (_, _) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Zakladatelská beta RonikCloud'), findsOneWidget);
    expect(
      find.text('Vyzkoušejte jeden skutečný postup se soubory'),
      findsOneWidget,
    );
    expect(find.text('Požádat o přístup do bety'), findsNWidgets(2));

    await _submitEmail(tester);

    expect(find.text('Pozvěte jednoho kolegu k testování'), findsOneWidget);
    expect(find.text('Pozvat jednoho člověka'), findsOneWidget);
  });
}
