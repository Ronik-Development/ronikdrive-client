import 'dart:convert';

import 'package:cloud_storage/src/analytics/growth_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends only a coarse allowlisted event payload', () async {
    http.Request? captured;
    final analytics = GrowthAnalytics(
      endpoint: Uri.parse('https://api.example.test/growth/events'),
      client: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true}', 202);
      }),
    );

    final recorded = await analytics.record(
      event: GrowthEvent.checkoutStarted,
      source: GrowthSource.paidSearch,
      properties: const GrowthEventProperties(
        plan: GrowthPlan.pro,
        billingInterval: GrowthBillingInterval.yearly,
      ),
    );

    expect(recorded, isTrue);
    expect(captured, isNotNull);
    expect(captured!.url.path, '/growth/events');
    expect(captured!.headers['content-type'], startsWith('application/json'));
    final payload = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(payload, <String, dynamic>{
      'event': 'checkout_started',
      'source': 'paid_search',
      'properties': <String, dynamic>{
        'plan': 'pro',
        'billing_interval': 'yearly',
      },
    });
    expect(payload.containsKey('uid'), isFalse);
    expect(payload.containsKey('email'), isFalse);
    expect(payload.containsKey('url'), isFalse);
    expect(payload.containsKey('referrer'), isFalse);
    expect(payload.containsKey('user_agent'), isFalse);
  });

  test('sends a privacy-safe tester referral click', () async {
    http.Request? captured;
    final analytics = GrowthAnalytics(
      endpoint: Uri.parse('https://api.example.test/growth/events'),
      client: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true}', 202);
      }),
    );

    final recorded = await analytics.record(
      event: GrowthEvent.ctaClick,
      source: GrowthSource.organicSocial,
      properties: const GrowthEventProperties(
        placement: GrowthPlacement.testerReferral,
        channel: GrowthChannel.linkedin,
        entryPage: GrowthEntryPage.secureCloudStorage,
        ctaPlacement: GrowthCtaPlacement.postSignupReferral,
      ),
    );

    expect(recorded, isTrue);
    expect(jsonDecode(captured!.body), <String, dynamic>{
      'event': 'cta_click',
      'source': 'organic_social',
      'properties': <String, dynamic>{
        'placement': 'tester_referral',
        'channel': 'linkedin',
        'entry_page': 'secure_cloud_storage',
        'cta_placement': 'post_signup_referral',
      },
    });
    expect(captured!.body, isNot(contains('email')));
    expect(captured!.body, isNot(contains('utm_')));
  });

  test('sends a comparable privacy-safe tester signup start', () async {
    http.Request? captured;
    final analytics = GrowthAnalytics(
      endpoint: Uri.parse('https://api.example.test/growth/events'),
      client: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true}', 202);
      }),
    );

    final recorded = await analytics.record(
      event: GrowthEvent.testerSignupStarted,
      source: GrowthSource.organicSearch,
      properties: const GrowthEventProperties(
        placement: GrowthPlacement.testerPage,
        channel: GrowthChannel.organicSearch,
        entryPage: GrowthEntryPage.secureCloudStorage,
        ctaPlacement: GrowthCtaPlacement.hero,
      ),
    );

    expect(recorded, isTrue);
    expect(jsonDecode(captured!.body), <String, dynamic>{
      'event': 'tester_signup_started',
      'source': 'organic_search',
      'properties': <String, dynamic>{
        'placement': 'tester_page',
        'channel': 'organic_search',
        'entry_page': 'secure_cloud_storage',
        'cta_placement': 'hero',
      },
    });
    expect(captured!.body, isNot(contains('https://')));
    expect(captured!.body, isNot(contains('utm_')));
  });

  test(
    'authenticated signup completion sends only the fixed outcome fields',
    () async {
      http.Request? captured;
      final analytics = GrowthAnalytics(
        endpoint: Uri.parse('https://api.example.test/growth/events'),
        signupCompletedEndpoint: Uri.parse(
          'https://api.example.test/growth/signup-completed',
        ),
        client: MockClient((request) async {
          captured = request;
          return http.Response('{"ok":true,"recorded":true}', 200);
        }),
      );

      final recorded = await analytics.recordAuthenticatedSignupCompleted(
        idToken: '  firebase-id-token  ',
        channel: GrowthChannel.linkedin,
        entryPage: GrowthEntryPage.secureCloudStorage,
        ctaPlacement: GrowthCtaPlacement.hero,
        authMethod: GrowthAuthMethod.emailPassword,
      );

      expect(recorded, isTrue);
      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/growth/signup-completed');
      expect(captured!.headers['authorization'], 'Bearer firebase-id-token');
      expect(captured!.headers['content-type'], startsWith('application/json'));
      final payload = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(payload, <String, dynamic>{
        'channel': 'linkedin',
        'entryPage': 'secure_cloud_storage',
        'ctaPlacement': 'hero',
        'authMethod': 'email_password',
      });
      expect(payload.containsKey('email'), isFalse);
      expect(payload.containsKey('uid'), isFalse);
      expect(payload.containsKey('source'), isFalse);
      expect(captured!.body, isNot(contains('utm_')));
    },
  );

  test(
    'authenticated signup completion rejects a blank token locally',
    () async {
      var requestCount = 0;
      final analytics = GrowthAnalytics(
        signupCompletedEndpoint: Uri.parse(
          'https://api.example.test/growth/signup-completed',
        ),
        client: MockClient((_) async {
          requestCount += 1;
          return http.Response('{}', 200);
        }),
      );

      expect(
        await analytics.recordAuthenticatedSignupCompleted(
          idToken: '   ',
          channel: GrowthChannel.unknown,
          entryPage: GrowthEntryPage.unknown,
          ctaPlacement: GrowthCtaPlacement.unknown,
          authMethod: GrowthAuthMethod.unknown,
        ),
        isFalse,
      );
      expect(requestCount, 0);
    },
  );

  test(
    'signup completion clears only on a successful body with server proof',
    () async {
      Future<AuthenticatedSignupCompletionResult> submit(
        int statusCode,
        String body,
      ) {
        final analytics = GrowthAnalytics(
          signupCompletedEndpoint: Uri.parse(
            'https://api.example.test/growth/signup-completed',
          ),
          client: MockClient((_) async => http.Response(body, statusCode)),
        );
        return analytics.submitAuthenticatedSignupCompleted(
          idToken: 'firebase-id-token',
          channel: GrowthChannel.linkedin,
          entryPage: GrowthEntryPage.secureCloudStorage,
          ctaPlacement: GrowthCtaPlacement.hero,
          authMethod: GrowthAuthMethod.emailPassword,
        );
      }

      expect(
        await submit(200, '{"ok":true,"recorded":true}'),
        AuthenticatedSignupCompletionResult.confirmed,
      );
      expect(
        await submit(
          200,
          '{"ok":true,"recorded":false,"reason":"already_recorded"}',
        ),
        AuthenticatedSignupCompletionResult.confirmed,
      );
      for (final response in <(int, String)>[
        (200, '{"ok":true}'),
        (200, '{"recorded":false,"reason":"account_unavailable"}'),
        (200, 'not-json'),
        (404, '{"recorded":true}'),
        (409, '{"reason":"already_recorded"}'),
        (429, '{"recorded":true}'),
        (503, '{"recorded":true}'),
      ]) {
        expect(
          await submit(response.$1, response.$2),
          AuthenticatedSignupCompletionResult.retryable,
          reason: '${response.$1} ${response.$2}',
        );
      }
    },
  );

  test(
    'signup completion retains retry state on network failure and timeout',
    () async {
      final networkFailure = GrowthAnalytics(
        signupCompletedEndpoint: Uri.parse(
          'https://api.example.test/growth/signup-completed',
        ),
        client: MockClient((request) async {
          throw http.ClientException('offline', request.url);
        }),
      );
      final timeout = GrowthAnalytics(
        signupCompletedEndpoint: Uri.parse(
          'https://api.example.test/growth/signup-completed',
        ),
        timeout: Duration.zero,
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return http.Response('{"recorded":true}', 200);
        }),
      );

      for (final analytics in <GrowthAnalytics>[networkFailure, timeout]) {
        expect(
          await analytics.submitAuthenticatedSignupCompleted(
            idToken: 'firebase-id-token',
            channel: GrowthChannel.linkedin,
            entryPage: GrowthEntryPage.secureCloudStorage,
            ctaPlacement: GrowthCtaPlacement.hero,
            authMethod: GrowthAuthMethod.emailPassword,
          ),
          AuthenticatedSignupCompletionResult.retryable,
        );
      }
    },
  );

  test('does not send an invalid event and property combination', () async {
    var requestCount = 0;
    final analytics = GrowthAnalytics(
      endpoint: Uri.parse('https://api.example.test/growth/events'),
      client: MockClient((_) async {
        requestCount += 1;
        return http.Response('{}', 202);
      }),
    );

    final recorded = await analytics.record(
      event: GrowthEvent.landingView,
      source: GrowthSource.direct,
      properties: const GrowthEventProperties(plan: GrowthPlan.basic),
    );

    expect(recorded, isFalse);
    expect(requestCount, 0);
  });

  test(
    'network and server failures never escape into the product flow',
    () async {
      final networkFailure = GrowthAnalytics(
        endpoint: Uri.parse('https://api.example.test/growth/events'),
        client: MockClient((request) async {
          throw http.ClientException('offline', request.url);
        }),
      );
      final serverFailure = GrowthAnalytics(
        endpoint: Uri.parse('https://api.example.test/growth/events'),
        client: MockClient((_) async => http.Response('{}', 503)),
      );

      expect(
        await networkFailure.record(
          event: GrowthEvent.ctaClick,
          source: GrowthSource.direct,
          properties: const GrowthEventProperties(
            placement: GrowthPlacement.hero,
          ),
        ),
        isFalse,
      );
      expect(
        await serverFailure.record(
          event: GrowthEvent.ctaClick,
          source: GrowthSource.direct,
        ),
        isFalse,
      );
    },
  );

  test('growth channel vocabulary and known aliases stay closed', () {
    expect(
      GrowthChannel.values.map((value) => value.wireName).toList(),
      <String>[
        'direct',
        'organic_search',
        'linkedin',
        'x',
        'reddit',
        'hacker_news',
        'product_hunt',
        'bluesky',
        'mastodon',
        'dev_community',
        'privacy_forum',
        'alternativeto',
        'saashub',
        'b2b_saas_market',
        'betabound',
        'crozdesk',
        'finderslist',
        'g2',
        'helperg',
        'launching_next',
        'peerlist',
        'pitchwall',
        'privacyfest',
        'productreveal',
        'startup_directory',
        'startup_starter_kit',
        'startupbase',
        'startupbuffer',
        'submitstartup',
        'uneed',
        'visalytica',
        'we_are_founders',
        'help_net_security',
        'the_register',
        'reviewer_outreach',
        'user_referral',
        'lifecycle_email',
        'paid_search',
        'paid_social',
        'other_referral',
        'product',
        'unknown',
      ],
    );

    const cases = <String, GrowthChannel>{
      'utm_source=linkedin&utm_medium=organic': GrowthChannel.linkedin,
      'utm_source=twitter&utm_medium=organic': GrowthChannel.x,
      'utm_source=bsky&utm_medium=organic': GrowthChannel.bluesky,
      'utm_source=hackernews&utm_medium=community': GrowthChannel.hackerNews,
      'utm_source=product-hunt&utm_medium=launch': GrowthChannel.productHunt,
      'utm_source=alternative_to&utm_medium=listing':
          GrowthChannel.alternativeTo,
      'utm_source=beta_bound&utm_medium=listing': GrowthChannel.betaBound,
      'utm_source=dev&utm_medium=community': GrowthChannel.devCommunity,
      'utm_source=dev.to&utm_medium=community': GrowthChannel.devCommunity,
      'utm_source=dev_to&utm_medium=community': GrowthChannel.devCommunity,
      'utm_source=dev_community_showdev&utm_medium=community':
          GrowthChannel.devCommunity,
      'utm_source=reviewer&utm_medium=outreach': GrowthChannel.reviewerOutreach,
      'utm_source=launchingnext&utm_medium=listing':
          GrowthChannel.launchingNext,
      'utm_source=beta_list&utm_medium=launch': GrowthChannel.startupDirectory,
      'utm_source=google&utm_medium=organic': GrowthChannel.organicSearch,
      'utm_medium=seo': GrowthChannel.organicSearch,
      'utm_source=network&utm_medium=paid_social': GrowthChannel.paidSocial,
      'utm_source=search&utm_medium=cpc': GrowthChannel.paidSearch,
      'utm_source=newsletter&utm_medium=email': GrowthChannel.lifecycleEmail,
      'utm_source=user_referral&utm_medium=referral':
          GrowthChannel.userReferral,
      'utm_source=unlisted_directory&utm_medium=listing':
          GrowthChannel.otherReferral,
      'utm_source=private-person&utm_medium=community': GrowthChannel.unknown,
    };
    for (final entry in cases.entries) {
      expect(
        growthChannelFromCampaignUri(
          Uri.parse('https://ronikcloud.com/?${entry.key}'),
        ),
        entry.value,
        reason: entry.key,
      );
    }
    expect(
      growthChannelFromCampaignUri(Uri.parse('https://ronikcloud.com/')),
      GrowthChannel.direct,
    );
  });

  test(
    'campaign attribution collapses arbitrary query strings to coarse sources',
    () {
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_medium=cpc&utm_campaign=secret',
          ),
        ),
        GrowthSource.paidSearch,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_medium=organic&utm_source=google',
          ),
        ),
        GrowthSource.organicSearch,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse('https://ronikcloud.com/?utm_medium=seo'),
        ),
        GrowthSource.organicSearch,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_medium=listing&utm_source=alternativeto',
          ),
        ),
        GrowthSource.referral,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/testers?utm_source=user_referral&'
            'utm_medium=referral&utm_campaign=founding_beta_2026&'
            'utm_content=tester_success',
          ),
        ),
        GrowthSource.userReferral,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_medium=listing&utm_source=saashub',
          ),
        ),
        GrowthSource.referral,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_medium=listing&'
            'utm_source=launching_next',
          ),
        ),
        GrowthSource.referral,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_medium=community&utm_source=reddit',
          ),
        ),
        GrowthSource.organicSocial,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_medium=community&utm_source=hacker_news',
          ),
        ),
        GrowthSource.organicSocial,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_medium=community&'
            'utm_source=privacy_forum',
          ),
        ),
        GrowthSource.organicSocial,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_medium=launch&utm_source=product_hunt',
          ),
        ),
        GrowthSource.organicSocial,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_medium=launch&'
            'utm_source=startup_directory',
          ),
        ),
        GrowthSource.referral,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_medium=outreach&utm_source=reviewer',
          ),
        ),
        GrowthSource.partner,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse('https://ronikcloud.com/?utm_medium=lifecycle'),
        ),
        GrowthSource.email,
      );
      expect(
        growthSourceFromCampaignUri(
          Uri.parse(
            'https://ronikcloud.com/?utm_campaign=unrecognized-free-text',
          ),
        ),
        GrowthSource.unknown,
      );
      expect(
        growthSourceFromCampaignUri(Uri.parse('https://ronikcloud.com/')),
        GrowthSource.direct,
      );
    },
  );

  test('entry routes and CTA locations collapse to fixed categories', () {
    const routeEntries = <String, GrowthEntryPage>{
      '/': GrowthEntryPage.home,
      '/testers': GrowthEntryPage.testers,
      '/download': GrowthEntryPage.download,
      '/resources': GrowthEntryPage.resources,
      '/secure-cloud-storage': GrowthEntryPage.secureCloudStorage,
      '/security-whitepaper': GrowthEntryPage.securityWhitepaper,
      '/encrypted-file-sharing': GrowthEntryPage.encryptedFileSharing,
      '/for-freelancers': GrowthEntryPage.freelancers,
      '/for-small-teams': GrowthEntryPage.smallTeams,
      '/private-cloud-backup': GrowthEntryPage.privateCloudBackup,
      '/secure-client-file-portal': GrowthEntryPage.secureClientFilePortal,
      '/encrypted-file-request': GrowthEntryPage.encryptedFileRequest,
      '/google-drive-client-side-encryption-alternative':
          GrowthEntryPage.googleDriveEncryptionAlternative,
      '/encrypted-wetransfer-alternative':
          GrowthEntryPage.encryptedWetransferAlternative,
      '/secure-file-sharing-accountants':
          GrowthEntryPage.secureFileSharingAccountants,
      '/dropbox-encryption-alternative':
          GrowthEntryPage.dropboxEncryptionAlternative,
      '/client-side-vs-server-side-encryption':
          GrowthEntryPage.clientSideVsServerSide,
      '/press-kit': GrowthEntryPage.pressKit,
    };
    for (final entry in routeEntries.entries) {
      expect(
        growthEntryPageFromUri(
          Uri.parse('https://ronikcloud.com${entry.key}?private=value#secret'),
        ),
        entry.value,
        reason: entry.key,
      );
    }
    expect(
      growthEntryPageFromUri(
        Uri.parse('https://ronikcloud.com/for-freelancers.html'),
      ),
      GrowthEntryPage.freelancers,
    );
    expect(
      growthEntryPageFromUri(
        Uri.parse('https://ronikcloud.com/custom/customer/account'),
      ),
      GrowthEntryPage.other,
    );
    final attribution = growthAttributionFromUri(
      Uri.parse(
        'https://ronikcloud.com/testers?utm_campaign=resources&'
        'utm_source=linkedin&utm_medium=organic',
      ),
    );
    expect(attribution.source, GrowthSource.organicSocial);
    expect(attribution.channel, GrowthChannel.linkedin);
    expect(attribution.entryPage, GrowthEntryPage.testers);
    expect(
      growthCtaPlacementFromCampaignUri(
        Uri.parse(
          'https://ronikcloud.com/testers?utm_content=hero_testers&'
          'private_identifier=abc',
        ),
      ),
      GrowthCtaPlacement.hero,
    );
    expect(
      growthCtaPlacementFromCampaignUri(
        Uri.parse('https://ronikcloud.com/testers?utm_content=user-9237'),
      ),
      GrowthCtaPlacement.unknown,
    );
  });

  test('first-touch session preserves one strict v2 attribution triple', () {
    final stored = <String, String>{};
    final session = GrowthAttributionSession(
      readValue: (key) => stored[key],
      writeValue: (key, value) => stored[key] = value,
    );

    final external = session.resolve(
      Uri.parse(
        'https://ronikcloud.com/secure-cloud-storage?utm_source=linkedin&'
        'utm_medium=organic&utm_campaign=founding_beta_2026&'
        'utm_content=private-post-id',
      ),
    );
    final internal = session.resolve(
      Uri.parse(
        'https://ronikcloud.com/testers?utm_source=organic&utm_medium=seo&'
        'utm_campaign=secure_cloud_storage&utm_content=hero_testers',
      ),
    );

    expect(external.isNewEntry, isTrue);
    expect(external.attribution.source, GrowthSource.organicSocial);
    expect(external.attribution.channel, GrowthChannel.linkedin);
    expect(external.attribution.entryPage, GrowthEntryPage.secureCloudStorage);
    expect(internal.isNewEntry, isFalse);
    expect(internal.attribution.source, GrowthSource.organicSocial);
    expect(internal.attribution.channel, GrowthChannel.linkedin);
    expect(internal.attribution.entryPage, GrowthEntryPage.secureCloudStorage);
    expect(stored.keys, <String>[growthAttributionSessionKey]);
    expect(jsonDecode(stored[growthAttributionSessionKey]!), <String, dynamic>{
      'source': 'organic_social',
      'channel': 'linkedin',
      'entry_page': 'secure_cloud_storage',
    });
    expect(stored.values.join(' '), isNot(contains('utm_')));
    expect(stored.values.join(' '), isNot(contains('private-post-id')));
    expect(stored.values.join(' '), isNot(contains('founding_beta_2026')));
  });

  test('legacy v1 values are ignored and invalid v2 is replaced', () {
    final stored = <String, String>{
      'ronikcloud.growth.source.v1': 'organic_social',
      'ronikcloud.growth.entry_page.v1': 'secure_cloud_storage',
      growthAttributionSessionKey:
          '{"source":"organic_social","channel":"private-user-123",'
          '"entry_page":"/customer/private/path"}',
    };
    final session = GrowthAttributionSession(
      readValue: (key) => stored[key],
      writeValue: (key, value) => stored[key] = value,
    );

    final resolution = session.resolve(
      Uri.parse('https://ronikcloud.com/testers?utm_campaign=private-value'),
    );

    expect(resolution.isNewEntry, isTrue);
    expect(resolution.attribution.source, GrowthSource.unknown);
    expect(resolution.attribution.channel, GrowthChannel.unknown);
    expect(resolution.attribution.entryPage, GrowthEntryPage.testers);
    expect(jsonDecode(stored[growthAttributionSessionKey]!), <String, dynamic>{
      'source': 'unknown',
      'channel': 'unknown',
      'entry_page': 'testers',
    });
    expect(stored['ronikcloud.growth.source.v1'], 'organic_social');
    expect(stored['ronikcloud.growth.entry_page.v1'], 'secure_cloud_storage');
  });

  test('v1 values alone never override a new first touch', () {
    final stored = <String, String>{
      'ronikcloud.growth.source.v1': 'organic_social',
      'ronikcloud.growth.entry_page.v1': 'secure_cloud_storage',
    };
    final session = GrowthAttributionSession(
      readValue: (key) => stored[key],
      writeValue: (key, value) => stored[key] = value,
    );

    final resolution = session.resolve(
      Uri.parse(
        'https://ronikcloud.com/download?utm_source=reddit&'
        'utm_medium=community',
      ),
    );

    expect(resolution.isNewEntry, isTrue);
    expect(resolution.attribution.source, GrowthSource.organicSocial);
    expect(resolution.attribution.channel, GrowthChannel.reddit);
    expect(resolution.attribution.entryPage, GrowthEntryPage.download);
  });
}
