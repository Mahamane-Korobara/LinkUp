'use client';

import { useEffect } from 'react';

/**
 * Enregistre le service worker du dashboard (PWA). No-op si le navigateur ne le
 * supporte pas ou si le contexte n'est pas sécurisé (http://<ip> hors localhost) :
 * `navigator.serviceWorker` est alors absent et on ignore silencieusement.
 */
export function ServiceWorkerRegister() {
  useEffect(() => {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js').catch(() => {});
    }
  }, []);
  return null;
}
