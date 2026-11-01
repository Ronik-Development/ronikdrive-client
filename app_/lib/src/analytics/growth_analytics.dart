import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../shared/release_runtime_config.dart';
import 'growth_attribution_session_stub.dart'
    if (dart.library.js_interop) 'growth_attribution_session_web.dart';

const String growthAttributionSessionKey = 'ronikcloud.growth.attribution.v2';

enum GrowthEvent {
  landingView('landing_view'),
  ctaClick('cta_click'),
  pricingPeriodSelected('pricing_period_selected'),
  pricingPlanSelected('pricing_plan_selected'),
  signupStarted('signup_started'),
  signupCompleted('signup_completed'),
  activationCompleted('activation_completed'),
  checkoutStarted('checkout_started'),
  checkoutCompleted('checkout_completed'),
  downloadStarted('download_started'),
  testerSignupStarted('tester_signup_started'),
  testerSignupCompleted('tester_signup_completed');

  const GrowthEvent(this.wireName);

  final String wireName;
}

enum GrowthSource {
  direct('direct'),
  organicSearch('organic_search'),
  organicSocial('organic_social'),
  referral('referral'),
  userReferral('user_referral'),
  email('email'),
  paidSearch('paid_search'),
  paidSocial('paid_social'),
  partner('partner'),
  product('product'),
  unknown('unknown');

  const GrowthSource(this.wireName);

  final String wireName;
}

/// Closed, low-cardinality first-touch acquisition channels.
///
/// Only these wire values may leave the client. Raw campaign values, URLs,
/// referrers, and visitor identifiers are deliberately excluded.
enum GrowthChannel {
  direct('direct'),
  organicSearch('organic_search'),
  linkedin('linkedin'),
  x('x'),
  reddit('reddit'),
  hackerNews('hacker_news'),
  productHunt('product_hunt'),
  bluesky('bluesky'),
  mastodon('mastodon'),
  devCommunity('dev_community'),
  privacyForum('privacy_forum'),
  alternativeTo('alternativeto'),
  saasHub('saashub'),
  b2bSaasMarket('b2b_saas_market'),
  betaBound('betabound'),
  crozdesk('crozdesk'),
  findersList('finderslist'),
  g2('g2'),
  helperG('helperg'),
  launchingNext('launching_next'),
  peerlist('peerlist'),
  pitchwall('pitchwall'),
  privacyFest('privacyfest'),
  productReveal('productreveal'),
  startupDirectory('startup_directory'),
  startupStarterKit('startup_starter_kit'),
  startupBase('startupbase'),
  startupBuffer('startupbuffer'),
  submitStartup('submitstartup'),
  uneed('uneed'),
  visalytica('visalytica'),
  weAreFounders('we_are_founders'),
  helpNetSecurity('help_net_security'),
  theRegister('the_register'),
  reviewerOutreach('reviewer_outreach'),
  userReferral('user_referral'),
  lifecycleEmail('lifecycle_email'),
  paidSearch('paid_search'),
  paidSocial('paid_social'),
  otherReferral('other_referral'),
  product('product'),
  unknown('unknown');

  const GrowthChannel(this.wireName);

  final String wireName;
}

enum GrowthPlacement {
  header('header'),
  hero('hero'),
  pricing('pricing'),
  footer('footer'),
  mobileNav('mobile_nav'),
  downloadPage('download_page'),
  testerPage('tester_page'),
  testerReferral('tester_referral'),
  subscriptionGate('subscription_gate'),
  checkout('checkout'),
  onboarding('onboarding'),
  workspace('workspace'),
  unknown('unknown');

  const GrowthPlacement(this.wireName);

  final String wireName;
}

/// Fixed first-touch entry routes used for aggregate acquisition reporting.
///
/// These values intentionally mirror the existing snake_case campaign
/// vocabulary. No URL, query string, title, or arbitrary route is retained.
enum GrowthEntryPage {
  home('home'),
  testers('testers'),
  download('download'),
  resources('resources'),
  secureCloudStorage('secure_cloud_storage'),
  securityWhitepaper('security_whitepaper'),
  encryptedFileSharing('encrypted_file_sharing'),
  freelancers('freelancers'),
  smallTeams('small_teams'),
  privateCloudBackup('private_cloud_backup'),
  secureClientFilePortal('secure_client_file_portal'),
  encryptedFileRequest('encrypted_file_request'),
  googleDriveEncryptionAlternative('google_drive_encryption_alternative'),
  encryptedWetransferAlternative('encrypted_wetransfer_alternative'),
  secureFileSharingAccountants('secure_file_sharing_accountants'),
  dropboxEncryptionAlternative('dropbox_encryption_alternative'),
  clientSideVsServerSide('client_side_vs_server_side'),
  pressKit('press_kit'),
  other('other'),
  unknown('unknown');

