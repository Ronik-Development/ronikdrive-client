(function bootstrapGrowthAttribution(root, factory) {
  'use strict';

  const api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
    return;
  }
  const privacy = root.document.createElement('script');
  privacy.src = '/privacy-controls.js';
  root.document.head.appendChild(privacy);
  api.start(root);
})(typeof window === 'undefined' ? globalThis : window, function createGrowthAttribution() {
  'use strict';

  const ENDPOINT = 'https://api-hn7guzik3q-ew.a.run.app/growth/events';
  const ATTRIBUTION_SESSION_KEY = 'ronikcloud.growth.attribution.v2';
  const LEGACY_SOURCE_SESSION_KEY = 'ronikcloud.growth.source.v1';
  const LEGACY_ENTRY_PAGE_SESSION_KEY = 'ronikcloud.growth.entry_page.v1';

  const SOURCES = Object.freeze([
    'direct',
    'organic_search',
    'organic_social',
    'referral',
    'user_referral',
    'email',
    'paid_search',
    'paid_social',
    'partner',
    'product',
    'unknown',
  ]);

  // A closed, low-cardinality first-touch channel vocabulary. Only these
  // fixed values are retained or sent; raw UTM values, URLs, and referrers
  // are inspected transiently and then discarded.
  const CHANNELS = Object.freeze([
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
  ]);

  const ENTRY_PAGES = Object.freeze([
    'home',
    'testers',
    'download',
    'resources',
    'secure_cloud_storage',
    'security_whitepaper',
    'encrypted_file_sharing',
    'freelancers',
    'small_teams',
    'private_cloud_backup',
    'secure_client_file_portal',
    'encrypted_file_request',
    'google_drive_encryption_alternative',
    'encrypted_wetransfer_alternative',
    'secure_file_sharing_accountants',
    'dropbox_encryption_alternative',
    'client_side_vs_server_side',
    'press_kit',
    'other',
    'unknown',
  ]);

  const CTA_PLACEMENTS = Object.freeze([
    'direct',
    'header',
    'hero',
    'inline',
    'final',
    'footer',
    'post_signup_referral',
    'unknown',
  ]);

  const ROUTE_ENTRY_PAGES = Object.freeze({
    '/': 'home',
    '/testers': 'testers',
    '/download': 'download',
    '/resources': 'resources',
    '/secure-cloud-storage': 'secure_cloud_storage',
    '/security-whitepaper': 'security_whitepaper',
    '/encrypted-file-sharing': 'encrypted_file_sharing',
    '/for-freelancers': 'freelancers',
    '/for-small-teams': 'small_teams',
    '/private-cloud-backup': 'private_cloud_backup',
    '/secure-client-file-portal': 'secure_client_file_portal',
    '/encrypted-file-request': 'encrypted_file_request',
    '/google-drive-client-side-encryption-alternative':
      'google_drive_encryption_alternative',
    '/encrypted-wetransfer-alternative':
      'encrypted_wetransfer_alternative',
    '/secure-file-sharing-accountants': 'secure_file_sharing_accountants',
    '/dropbox-encryption-alternative': 'dropbox_encryption_alternative',
    '/client-side-vs-server-side-encryption': 'client_side_vs_server_side',
    '/press-kit': 'press_kit',
  });

  const SEARCH_REFERRERS = Object.freeze([
    'bing.com',
    'brave.com',
    'duckduckgo.com',
    'ecosia.org',
    'startpage.com',
  ]);

  // Cover common regional search domains without accepting arbitrary
  // attacker-controlled suffixes such as google.example. These patterns are
  // used only for a fixed aggregate category; the referrer itself is never
  // persisted or transmitted.
  const REGIONAL_SEARCH_REFERRER_PATTERNS = Object.freeze([
    /(?:^|[.])google[.](?:com|[a-z]{2,3}|co[.][a-z]{2}|com[.][a-z]{2})$/u,
    /(?:^|[.])search[.]yahoo[.](?:com|[a-z]{2,3}|co[.][a-z]{2}|com[.][a-z]{2})$/u,
    /(?:^|[.])yandex[.](?:com|[a-z]{2,3}|com[.][a-z]{2})$/u,
  ]);

  const SOCIAL_REFERRERS = Object.freeze([
    'bsky.app',
    'facebook.com',
    'instagram.com',
    'linkedin.com',
    'mastodon.social',
    'reddit.com',
    'tiktok.com',
    'twitter.com',
    'x.com',
    'youtube.com',
  ]);

  const CHANNEL_BY_CAMPAIGN_SOURCE = Object.freeze({
    alternative_to: 'alternativeto',
    alternativeto: 'alternativeto',
    b2b_saas_market: 'b2b_saas_market',
    beta_bound: 'betabound',
    betabound: 'betabound',
    beta_list: 'startup_directory',
    bluesky: 'bluesky',
    bsky: 'bluesky',
    crozdesk: 'crozdesk',
    dev: 'dev_community',
    'dev.to': 'dev_community',
    dev_community: 'dev_community',
    dev_community_showdev: 'dev_community',
    dev_to: 'dev_community',
    devto: 'dev_community',
    finderslist: 'finderslist',
    g2: 'g2',
    hacker_news: 'hacker_news',
    hackernews: 'hacker_news',
    help_net_security: 'help_net_security',
    helperg: 'helperg',
    launching_next: 'launching_next',
    launchingnext: 'launching_next',
    linkedin: 'linkedin',
    mastodon: 'mastodon',
    peerlist: 'peerlist',
    pitchwall: 'pitchwall',
    privacy_forum: 'privacy_forum',
    privacyfest: 'privacyfest',
    product: 'product',
    'product-hunt': 'product_hunt',
    product_hunt: 'product_hunt',
    producthunt: 'product_hunt',
    productreveal: 'productreveal',
    reddit: 'reddit',
    reviewer: 'reviewer_outreach',
    reviewer_outreach: 'reviewer_outreach',
    saashub: 'saashub',
    startup_directory: 'startup_directory',
    startup_starter_kit: 'startup_starter_kit',
    startupbase: 'startupbase',
    startupbuffer: 'startupbuffer',
    submitstartup: 'submitstartup',
    the_register: 'the_register',
    twitter: 'x',
    uneed: 'uneed',
    user_referral: 'user_referral',
    visalytica: 'visalytica',
    we_are_founders: 'we_are_founders',
    x: 'x',
  });

  const CHANNEL_REFERRERS = Object.freeze({
    'alternativeto.net': 'alternativeto',
    'bsky.app': 'bluesky',
    'dev.to': 'dev_community',
    'g2.com': 'g2',
    'linkedin.com': 'linkedin',
    'mastodon.social': 'mastodon',
    'news.ycombinator.com': 'hacker_news',
    'peerlist.io': 'peerlist',
    'producthunt.com': 'product_hunt',
    'reddit.com': 'reddit',
    'saashub.com': 'saashub',
    'twitter.com': 'x',
    'x.com': 'x',
  });

  const SOURCE_BY_CHANNEL = Object.freeze({
    direct: 'direct',
    organic_search: 'organic_search',
    linkedin: 'organic_social',
    x: 'organic_social',
    reddit: 'organic_social',
    hacker_news: 'organic_social',
    product_hunt: 'organic_social',
    bluesky: 'organic_social',
    mastodon: 'organic_social',
    dev_community: 'organic_social',
    privacy_forum: 'organic_social',
    privacyfest: 'referral',
    alternativeto: 'referral',
    saashub: 'referral',
    b2b_saas_market: 'referral',
    betabound: 'referral',
    crozdesk: 'referral',
    finderslist: 'referral',
    g2: 'referral',
    helperg: 'referral',
    launching_next: 'referral',
    peerlist: 'referral',
    pitchwall: 'referral',
    productreveal: 'referral',
    startup_directory: 'referral',
    startup_starter_kit: 'referral',
    startupbase: 'referral',
    startupbuffer: 'referral',
    submitstartup: 'referral',
    uneed: 'referral',
    visalytica: 'referral',
    we_are_founders: 'referral',
    other_referral: 'referral',
    help_net_security: 'partner',
    the_register: 'partner',
    reviewer_outreach: 'partner',
    user_referral: 'user_referral',
    lifecycle_email: 'email',
    paid_search: 'paid_search',
    paid_social: 'paid_social',
    product: 'product',
    unknown: 'unknown',
  });

  const SOURCE_SET = new Set(SOURCES);
  const CHANNEL_SET = new Set(CHANNELS);
  const ENTRY_PAGE_SET = new Set(ENTRY_PAGES);
  const CTA_PLACEMENT_SET = new Set(CTA_PLACEMENTS);

  function normalized(value) {
    return typeof value === 'string' ? value.trim().toLowerCase() : '';
  }

  function validAttributionPair(source, channel) {
    return (
      SOURCE_SET.has(source) &&
      CHANNEL_SET.has(channel) &&
      SOURCE_BY_CHANNEL[channel] === source
    );
  }

  function safeUrl(value, base) {
    try {
      return new URL(value, base);
    } catch (_) {
      return null;
    }
  }

  function normalizedPath(pathname) {
    let path = normalized(pathname) || '/';
    if (!path.startsWith('/')) {
      path = `/${path}`;
    }
    if (path.length > 1 && path.endsWith('/')) {
      path = path.slice(0, -1);
    }
    if (path.endsWith('.html')) {
      path = path.slice(0, -5) || '/';
    }
    return path;
  }

  function entryPageFromPath(pathname) {
    const path = normalizedPath(pathname);
    return ROUTE_ENTRY_PAGES[path] || (path === '/' ? 'home' : 'other');
  }

  function hostMatches(hostname, candidate) {
    return hostname === candidate || hostname.endsWith(`.${candidate}`);
  }

  function isOrganicSearchHost(hostname) {
    return (
      SEARCH_REFERRERS.some((candidate) => hostMatches(hostname, candidate)) ||
      REGIONAL_SEARCH_REFERRER_PATTERNS.some((pattern) => pattern.test(hostname))
    );
  }

  function channelFromReferrer(referrer, currentUrl) {
    if (!referrer) {
      return 'direct';
    }
    const parsed = safeUrl(referrer, currentUrl.origin);
    if (!parsed) {
      return 'unknown';
    }
    const hostname = normalized(parsed.hostname).replace(/^www\./, '');
    const currentHostname = normalized(currentUrl.hostname).replace(/^www\./, '');
    if (!hostname || hostname === currentHostname) {
      return 'direct';
    }
    if (isOrganicSearchHost(hostname)) {
      return 'organic_search';
    }
    for (const [candidate, channel] of Object.entries(CHANNEL_REFERRERS)) {
      if (hostMatches(hostname, candidate)) {
        return channel;
      }
    }
    if (SOCIAL_REFERRERS.some((candidate) => hostMatches(hostname, candidate))) {
      return 'unknown';
    }
    return 'other_referral';
  }

  function channelFromCampaign(url) {
    const medium = normalized(url.searchParams.get('utm_medium'));
    const source = normalized(url.searchParams.get('utm_source'));
    let hasCampaignParameter = false;
    url.searchParams.forEach((_, key) => {
      if (normalized(key).startsWith('utm_')) {
        hasCampaignParameter = true;
      }
    });
    if (!hasCampaignParameter) {
      return null;
    }

    if (['cpc', 'ppc', 'paid_search', 'paidsearch'].includes(medium)) {
      return 'paid_search';
    }
    if (['paid_social', 'paidsocial'].includes(medium)) {
      return 'paid_social';
    }
    if (['email', 'newsletter', 'lifecycle'].includes(medium)) {
      return 'lifecycle_email';
    }
    if (
      medium === 'seo' ||
      source === 'seo' ||
      source === 'organic' ||
      (medium === 'organic' &&
        ['google', 'bing', 'duckduckgo', 'brave', 'ecosia', 'yahoo', 'startpage', 'yandex'].includes(source))
    ) {
      return 'organic_search';
    }
    const known = CHANNEL_BY_CAMPAIGN_SOURCE[source];
    if (known) {
      return known;
    }
    if (source === 'newsletter' || source === 'tester_welcome') {
      return 'lifecycle_email';
    }
    if (medium === 'outreach' && source === 'reviewer') {
      return 'reviewer_outreach';
    }
    if (
      ['listing', 'referral', 'referral_link', 'affiliate', 'partner'].includes(
        medium,
      )
    ) {
      return 'other_referral';
    }
    return 'unknown';
  }

  function deriveSource(href, referrer) {
    return SOURCE_BY_CHANNEL[deriveChannel(href, referrer)] || 'unknown';
  }

  function deriveChannel(href, referrer) {
    const url = safeUrl(href, 'https://ronikcloud.com/');
    if (!url) {
      return 'unknown';
    }
    const campaignChannel = channelFromCampaign(url);
    return campaignChannel || channelFromReferrer(referrer, url);
  }

  function readStoredAttribution(sessionStorage) {
    try {
      const raw = sessionStorage.getItem(ATTRIBUTION_SESSION_KEY);
      if (typeof raw !== 'string' || raw.length > 512) {
        return null;
      }
      const parsed = JSON.parse(raw);
      if (
        !parsed ||
        Array.isArray(parsed) ||
        typeof parsed !== 'object' ||
        Object.keys(parsed).sort().join(',') !== 'channel,entry_page,source' ||
        !validAttributionPair(parsed.source, parsed.channel) ||
        !ENTRY_PAGE_SET.has(parsed.entry_page)
      ) {
        return null;
      }
      return Object.freeze({
        source: parsed.source,
        channel: parsed.channel,
        entryPage: parsed.entry_page,
      });
    } catch (_) {
      // Storage may be unavailable in private or restricted browser contexts.
    }
    return null;
  }

  function writeStoredAttribution(sessionStorage, attribution) {
    try {
      if (typeof sessionStorage.removeItem === 'function') {
        sessionStorage.removeItem(ATTRIBUTION_SESSION_KEY);
        sessionStorage.removeItem(LEGACY_SOURCE_SESSION_KEY);
        sessionStorage.removeItem(LEGACY_ENTRY_PAGE_SESSION_KEY);
      }
      sessionStorage.setItem(
        ATTRIBUTION_SESSION_KEY,
        JSON.stringify({
          source: attribution.source,
          channel: attribution.channel,
          entry_page: attribution.entryPage,
        }),
      );
      return true;
    } catch (_) {
      try {
        if (typeof sessionStorage.removeItem === 'function') {
          sessionStorage.removeItem(ATTRIBUTION_SESSION_KEY);
        }
      } catch (_) {
        // A partial or corrupt value is ignored on the next page load.
      }
      // Telemetry is optional and must never affect the page experience.
      return false;
    }
  }

  function sessionStorageFor(root) {
    try {
      return root.sessionStorage;
    } catch (_) {
      return null;
    }
  }

  function resolveFirstTouch({ sessionStorage, href, pathname, referrer }) {
    const stored = readStoredAttribution(sessionStorage);
    if (stored) {
      return Object.freeze({
        source: stored.source,
        channel: stored.channel,
        entryPage: stored.entryPage,
        isNewEntry: false,
      });
    }

    const source = deriveSource(href, referrer);
    const channel = deriveChannel(href, referrer);
    const entryPage = entryPageFromPath(pathname);
    writeStoredAttribution(sessionStorage, { source, channel, entryPage });
    return Object.freeze({ source, channel, entryPage, isNewEntry: true });
  }

  function landingViewPayload(attribution) {
    if (
      !validAttributionPair(attribution.source, attribution.channel) ||
      !ENTRY_PAGE_SET.has(attribution.entryPage)
    ) {
      return null;
    }
    return Object.freeze({
      event: 'landing_view',
      source: attribution.source,
      properties: Object.freeze({
        surface: 'website',
        channel: attribution.channel,
        entry_page: attribution.entryPage,
      }),
    });
  }

  function ctaClickPayload(attribution, placement) {
    const ctaPlacement = normalized(placement);
    if (
      !validAttributionPair(attribution.source, attribution.channel) ||
      !ENTRY_PAGE_SET.has(attribution.entryPage) ||
      !CTA_PLACEMENT_SET.has(ctaPlacement)
    ) {
      return null;
    }
    return Object.freeze({
      event: 'cta_click',
      source: attribution.source,
      properties: Object.freeze({
        channel: attribution.channel,
        entry_page: attribution.entryPage,
        cta_placement: ctaPlacement,
      }),
    });
  }

  function postEvent(root, payload) {
    if (!payload || !root.ronikPrivacy || !root.ronikPrivacy.analyticsAllowed()) {
      return;
    }
    try {
      const fetchEvent = root.fetch;
      if (typeof fetchEvent !== 'function') {
        return;
      }
      const request = fetchEvent.call(root, ENDPOINT, {
        method: 'POST',
        mode: 'cors',
        credentials: 'omit',
        cache: 'no-store',
        keepalive: true,
        referrerPolicy: 'no-referrer',
        headers: Object.freeze({ 'Content-Type': 'application/json' }),
        body: JSON.stringify(payload),
      });
      if (request && typeof request.catch === 'function') {
        request.catch(function ignoreGrowthEventFailure() {});
      }
    } catch (_) {
      // Best-effort measurement must never block or change navigation.
    }
  }

  function declaredEntryPage(document, pathname) {
    const fixedEntryPage = entryPageFromPath(pathname);
    const declared = normalized(
      document && document.body && document.body.dataset
        ? document.body.dataset.growthEntryPage
        : '',
    );
    return declared === fixedEntryPage ? declared : fixedEntryPage;
  }

  const listening = new WeakSet();
  const started = new WeakSet();
  function start(root) {
    if (!root || !root.location || !root.document) {
      return null;
    }
    if (!listening.has(root) && typeof root.addEventListener === 'function') {
      listening.add(root);
      root.addEventListener('ronikprivacychange', () => start(root));
    }
    if (!root.ronikPrivacy || !root.ronikPrivacy.analyticsAllowed() || started.has(root)) return null;
    started.add(root);
    const document = root.document;
    const fixedEntryPage = declaredEntryPage(document, root.location.pathname);
    const attribution = resolveFirstTouch({
      sessionStorage: sessionStorageFor(root),
      href: root.location.href,
      pathname: root.location.pathname,
      referrer: document.referrer,
    });
    const effectiveAttribution = Object.freeze({
      source: attribution.source,
      channel: attribution.channel,
      entryPage: attribution.isNewEntry
        ? fixedEntryPage
        : attribution.entryPage,
    });

    if (attribution.isNewEntry) {
      postEvent(root, landingViewPayload(effectiveAttribution));
    }

    if (typeof document.addEventListener === 'function') {
      document.addEventListener(
        'click',
        function recordCtaClick(event) {
          const origin = event && event.target;
          const cta =
            origin && typeof origin.closest === 'function'
              ? origin.closest('[data-growth-cta-placement]')
              : null;
          if (!cta || !cta.dataset) {
            return;
          }
          const payload = ctaClickPayload(
            effectiveAttribution,
            cta.dataset.growthCtaPlacement,
          );
          postEvent(root, payload);
        },
        { capture: true },
      );
    }
    return effectiveAttribution;
  }

  return Object.freeze({
    ATTRIBUTION_SESSION_KEY,
    CHANNELS,
    CTA_PLACEMENTS,
    ENDPOINT,
    ENTRY_PAGES,
    ROUTE_ENTRY_PAGES,
    SOURCES,
    SOURCE_BY_CHANNEL,
    ctaClickPayload,
    deriveChannel,
    deriveSource,
    entryPageFromPath,
    landingViewPayload,
    resolveFirstTouch,
    start,
  });
});
