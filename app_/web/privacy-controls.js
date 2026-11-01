(function () {
  'use strict';
  if (window.ronikPrivacy) return;
  const id = 'G-QK81P4P7VG';
  const key = 'ronikcloud.optional-analytics.v2';
  const lifetime = 180 * 24 * 60 * 60 * 1000;
  let enabled = false;
  let loaded = false;
  let panel;
  let opener;
  let previousFocus;
  let expiryTimer;
  let allowedUntil = 0;
  function notify() {
    if (typeof window.dispatchEvent === 'function') window.dispatchEvent(new Event('ronikprivacychange'));
  }
  function scheduleExpiry(saved) {
    clearTimeout(expiryTimer);
    allowedUntil = saved && saved.allowed ? saved.at + lifetime : 0;
    if (saved && saved.allowed) expiryTimer = setTimeout(() => {
      if (Date.now() < allowedUntil) { scheduleExpiry(saved); return; }
      apply(false);
      notify();
      if (loaded) location.reload();
    }, Math.min(86400000, Math.max(0, saved.at + lifetime - Date.now())));
  }
  const read = () => {
    try {
      const saved = JSON.parse(localStorage.getItem(key));
      return saved && typeof saved.allowed === 'boolean' &&
        Number.isFinite(saved.at) && Date.now() >= saved.at &&
        Date.now() - saved.at < lifetime ? saved : null;
    } catch (_) { return null; }
  };
  function clearAnalyticsCookies() {
    const domains = location.hostname.split('.');
    for (const cookie of document.cookie.split(';')) {
      const name = cookie.split('=')[0].trim();
      if (!/^_ga(?:_|$)/.test(name)) continue;
      document.cookie = name + '=; Max-Age=0; path=/; SameSite=Lax';
      for (let i = 0; i < domains.length - 1; i++) {
        document.cookie = name + '=; Max-Age=0; path=/; domain=' + domains.slice(i).join('.') + '; SameSite=Lax';
      }
    }
  }
  function apply(allowed) {
    enabled = allowed;
    window['ga-disable-' + id] = !allowed;
    if (!allowed) {
      clearAnalyticsCookies();
      try {
        ['ronikcloud.growth.attribution.v2', 'ronikcloud.growth.source.v1', 'ronikcloud.growth.entry_page.v1']
          .forEach(name => sessionStorage.removeItem(name));
      } catch (_) {}
      return;
    }
    if (loaded) return;
    loaded = true;
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { window.dataLayer.push(arguments); };
    window.gtag('consent', 'default', {
      analytics_storage: 'granted', ad_storage: 'denied',
      ad_user_data: 'denied', ad_personalization: 'denied'
    });
    window.gtag('js', new Date());
    // Never send the real URL, query, fragment, title, referrer or account ID.
    window.gtag('config', id, {
      send_page_view: false, allow_google_signals: false,
      allow_ad_personalization_signals: false,
      page_location: location.origin + '/', page_referrer: '',
      page_title: 'RonikCloud', cookie_expires: lifetime / 1000,
      cookie_update: false
    });
    window.gtag('event', 'site_visit', {
      page_location: location.origin + '/', page_referrer: '',
      page_title: 'RonikCloud'
    });
    const script = document.createElement('script');
    script.async = true;
    script.src = 'https://www.googletagmanager.com/gtag/js?id=' + id;
    document.head.appendChild(script);
  }
  function save(allowed) {
    const saved = { allowed, at: Date.now() };
    try { localStorage.setItem(key, JSON.stringify(saved)); } catch (_) {}
    apply(allowed);
    scheduleExpiry(saved);
    notify();
    panel.hidden = true;
    opener.hidden = true;
    if (previousFocus && typeof previousFocus.focus === 'function') previousFocus.focus();
    // A loaded third-party tag cannot be unloaded reliably. Reload on withdrawal.
    if (!allowed && loaded) location.reload();
  }
  function button(label, action) {
    const element = document.createElement('button');
    element.type = 'button';
    element.textContent = label;
    element.className = 'ronik-privacy-button';
    element.onclick = action;
    return element;
  }
  panel = document.createElement('section');
  panel.id = 'ronik-privacy-panel';
  panel.className = 'ronik-privacy-panel';
  panel.setAttribute('aria-label', 'Cookie and analytics preferences');
  const style = document.createElement('style');
  style.textContent = `
    .ronik-privacy-panel, .ronik-privacy-button {
      --privacy-surface: var(--panel, var(--surface, #fff)); --privacy-text: var(--ink, #172033);
      --privacy-outline: #64748b; --privacy-accent: var(--link, var(--brand, #1e5bf1));
      --privacy-hover: var(--surface-raised, var(--page, #edf2ff));
      font: 14px/1.5 'Source Sans 3', system-ui, sans-serif;
      color: var(--privacy-text); color-scheme: inherit;
    }
    @media (prefers-color-scheme: dark) {
      .ronik-privacy-panel, .ronik-privacy-button {
        --privacy-surface: var(--panel, var(--surface, #142033)); --privacy-text: var(--ink, #e2e8f0);
        --privacy-outline: #74859f; --privacy-accent: var(--link, var(--brand, #adc6ff));
        --privacy-hover: var(--surface-raised, var(--page, #22324b));
      }
    }
    .ronik-privacy-panel[hidden], .ronik-privacy-button[hidden] { display: none !important; }
    #ronik-privacy-panel {
      position: fixed; bottom: 64px; right: 12px; box-sizing: border-box;
      width: min(420px, calc(100vw - 24px)); max-height: 65vh; overflow: auto;
      padding: 20px; background: var(--privacy-surface); border-radius: 10px;
      z-index: 10000; box-shadow: 0 8px 32px #0004;
      accent-color: var(--privacy-accent);
    }
    .ronik-privacy-panel h2 { margin: 0 0 12px; font-size: 20px; }
    .ronik-privacy-panel p { margin: 0 0 16px; }
    .ronik-privacy-panel label { display: flex; align-items: center; gap: 8px; margin-bottom: 16px; }
    .ronik-privacy-button {
      min-height: 44px; padding: 8px 12px; margin: 4px;
      border: 1px solid var(--privacy-outline); border-radius: 8px;
      background: var(--privacy-surface); cursor: pointer;
    }
    .ronik-privacy-button:hover { background: var(--privacy-hover); }
    .ronik-privacy-button:focus-visible, .ronik-privacy-panel input:focus-visible {
      outline: 2px solid var(--privacy-accent); outline-offset: 3px;
    }
    .ronik-privacy-opener { position: fixed; bottom: 8px; right: 8px; z-index: 10000; }
    .ronik-privacy-footer { border: 0; background: transparent; color: inherit; }
  `;
  document.head.appendChild(style);
  const heading = document.createElement('h2');
  heading.textContent = 'Privacy & cookies';
  panel.appendChild(heading);
  const description = document.createElement('p');
  description.textContent = 'Essential storage keeps sign-in, security and settings working. Optional analytics uses Google Analytics cookies and session storage for marketing-source measurement. Both are off until you agree. File names, folder paths and account details are excluded. Your choice lasts 180 days on this device.';
  panel.appendChild(description);
  const toggle = document.createElement('input');
  toggle.type = 'checkbox';
  const label = document.createElement('label');
  label.append(toggle, document.createTextNode(' Optional usage and marketing analytics'));
  panel.append(label);
  panel.append(button('Accept optional', () => save(true)), button('Reject optional', () => save(false)), button('Save preferences', () => save(toggle.checked)));
  function open() {
    previousFocus = document.activeElement;
    toggle.checked = enabled;
    panel.hidden = false;
    toggle.focus();
  }
  opener = button('Privacy & cookies', () => {
    if (panel.hidden) open();
    else panel.hidden = true;
  });
  opener.className += ' ronik-privacy-opener';
  opener.setAttribute('aria-controls', panel.id);
  document.body.append(panel, opener);
  // Public pages retain a quiet entry point after the floating prompt is dismissed.
  const footer = document.querySelector('footer');
  if (footer) {
    const footerButton = button('Cookie preferences', open);
    footerButton.className += ' ronik-privacy-footer';
    footer.appendChild(footerButton);
  }
  const saved = read();
  opener.hidden = !!saved;
  window.ronikPrivacy = { analyticsAllowed: () => enabled && Date.now() < allowedUntil, open };
  panel.hidden = true; // No blocking prompt; optional tracking stays off.
  apply(saved ? saved.allowed : false);
  scheduleExpiry(saved);
  notify();
  window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !panel.hidden) {
      panel.hidden = true;
      if (previousFocus && typeof previousFocus.focus === 'function') previousFocus.focus();
    }
  });
  window.addEventListener('storage', (event) => {
    if (event.key === key) {
      const next = read();
      opener.hidden = !!next;
      panel.hidden = true;
      if (loaded && (!next || !next.allowed)) location.reload();
      else { apply(next ? next.allowed : false); scheduleExpiry(next); notify(); }
    }
  });
})();