  const GrowthEntryPage(this.wireName);

  final String wireName;
}

/// Fixed CTA locations. This is separate from [GrowthPlacement] so the new
/// acquisition funnel can be compared while older aggregate fields remain
/// compatible.
enum GrowthCtaPlacement {
  direct('direct'),
  header('header'),
  hero('hero'),
  inline('inline'),
  finalCta('final'),
  footer('footer'),
  postSignupReferral('post_signup_referral'),
  unknown('unknown');

  const GrowthCtaPlacement(this.wireName);

  final String wireName;
}

class GrowthAttribution {
  const GrowthAttribution({
    required this.source,
    required this.channel,
    required this.entryPage,
  });

  final GrowthSource source;
  final GrowthChannel channel;
  final GrowthEntryPage entryPage;
}

class GrowthAttributionResolution {
  const GrowthAttributionResolution({
    required this.attribution,
    required this.isNewEntry,
  });

  final GrowthAttribution attribution;
  final bool isNewEntry;
}

enum GrowthPlan {
  basic('basic'),
  pro('pro'),
  ultra('ultra'),
  unknown('unknown');

  const GrowthPlan(this.wireName);

  final String wireName;
}

enum GrowthBillingInterval {
  monthly('monthly'),
  yearly('yearly'),
  unknown('unknown');

  const GrowthBillingInterval(this.wireName);

  final String wireName;
}

enum GrowthPlatform {
  web('web'),
  android('android'),
  ios('ios'),
  windows('windows'),
  macos('macos'),
  linux('linux'),
  unknown('unknown');

  const GrowthPlatform(this.wireName);

  final String wireName;
}

enum GrowthAuthMethod {
  emailPassword('email_password'),
  google('google'),
  apple('apple'),
  emailLink('email_link'),
  unknown('unknown');

  const GrowthAuthMethod(this.wireName);

  final String wireName;
}

enum GrowthSurface {
  website('website'),
  webApp('web_app'),
  desktopApp('desktop_app'),
  mobileApp('mobile_app'),
  unknown('unknown');

  const GrowthSurface(this.wireName);

  final String wireName;
}

class GrowthEventProperties {
  const GrowthEventProperties({
    this.placement,
    this.channel,
    this.entryPage,
    this.ctaPlacement,
    this.plan,
    this.billingInterval,
    this.platform,
    this.authMethod,
    this.surface,
  });

  final GrowthPlacement? placement;
  final GrowthChannel? channel;
  final GrowthEntryPage? entryPage;
  final GrowthCtaPlacement? ctaPlacement;
  final GrowthPlan? plan;
  final GrowthBillingInterval? billingInterval;
  final GrowthPlatform? platform;
  final GrowthAuthMethod? authMethod;
  final GrowthSurface? surface;

  Map<String, String>? toJsonFor(GrowthEvent event) {
    final values = <String, String>{
      if (placement != null) 'placement': placement!.wireName,
      if (channel != null) 'channel': channel!.wireName,
      if (entryPage != null) 'entry_page': entryPage!.wireName,
      if (ctaPlacement != null) 'cta_placement': ctaPlacement!.wireName,
      if (plan != null) 'plan': plan!.wireName,
      if (billingInterval != null)
        'billing_interval': billingInterval!.wireName,
      if (platform != null) 'platform': platform!.wireName,
      if (authMethod != null) 'auth_method': authMethod!.wireName,
      if (surface != null) 'surface': surface!.wireName,
    };
    final allowed = _allowedProperties[event]!;
    if (values.keys.any((property) => !allowed.contains(property))) {
      return null;
    }
    return values;
  }
}

