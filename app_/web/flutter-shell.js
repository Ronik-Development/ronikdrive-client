'use strict';

const fallback = document.querySelector('[data-flutter-shell-fallback]');
const recoveryTimer = window.setTimeout(() => {
  if (!fallback?.isConnected) return;
  const recovery = document.createElement('div');
  recovery.className = 'flutter-shell-recovery';
  const message = document.createElement('p');
  message.setAttribute('role', 'status');
  message.textContent = 'Loading is taking longer than expected. Check your connection and reload, or use the links below for help.';
  const retry = document.createElement('button');
  retry.type = 'button';
  retry.textContent = 'Reload app';
  retry.addEventListener('click', () => window.location.reload());
  recovery.append(message, retry);
  fallback.querySelector('.flutter-shell-content')?.insertBefore(
    recovery, fallback.querySelector('nav')
  );
}, 20000);

window.addEventListener(
  'flutter-first-frame',
  () => {
    window.clearTimeout(recoveryTimer);
    fallback?.remove();
  },
  { once: true }
);
