'use strict';
(() => {
  const status = document.getElementById('status');
  const refresh = document.getElementById('refresh');
  const fragment = window.location.hash.slice(1);
  if (!/^request=[a-f0-9]{64}&token=[A-Za-z0-9_-]{43}$/.test(fragment)) return;
  const params = new URLSearchParams(fragment);
  const project = {
    'ronikcloud.com': 'cloudapp-7dcc2',
    'cloudapp-7dcc2.web.app': 'cloudapp-7dcc2',
    'cloudapp-7dcc2.firebaseapp.com': 'cloudapp-7dcc2',
    'ronikdrive-staging.web.app': 'ronikdrive-staging',
    'ronikcloud-test-7dcc2.web.app': 'ronikcloud-test-7dcc2',
    'ronikcloud-test-7dcc2.firebaseapp.com': 'ronikcloud-test-7dcc2',
  }[window.location.hostname];
  if (!project) return;
  const messages = {
    requested: 'Your deletion request is recorded and queued for processing. Your account and billing may remain active until processing begins.',
    in_progress: 'Your account closure is in progress. Account access may already be disabled while deletion finishes.',
    completed: 'Your account deletion is complete in active service systems. Provider backups, required transaction records and organization-owned content follow the retention policy.',
    needs_attention: 'Processing has paused for a check or a provider problem. We are retrying and will contact you if action is needed. Your request remains recorded.',
  };
  refresh.hidden = false;
  async function check() {
    refresh.disabled = true;
    status.textContent = 'Checking your deletion request…';
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch(`https://europe-west1-${project}.cloudfunctions.net/getAccountClosureReceipt`, {
        method: 'POST', credentials: 'omit', referrerPolicy: 'no-referrer', cache: 'no-store', redirect: 'error', signal: controller.signal,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ data: { request: params.get('request'), token: params.get('token') } }),
      });
      if (response.status === 404) {
        status.textContent = 'This receipt is unavailable. It may have expired or been replaced. Use your most recent saved link or contact support.';
        return;
      }
      if (!response.ok) throw new Error('Receipt service unavailable');
      const data = (await response.json()).result;
      if (!data || !Object.hasOwn(messages, data.status)) throw new Error('Invalid receipt response');
      status.textContent = messages[data.status];
    } catch {
      status.textContent = 'The status could not be checked. Check your connection and try again, or contact support. This does not change your request.';
    } finally { clearTimeout(timeout); refresh.disabled = false; }
  }
  refresh.addEventListener('click', check);
  check();
})();