const Map<GrowthEvent, Set<String>> _allowedProperties =
    <GrowthEvent, Set<String>>{
      GrowthEvent.landingView: <String>{'surface', 'channel', 'entry_page'},
      GrowthEvent.ctaClick: <String>{
        'placement',
        'channel',
        'entry_page',
        'cta_placement',
      },
      GrowthEvent.pricingPeriodSelected: <String>{'billing_interval'},
      GrowthEvent.pricingPlanSelected: <String>{'plan', 'billing_interval'},
      GrowthEvent.signupStarted: <String>{
        'auth_method',
        'placement',
        'channel',
        'entry_page',
        'cta_placement',
      },
      GrowthEvent.signupCompleted: <String>{
        'auth_method',
        'channel',
        'entry_page',
        'cta_placement',
      },
      GrowthEvent.activationCompleted: <String>{'surface'},
      GrowthEvent.checkoutStarted: <String>{'plan', 'billing_interval'},
      GrowthEvent.checkoutCompleted: <String>{'plan', 'billing_interval'},
      GrowthEvent.downloadStarted: <String>{'platform', 'channel'},
      GrowthEvent.testerSignupStarted: <String>{
        'placement',
        'channel',
        'entry_page',
        'cta_placement',
      },
      GrowthEvent.testerSignupCompleted: <String>{
        'placement',
        'channel',
        'entry_page',
        'cta_placement',
      },
    };

const Map<String, GrowthEntryPage> _entryPagesByPath =
    <String, GrowthEntryPage>{
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

final Map<String, GrowthEntryPage> _entryPagesByWireName =
    <String, GrowthEntryPage>{
      for (final value in GrowthEntryPage.values) value.wireName: value,
    };

final Map<String, GrowthSource> _sourcesByWireName = <String, GrowthSource>{
  for (final value in GrowthSource.values) value.wireName: value,
};

final Map<String, GrowthChannel> _channelsByWireName = <String, GrowthChannel>{
  for (final value in GrowthChannel.values) value.wireName: value,
};

const Map<String, GrowthChannel> _growthChannelAliases =
    <String, GrowthChannel>{
      'alternative_to': GrowthChannel.alternativeTo,
      'beta_bound': GrowthChannel.betaBound,
      'bsky': GrowthChannel.bluesky,
      'twitter': GrowthChannel.x,
      'hackernews': GrowthChannel.hackerNews,
      'product-hunt': GrowthChannel.productHunt,
      'producthunt': GrowthChannel.productHunt,
      'dev': GrowthChannel.devCommunity,
      'dev.to': GrowthChannel.devCommunity,
      'dev_to': GrowthChannel.devCommunity,
      'devto': GrowthChannel.devCommunity,
      'dev_community_showdev': GrowthChannel.devCommunity,
      'reviewer': GrowthChannel.reviewerOutreach,
      'launchingnext': GrowthChannel.launchingNext,
      'beta_list': GrowthChannel.startupDirectory,
    };

const Set<String> _paidSearchMedia = <String>{
  'cpc',
  'ppc',
  'paid_search',
  'paidsearch',
};
const Set<String> _paidSocialMedia = <String>{'paid_social', 'paidsocial'};
const Set<String> _emailMedia = <String>{'lifecycle', 'email', 'newsletter'};
const Set<String> _referralMedia = <String>{
  'listing',
  'referral',
  'referral_link',
  'affiliate',
  'partner',
};
const Set<String> _organicSearchSources = <String>{
  'organic',
  'seo',
  'google',
  'bing',
  'duckduckgo',
  'brave',
  'yahoo',
  'ecosia',
  'startpage',
  'yandex',
};

GrowthEntryPage growthEntryPageFromUri(Uri uri) {
  var path = uri.path.trim().toLowerCase();
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.endsWith('.html')) {
    path = path.substring(0, path.length - 5);
  }
  final routeEntry = _entryPagesByPath[path];
  if (routeEntry != null) {
    return routeEntry;
  }
  return path.isEmpty ? GrowthEntryPage.unknown : GrowthEntryPage.other;
}

