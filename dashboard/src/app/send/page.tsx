'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { motion } from 'framer-motion';
import {
  SendHorizontal,
  Smartphone,
  Paperclip,
  CheckCircle2,
  XCircle,
  Loader2,
} from 'lucide-react';

import { DASHBOARD_HEADERS, LARAVEL_BASE, formatBytes } from '@/lib/api';
import { PageHeader } from '@/components/PageHeader';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ErrorBanner, EmptyState } from '@/components/ui/states';

/**
 * Page « Envoyer » (S6 — PC → tél). Logique inchangée : loadDevices (approuvés),
 * POST /api/outbox/{device} par fichier, suivi par fichier.
 */

type Device = { device_id: string; name: string | null; status: string };
type SendState = { name: string; status: 'pending' | 'ok' | 'error'; message?: string };

async function loadDevices(): Promise<Device[]> {
  const res = await fetch(`${LARAVEL_BASE}/api/pairing/devices`, {
    headers: DASHBOARD_HEADERS,
    cache: 'no-store',
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  return ((data.devices ?? []) as Device[]).filter((d) => d.status === 'approved');
}

async function sendFile(deviceId: string, file: File): Promise<void> {
  const form = new FormData();
  form.append('file', file);
  const res = await fetch(`${LARAVEL_BASE}/api/outbox/${deviceId}`, {
    method: 'POST',
    headers: DASHBOARD_HEADERS,
    body: form,
  });
  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try {
      msg = (await res.json()).message ?? msg;
    } catch {
      /* corps non-JSON */
    }
    throw new Error(msg);
  }
}

export default function SendPage() {
  const [devices, setDevices] = useState<Device[]>([]);
  const [deviceId, setDeviceId] = useState<string>('');
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const [results, setResults] = useState<SendState[]>([]);
  const [picked, setPicked] = useState<string[]>([]);
  const fileInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    loadDevices()
      .then((ds) => {
        setDevices(ds);
        if (ds.length > 0) setDeviceId(ds[0].device_id);
      })
      .catch((e) => setError(e instanceof Error ? e.message : String(e)));
  }, []);

  const onSend = useCallback(async () => {
    const files = Array.from(fileInput.current?.files ?? []);
    if (files.length === 0 || !deviceId) return;

    setSending(true);
    setResults(files.map((f) => ({ name: f.name, status: 'pending' as const })));

    for (let i = 0; i < files.length; i++) {
      try {
        await sendFile(deviceId, files[i]);
        setResults((prev) => prev.map((r, j) => (j === i ? { ...r, status: 'ok' } : r)));
      } catch (e) {
        setResults((prev) =>
          prev.map((r, j) =>
            j === i
              ? { ...r, status: 'error', message: e instanceof Error ? e.message : String(e) }
              : r,
          ),
        );
      }
    }
    setSending(false);
    if (fileInput.current) fileInput.current.value = '';
    setPicked([]);
  }, [deviceId]);

  return (
    <>
      <PageHeader
        icon={SendHorizontal}
        title="Envoyer au téléphone"
        subtitle="Dépose des fichiers pour un téléphone appairé : il les récupère depuis l’écran « Reçus du PC »."
      />

      {error && <ErrorBanner message={error} base={LARAVEL_BASE} />}

      {devices.length === 0 && !error ? (
        <EmptyState icon={Smartphone}>
          Aucun téléphone approuvé. Appaire et approuve un téléphone d’abord.
        </EmptyState>
      ) : (
        <Card className="space-y-5 p-6">
          <label className="block">
            <span className="mb-1.5 block text-sm font-medium text-zinc-700">Téléphone</span>
            <div className="relative">
              <Smartphone className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-zinc-400" />
              <select
                value={deviceId}
                onChange={(e) => setDeviceId(e.target.value)}
                className="w-full appearance-none rounded-xl border border-zinc-200 bg-white py-2.5 pl-9 pr-3 text-sm outline-none focus:border-violet-400 focus:ring-2 focus:ring-violet-500/20"
              >
                {devices.map((d) => (
                  <option key={d.device_id} value={d.device_id}>
                    {d.name ?? 'Téléphone'}
                  </option>
                ))}
              </select>
            </div>
          </label>

          <div>
            <span className="mb-1.5 block text-sm font-medium text-zinc-700">Fichiers</span>
            <label className="flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-zinc-300 bg-zinc-50/60 px-4 py-8 text-center transition-colors hover:border-violet-400 hover:bg-violet-50/40">
              <Paperclip className="size-6 text-zinc-400" />
              <span className="text-sm font-medium text-zinc-600">
                {picked.length > 0
                  ? `${picked.length} fichier${picked.length > 1 ? 's' : ''} sélectionné${picked.length > 1 ? 's' : ''}`
                  : 'Clique pour choisir des fichiers'}
              </span>
              {picked.length > 0 && (
                <span className="max-w-full truncate text-xs text-zinc-400">
                  {picked.join(', ')}
                </span>
              )}
              <input
                ref={fileInput}
                type="file"
                multiple
                className="hidden"
                onChange={(e) =>
                  setPicked(Array.from(e.target.files ?? []).map((f) => f.name))
                }
              />
            </label>
          </div>

          <div className="flex items-center justify-between">
            <p className="text-xs text-zinc-400">
              Taille max par fichier : {formatBytes(200 * 1024 * 1024)}.
            </p>
            <Button onClick={onSend} disabled={sending || !deviceId || picked.length === 0}>
              {sending ? <Loader2 className="animate-spin" /> : <SendHorizontal />}
              {sending ? 'Envoi…' : 'Envoyer'}
            </Button>
          </div>

          {results.length > 0 && (
            <ul className="divide-y divide-zinc-100 border-t border-zinc-100 pt-2 text-sm">
              {results.map((r, i) => (
                <li key={i} className="flex items-center justify-between gap-3 py-2">
                  <span className="truncate text-zinc-700">{r.name}</span>
                  <span
                    className={
                      r.status === 'ok'
                        ? 'inline-flex items-center gap-1.5 font-medium text-emerald-600'
                        : r.status === 'error'
                          ? 'inline-flex items-center gap-1.5 font-medium text-red-600'
                          : 'inline-flex items-center gap-1.5 text-zinc-400'
                    }
                  >
                    {r.status === 'ok' ? (
                      <>
                        <CheckCircle2 className="size-4" /> déposé
                      </>
                    ) : r.status === 'error' ? (
                      <>
                        <XCircle className="size-4" /> {r.message}
                      </>
                    ) : (
                      <>
                        <Loader2 className="size-4 animate-spin" /> envoi
                      </>
                    )}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}
    </>
  );
}
