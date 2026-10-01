(() => {
  const MEASUREMENT_ID = 'G-SZTERTRTCE';
  const CONSENT_KEY = 'ios-ipa-builder-analytics-consent-v1';
  const PAGE_TITLE = String(document.querySelector('meta[name="analytics-page-title"]')?.content || document.title || location.hostname).trim() || location.hostname;
  const PAGE_LOCATION = `${location.origin}${location.pathname}${location.search}`;
  let loaded = false;
  let banner = null;
  let settingsButton = null;

  const COPY = {
    en: { title:'Analytics cookies', text:'This site uses Google Analytics only if you choose Accept. Rejecting keeps analytics disabled.', accept:'Accept analytics', reject:'Reject', settings:'Cookie settings' },
    cs: { title:'Analytické cookies', text:'Tento web používá Google Analytics pouze pokud zvolíte Přijmout. Odmítnutím zůstane analytika vypnutá.', accept:'Přijmout analytiku', reject:'Odmítnout', settings:'Nastavení cookies' },
    de: { title:'Analyse-Cookies', text:'Diese Website verwendet Google Analytics nur mit Ihrer Zustimmung. Bei Ablehnung bleibt die Analyse deaktiviert.', accept:'Analyse akzeptieren', reject:'Ablehnen', settings:'Cookie-Einstellungen' },
    es: { title:'Cookies de análisis', text:'Este sitio usa Google Analytics solo si eliges Aceptar. Si rechazas, el análisis permanece desactivado.', accept:'Aceptar análisis', reject:'Rechazar', settings:'Configuración de cookies' },
    fr: { title:'Cookies de mesure', text:'Ce site utilise Google Analytics uniquement si vous l’acceptez. En cas de refus, la mesure reste désactivée.', accept:'Accepter la mesure', reject:'Refuser', settings:'Paramètres des cookies' }
  };

  function lang() {
    const value = String(document.documentElement.lang || navigator.language || 'en').toLowerCase().split('-')[0];
    return COPY[value] ? value : 'en';
  }
  function copy() { return COPY[lang()]; }
  function readConsent() {
    try { return localStorage.getItem(CONSENT_KEY); } catch (_) { return null; }
  }
  function writeConsent(value) {
    try { localStorage.setItem(CONSENT_KEY, value); } catch (_) {}
  }
  function gtag() {
    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push(arguments);
  }
  function loadAnalytics() {
    if (loaded || document.querySelector('script[data-caseycz-analytics]')) return;
    loaded = true;
    window.dataLayer = window.dataLayer || [];
    window.gtag = gtag;
    gtag('consent', 'default', {
      analytics_storage: 'granted',
      ad_storage: 'denied',
      ad_user_data: 'denied',
      ad_personalization: 'denied'
    });
    gtag('js', new Date());
    gtag('config', MEASUREMENT_ID, {
      allow_google_signals: false,
      allow_ad_personalization_signals: false,
      page_title: PAGE_TITLE,
      page_location: PAGE_LOCATION
    });
    const tag = document.createElement('script');
    tag.async = true;
    tag.dataset.caseyczAnalytics = 'true';
    tag.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(MEASUREMENT_ID)}`;
    document.head.appendChild(tag);
  }
  function expireCookie(name) {
    const domains = ['', location.hostname, `.${location.hostname}`];
    for (const domain of domains) {
      document.cookie = `${name}=; Max-Age=0; path=/; SameSite=Lax${domain ? `; domain=${domain}` : ''}`;
    }
  }
  function disableAnalytics() {
    if (window.gtag) {
      window.gtag('consent', 'update', {
        analytics_storage: 'denied',
        ad_storage: 'denied',
        ad_user_data: 'denied',
        ad_personalization: 'denied'
      });
    }
    expireCookie('_ga');
    expireCookie('_ga_SZTERTRTCE');
  }
  function ensureStyle() {
    if (document.getElementById('caseycz-consent-style')) return;
    const style = document.createElement('style');
    style.id = 'caseycz-consent-style';
    style.textContent = `
      .caseycz-consent{position:fixed;z-index:2147483646;left:50%;bottom:max(14px,env(safe-area-inset-bottom));transform:translateX(-50%);width:min(680px,calc(100% - 24px));box-sizing:border-box;padding:14px;border:1px solid rgba(127,127,127,.35);border-radius:14px;background:rgba(20,22,28,.97);color:#fff;box-shadow:0 14px 42px rgba(0,0,0,.35);font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;display:flex;gap:14px;align-items:center}
      .caseycz-consent-copy{flex:1;min-width:0}.caseycz-consent-copy strong{display:block;margin-bottom:3px}.caseycz-consent-copy span{opacity:.8}
      .caseycz-consent-actions{display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end}.caseycz-consent button,.caseycz-cookie-settings{font:inherit;font-weight:700;cursor:pointer;border-radius:10px;border:1px solid rgba(127,127,127,.4);min-height:38px;padding:0 12px}
      .caseycz-consent [data-accept]{background:#0a84ff;border-color:#0a84ff;color:#fff}.caseycz-consent [data-reject]{background:transparent;color:#fff}
      .caseycz-cookie-settings-wrap{display:flex;justify-content:center;align-items:center;margin-top:10px}
      .caseycz-cookie-settings{min-height:32px;padding:0;border:0;background:transparent;color:inherit;font-size:12px;text-decoration:underline;text-underline-offset:3px;opacity:.75}
      .caseycz-cookie-settings:hover{opacity:1}
      .caseycz-privacy-footer{padding:14px 16px;text-align:center;color:#94a3b8;font:12px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
      @media(max-width:600px){.caseycz-consent{align-items:stretch;flex-direction:column}.caseycz-consent-actions{display:grid;grid-template-columns:1fr 1fr;width:100%}.caseycz-consent button{width:100%}}
    `;
    document.head.appendChild(style);
  }
  function closeBanner() {
    if (!banner) return;
    banner.remove();
    banner = null;
  }
  function showSettingsButton() {
    if (!document.body) return;
    ensureStyle();

    const existing = document.querySelector('[data-cookie-settings]');
    if (existing) {
      settingsButton = existing;
      settingsButton.textContent = copy().settings;
      settingsButton.setAttribute('aria-label', copy().title);
      if (settingsButton.dataset.cookieSettingsBound !== 'true') {
        settingsButton.dataset.cookieSettingsBound = 'true';
        settingsButton.addEventListener('click', event => {
          event.preventDefault();
          showBanner(true);
        });
      }
      return;
    }

    if (settingsButton) return;
    let footer = document.querySelector('[data-cookie-settings-host], footer, .foot, .footer, .site-footer');
    if (!footer) {
      footer = document.createElement('footer');
      footer.className = 'caseycz-privacy-footer';
      document.body.appendChild(footer);
    }

    const wrap = document.createElement('div');
    wrap.className = 'caseycz-cookie-settings-wrap';
    settingsButton = document.createElement('button');
    settingsButton.type = 'button';
    settingsButton.className = 'caseycz-cookie-settings';
    settingsButton.dataset.cookieSettings = '';
    settingsButton.textContent = copy().settings;
    settingsButton.setAttribute('aria-label', copy().title);
    settingsButton.dataset.cookieSettingsBound = 'true';
    settingsButton.addEventListener('click', () => showBanner(true));
    wrap.appendChild(settingsButton);
    footer.appendChild(wrap);
  }
  function setConsent(value) {
    writeConsent(value);
    if (value === 'granted') loadAnalytics();
    else disableAnalytics();
    closeBanner();
    showSettingsButton();
  }
  function showBanner(force = false) {
    if (banner || !document.body) return;
    if (!force && readConsent()) return;
    ensureStyle();
    const t = copy();
    banner = document.createElement('section');
    banner.className = 'caseycz-consent';
    banner.setAttribute('role', 'dialog');
    banner.setAttribute('aria-label', t.title);
    banner.innerHTML = `<div class="caseycz-consent-copy"><strong>${t.title}</strong><span>${t.text}</span></div><div class="caseycz-consent-actions"><button type="button" data-accept>${t.accept}</button><button type="button" data-reject>${t.reject}</button></div>`;
    banner.querySelector('[data-accept]')?.addEventListener('click', () => setConsent('granted'));
    banner.querySelector('[data-reject]')?.addEventListener('click', () => setConsent('denied'));
    document.body.appendChild(banner);
  }
  function init() {
    const consent = readConsent();
    if (consent === 'granted') loadAnalytics();
    else if (consent === 'denied') disableAnalytics();
    else showBanner();
    showSettingsButton();
  }
  window.CaseyCZAnalytics = Object.freeze({
    consent: readConsent,
    showSettings: () => showBanner(true)
  });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, {once:true});
  else init();
})();