GrowthCtaPlacement growthCtaPlacementFromCampaignUri(Uri uri) {
  final source = (uri.queryParameters['utm_source'] ?? '').trim().toLowerCase();
  final content = (uri.queryParameters['utm_content'] ?? '')
      .trim()
      .toLowerCase();
  if (source == GrowthSource.userReferral.wireName ||
      content == 'tester_success') {
    return GrowthCtaPlacement.postSignupReferral;
  }
  for (final value in <GrowthCtaPlacement>[
    GrowthCtaPlacement.header,
    GrowthCtaPlacement.hero,
    GrowthCtaPlacement.inline,
    GrowthCtaPlacement.finalCta,
    GrowthCtaPlacement.footer,
  ]) {
    if (content == value.wireName || content.startsWith('${value.wireName}_')) {
      return value;
    }
  }
  return content.isEmpty
      ? GrowthCtaPlacement.direct
      : GrowthCtaPlacement.unknown;
}

GrowthCtaPlacement growthCtaPlacementForLegacy(GrowthPlacement placement) {
  return switch (placement) {
    GrowthPlacement.header => GrowthCtaPlacement.header,
    GrowthPlacement.hero => GrowthCtaPlacement.hero,
    GrowthPlacement.footer => GrowthCtaPlacement.footer,
    GrowthPlacement.testerReferral => GrowthCtaPlacement.postSignupReferral,
    GrowthPlacement.pricing ||
    GrowthPlacement.mobileNav ||
    GrowthPlacement.downloadPage ||
    GrowthPlacement.testerPage => GrowthCtaPlacement.inline,
    _ => GrowthCtaPlacement.unknown,
  };
}

GrowthAttribution growthAttributionFromUri(Uri uri) {
  final channel = growthChannelFromCampaignUri(uri);
  return GrowthAttribution(
    source: growthSourceForChannel(channel),
    channel: channel,
    entryPage: growthEntryPageFromUri(uri),
  );
}

/// First-touch attribution for the current browser tab.
///
/// One versioned JSON object containing three fixed enum wire values enters
/// session storage. Legacy v1 keys are intentionally ignored. An internal
/// route or its UTM-decorated link therefore cannot replace the original
/// source, exact allowlisted channel, or entry page, and no raw URL/query/
/// referrer is persisted.
class GrowthAttributionSession {
  GrowthAttributionSession({
    this.readValue = readGrowthAttributionSessionValue,
    this.writeValue = writeGrowthAttributionSessionValue,
  });

  static final GrowthAttributionSession instance = GrowthAttributionSession();

  final String? Function(String key) readValue;
  final void Function(String key, String value) writeValue;

  GrowthAttribution? _current;

  GrowthAttributionResolution resolve(Uri uri) {
    final current = _current ?? _readStored();
    if (current != null) {
      _current = current;
      return GrowthAttributionResolution(
        attribution: current,
        isNewEntry: false,
      );
    }

    final attribution = growthAttributionFromUri(uri);
    _current = attribution;
    writeValue(
      growthAttributionSessionKey,
      jsonEncode(<String, String>{
        'source': attribution.source.wireName,
        'channel': attribution.channel.wireName,
        'entry_page': attribution.entryPage.wireName,
      }),
    );
    return GrowthAttributionResolution(
      attribution: attribution,
      isNewEntry: true,
    );
  }

  GrowthAttribution? _readStored() {
    final stored = readValue(growthAttributionSessionKey);
    if (stored == null || stored.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 3 ||
          !decoded.containsKey('source') ||
          !decoded.containsKey('channel') ||
          !decoded.containsKey('entry_page')) {
        return null;
      }
      final sourceValue = decoded['source'];
      final channelValue = decoded['channel'];
      final entryPageValue = decoded['entry_page'];
      if (sourceValue is! String ||
          channelValue is! String ||
          entryPageValue is! String) {
        return null;
      }
      final source = _sourcesByWireName[sourceValue];
      final channel = _channelsByWireName[channelValue];
      final entryPage = _entryPagesByWireName[entryPageValue];
      if (source == null ||
          channel == null ||
          entryPage == null ||
          growthSourceForChannel(channel) != source) {
        return null;
      }
      return GrowthAttribution(
        source: source,
        channel: channel,
        entryPage: entryPage,
      );
    } on FormatException {
      return null;
    }
  }
}

