'use client';

import { useState } from 'react';
import { motion } from 'framer-motion';
import { Globe, Server, Play, Square, Smartphone, ShieldCheck, Loader2 } from 'lucide-react';

import { LARAVEL_BASE, apiFetch } from '@/lib/api';
import { usePolling } from '@/hooks/usePolling';
import { PageHeader } from '@/components/PageHeader';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ErrorBanner, EmptyState } from '@/components/ui/states';

/**
 * Page « Dev Preview » (S14) — expose un serveur de dev qui tourne sur le PC
 * pour le tester sur le téléphone, sans déploiement. Le dashboard ne fait que
 * lister/exposer : le proxy HTTPS réel est dans le bridge (cf. CDC §16.5).
 */

const POLL_INTERVAL_MS = 2500;

type DevPort = { port: number; process: string | null };
type Exposed = { target_port: number; listen_port: number; started_at: number };
type PreviewState = {
  ports: DevPort[];
  exposed: Exposed[];
  scheme: string;
  hosts: string[];
};

const EMPTY: PreviewState = { ports: [], exposed: [], scheme: 'https', hosts: [] };

async function loadPreview(): Promise<PreviewState> {
  const [portsRes, exposedRes] = await Promise.all([
    apiFetch('/api/preview/ports'),
    apiFetch('/api/preview/exposed'),
  ]);
  const ports = (await portsRes.json()).ports ?? [];
  const exposed = await exposedRes.json();
  return {
    ports,
    exposed: exposed.exposed ?? [],
    scheme: exposed.scheme ?? 'https',
    hosts: exposed.hosts ?? [],
  };
}

export default function PreviewPage() {
  const { data, error, loadedOnce, setData } = usePolling<PreviewState>(
    loadPreview,
    POLL_INTERVAL_MS,
    EMPTY,
  );
  const [busy, setBusy] = useState<number | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const exposedByPort = new Map(data.exposed.map((e) => [e.target_port, e]));
  // Union ports détectés + ports exposés (un exposé reste affiché même si le
  // scan tarde à le re-lister).
  const allPorts = Array.from(
    new Set([...data.ports.map((p) => p.port), ...data.exposed.map((e) => e.target_port)]),
  ).sort((a, b) => a - b);
  const processFor = new Map(data.ports.map((p) => [p.port, p.process]));

  const act = async (path: string, port: number) => {
    setBusy(port);
    setActionError(null);
    try {
      await apiFetch(path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ port }),
      });
      setData(await loadPreview());
    } catch (e) {
      setActionError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };

  return (
    <>
      <PageHeader
        icon={Globe}
        title="Dev Preview"
        subtitle="Teste un projet web qui tourne sur ce PC directement sur ton téléphone, sans déploiement. Choisis le(s) port(s) à exposer."
      />

      {/* Com front↔back : pour que le front joigne son API/WS, expose AUSSI le back. */}
      <div className="mb-3 flex items-start gap-3 rounded-xl border border-sky-200 bg-sky-50 p-3.5 text-sm text-sky-800">
        <Server className="mt-0.5 size-4.5 shrink-0" />
        <p>
          Expose aussi ton <strong>backend</strong> (API, WebSocket) : depuis le téléphone, les
          appels du front vers <code className="font-mono">localhost</code> seront redirigés
          automatiquement vers le service exposé — pas besoin de toucher au code du projet.
        </p>
      </div>

      {/* Rappel certificat : la WebView in-app gère le HTTPS ; cert utile pour Chrome. */}
      <div className="mb-5 flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 p-3.5 text-sm text-amber-800">
        <ShieldCheck className="mt-0.5 size-4.5 shrink-0" />
        <p>
          Les projets sont servis en <strong>HTTPS</strong>. L’app Linkup ouvre tout dans une
          WebView de confiance (rien à installer). Le <strong>certificat Linkup</strong> n’est
          requis que pour « Ouvrir dans Chrome » (PWA / Web Push / DevTools).
        </p>
      </div>

      {error && <ErrorBanner message={error} base={LARAVEL_BASE} />}
      {actionError && <ErrorBanner message={actionError} />}

      {loadedOnce && allPorts.length === 0 && !error && (
        <EmptyState icon={Server}>
          Aucun serveur de dev détecté. Lance ton projet (ex.{' '}
          <code className="font-mono">npm run dev</code>) puis il apparaîtra ici.
        </EmptyState>
      )}

      <div className="space-y-3">
        {allPorts.map((port, i) => {
          const exposed = exposedByPort.get(port);
          const process = processFor.get(port);
          const isBusy = busy === port;
          return (
            <motion.div
              key={port}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3, delay: Math.min(i * 0.03, 0.25) }}
            >
              <Card className="flex flex-col gap-3 p-4">
                <div className="flex items-center justify-between gap-4">
                  <div className="flex min-w-0 items-center gap-3">
                    <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-zinc-100 text-zinc-500">
                      <Server className="size-4.5" />
                    </span>
                    <div className="min-w-0">
                      <p className="font-semibold text-zinc-900">
                        Port {port}
                        {exposed && (
                          <span className="ml-2 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700">
                            exposé
                          </span>
                        )}
                      </p>
                      {process && (
                        <p className="truncate font-mono text-xs text-zinc-400">{process}</p>
                      )}
                    </div>
                  </div>

                  {exposed ? (
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={isBusy}
                      onClick={() => act('/api/preview/unexpose', port)}
                    >
                      {isBusy ? <Loader2 className="animate-spin" /> : <Square />} Arrêter
                    </Button>
                  ) : (
                    <Button
                      size="sm"
                      disabled={isBusy}
                      onClick={() => act('/api/preview/expose', port)}
                    >
                      {isBusy ? <Loader2 className="animate-spin" /> : <Play />} Exposer
                    </Button>
                  )}
                </div>

                {exposed && (
                  <div className="flex items-center gap-2.5 rounded-xl border border-zinc-200 bg-zinc-50 px-3 py-2 text-sm text-zinc-500">
                    <Smartphone className="size-4 shrink-0 text-zinc-400" />
                    <span>
                      Visible dans l’app Linkup de ton téléphone — ouvre-le depuis là.
                    </span>
                  </div>
                )}
              </Card>
            </motion.div>
          );
        })}
      </div>
    </>
  );
}