GrowthChannel growthChannelFromCampaignUri(Uri uri) {
  final medium = (uri.queryParameters['utm_medium'] ?? '').trim().toLowerCase();
  final source = (uri.queryParameters['utm_source'] ?? '').trim().toLowerCase();
  final hasCampaignParameters = uri.queryParameters.keys.any(
    (key) => key.toLowerCase().startsWith('utm_'),
  );
  if (medium.isEmpty && source.isEmpty && !hasCampaignParameters) {
    return GrowthChannel.direct;
  }

  if (_paidSearchMedia.contains(medium)) {
    return GrowthChannel.paidSearch;
  }
  if (_paidSocialMedia.contains(medium)) {
    return GrowthChannel.paidSocial;
  }
  if (_emailMedia.contains(medium)) {
    return GrowthChannel.lifecycleEmail;
  }
  if (source == GrowthChannel.userReferral.wireName &&
      _referralMedia.contains(medium)) {
    return GrowthChannel.userReferral;
  }
  if (medium == 'seo' || source == 'seo' || source == 'organic') {
    return GrowthChannel.organicSearch;
  }
  if (medium == 'organic' && _organicSearchSources.contains(source)) {
    return GrowthChannel.organicSearch;
  }

  final alias = _growthChannelAliases[source];
  if (alias != null) {
    return alias;
  }
  final exact = _channelsByWireName[source];
  if (exact != null) {
    return exact;
  }
  if (_referralMedia.contains(medium)) {
    return GrowthChannel.otherReferral;
  }
  return GrowthChannel.unknown;
}

GrowthSource growthSourceForChannel(GrowthChannel channel) {
  return switch (channel) {
    GrowthChannel.direct => GrowthSource.direct,
    GrowthChannel.organicSearch => GrowthSource.organicSearch,
    GrowthChannel.linkedin ||
    GrowthChannel.x ||
    GrowthChannel.reddit ||
    GrowthChannel.hackerNews ||
    GrowthChannel.productHunt ||
    GrowthChannel.bluesky ||
    GrowthChannel.mastodon ||
    GrowthChannel.devCommunity ||
    GrowthChannel.privacyForum => GrowthSource.organicSocial,
    GrowthChannel.alternativeTo ||
    GrowthChannel.saasHub ||
    GrowthChannel.b2bSaasMarket ||
    GrowthChannel.betaBound ||
    GrowthChannel.crozdesk ||
    GrowthChannel.findersList ||
    GrowthChannel.g2 ||
    GrowthChannel.helperG ||
    GrowthChannel.launchingNext ||
    GrowthChannel.peerlist ||
    GrowthChannel.pitchwall ||
    GrowthChannel.privacyFest ||
    GrowthChannel.productReveal ||
    GrowthChannel.startupDirectory ||
    GrowthChannel.startupStarterKit ||
    GrowthChannel.startupBase ||
    GrowthChannel.startupBuffer ||
    GrowthChannel.submitStartup ||
    GrowthChannel.uneed ||
    GrowthChannel.visalytica ||
    GrowthChannel.weAreFounders ||
    GrowthChannel.otherReferral => GrowthSource.referral,
    GrowthChannel.helpNetSecurity ||
    GrowthChannel.theRegister ||
    GrowthChannel.reviewerOutreach => GrowthSource.partner,
    GrowthChannel.userReferral => GrowthSource.userReferral,
    GrowthChannel.lifecycleEmail => GrowthSource.email,
    GrowthChannel.paidSearch => GrowthSource.paidSearch,
    GrowthChannel.paidSocial => GrowthSource.paidSocial,
    GrowthChannel.product => GrowthSource.product,
    GrowthChannel.unknown => GrowthSource.unknown,
  };
}

GrowthChannel growthChannelForLegacySource(GrowthSource source) {
  return switch (source) {
    GrowthSource.direct => GrowthChannel.direct,
    GrowthSource.organicSearch => GrowthChannel.organicSearch,
    GrowthSource.userReferral => GrowthChannel.userReferral,
    GrowthSource.email => GrowthChannel.lifecycleEmail,
    GrowthSource.paidSearch => GrowthChannel.paidSearch,
    GrowthSource.paidSocial => GrowthChannel.paidSocial,
    GrowthSource.product => GrowthChannel.product,
    GrowthSource.organicSocial ||
    GrowthSource.referral ||
    GrowthSource.partner ||
    GrowthSource.unknown => GrowthChannel.unknown,
  };
}

GrowthSource growthSourceFromCampaignUri(Uri uri) {
  return growthSourceForChannel(growthChannelFromCampaignUri(uri));
}

class GrowthAnalytics {
  GrowthAnalytics({
    http.Client? client,
    Uri? endpoint,
    Uri? signupCompletedEndpoint,
    this.timeout = const Duration(seconds: 3),
  }) : _client = client,
       endpoint =
           endpoint ??
           ReleaseRuntimeConfig.resolveCheckoutApiBaseUri().resolve(
             'growth/events',
           ),
       signupCompletedEndpoint =
           signupCompletedEndpoint ??
           ReleaseRuntimeConfig.resolveCheckoutApiBaseUri().resolve(
             'growth/signup-completed',
           );

  final http.Client? _client;
  final Uri endpoint;
  final Uri signupCompletedEndpoint;
  final Duration timeout;

  Future<bool> record({
    required GrowthEvent event,
    required GrowthSource source,
    GrowthEventProperties properties = const GrowthEventProperties(),
  }) async {
    if (!optionalGrowthAllowed()) return false;
    final propertyPayload = properties.toJsonFor(event);
    if (propertyPayload == null) {
      return false;
    }

    final body = jsonEncode(<String, Object>{
      'event': event.wireName,
      'source': source.wireName,
      'properties': propertyPayload,
    });
    try {
      final request = _client == null
          ? http.post(
              endpoint,
              headers: const <String, String>{
                'Content-Type': 'application/json',
              },
              body: body,
            )
          : _client.post(
              endpoint,
              headers: const <String, String>{
                'Content-Type': 'application/json',
              },
              body: body,
            );
      final response = await request.timeout(timeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Object {
      return false;
    }
  }

  /// Records the authenticated, server-deduplicated signup outcome.
  ///
  /// The request intentionally contains no email, UID, source, URL, UTM value,
  /// or visitor/session identifier. The backend resolves the account from the
  /// Firebase bearer token and derives the coarse source from [channel].
  Future<bool> recordAuthenticatedSignupCompleted({
    required String idToken,
    required GrowthChannel channel,
    required GrowthEntryPage entryPage,
    required GrowthCtaPlacement ctaPlacement,
    required GrowthAuthMethod authMethod,
  }) async {
    final result = await submitAuthenticatedSignupCompleted(
      idToken: idToken,
      channel: channel,
      entryPage: entryPage,
      ctaPlacement: ctaPlacement,
      authMethod: authMethod,
    );
    return result == AuthenticatedSignupCompletionResult.confirmed;
  }

  /// Submits an authenticated signup outcome and reports whether the server
  /// proved that its exactly-once marker is now present.
  ///
  /// A generic 2xx response is deliberately insufficient. Callers may delete
  /// their durable local retry marker only when the bounded response body says
  /// `recorded: true` or `reason: already_recorded`.
  Future<AuthenticatedSignupCompletionResult>
  submitAuthenticatedSignupCompleted({
    required String idToken,
    required GrowthChannel channel,
    required GrowthEntryPage entryPage,
    required GrowthCtaPlacement ctaPlacement,
    required GrowthAuthMethod authMethod,
  }) async {
    final token = idToken.trim();
    if (token.isEmpty) {
      return AuthenticatedSignupCompletionResult.retryable;
    }
    final body = jsonEncode(<String, String>{
      'channel': channel.wireName,
      'entryPage': entryPage.wireName,
      'ctaPlacement': ctaPlacement.wireName,
      'authMethod': authMethod.wireName,
    });
    try {
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final request = _client == null
          ? http.post(signupCompletedEndpoint, headers: headers, body: body)
          : _client.post(signupCompletedEndpoint, headers: headers, body: body);
      final response = await request.timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return AuthenticatedSignupCompletionResult.retryable;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return AuthenticatedSignupCompletionResult.retryable;
      }
      final recorded = decoded['recorded'] == true;
      final alreadyRecorded = decoded['reason'] == 'already_recorded';
      return recorded || alreadyRecorded
          ? AuthenticatedSignupCompletionResult.confirmed
          : AuthenticatedSignupCompletionResult.retryable;
    } on Object {
      return AuthenticatedSignupCompletionResult.retryable;
    }
  }
}

enum AuthenticatedSignupCompletionResult { confirmed, retryable }
