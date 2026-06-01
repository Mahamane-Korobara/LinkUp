'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

import { DASHBOARD_HEADERS, LARAVEL_BASE, formatBytes } from '../../lib/api';

/**
 * Page « Envoyer » (S6 — PC → tél). Le PC dépose des fichiers dans l'outbox pour
 * un téléphone appairé ; celui-ci les récupère depuis l'app (« Reçus du PC »).
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
    headers: DASHBOARD_HEADERS, // pas de Content-Type : le navigateur pose le boundary
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
            j === i ? { ...r, status: 'error', message: e instanceof Error ? e.message : String(e) } : r,
          ),
        );
      }
    }
    setSending(false);
    if (fileInput.current) fileInput.current.value = '';
  }, [deviceId]);

  return (
    <main className="min-h-screen bg-slate-50 p-8">
      <div className="max-w-2xl mx-auto">
        <h1 className="text-2xl font-bold mb-1">Envoyer au téléphone</h1>
        <p className="text-slate-600 text-sm mb-6">
          Choisis des fichiers : ils seront déposés pour le téléphone, qui les enregistrera dans sa galerie
          depuis l&apos;écran « Reçus du PC ».
        </p>

        {error && (
          <div className="bg-red-50 border border-red-200 rounded p-3 text-red-700 text-sm mb-4">
            {error} — Laravel doit tourner sur <code>{LARAVEL_BASE}</code>.
          </div>
        )}

        {devices.length === 0 && !error ? (
          <div className="bg-white rounded-xl border border-slate-200 p-8 text-center text-slate-500">
            Aucun téléphone appairé. Appaire un téléphone d&apos;abord.
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-slate-200 p-6 space-y-4">
            <label className="block">
              <span className="text-sm font-medium text-slate-700">Téléphone</span>
              <select
                value={deviceId}
                onChange={(e) => setDeviceId(e.target.value)}
                className="mt-1 block w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
              >
                {devices.map((d) => (
                  <option key={d.device_id} value={d.device_id}>
                    {d.name ?? 'Téléphone'}
                  </option>
                ))}
              </select>
            </label>

            <label className="block">
              <span className="text-sm font-medium text-slate-700">Fichiers</span>
              <input
                ref={fileInput}
                type="file"
                multiple
                className="mt-1 block w-full text-sm text-slate-600 file:mr-3 file:rounded-lg file:border-0 file:bg-indigo-50 file:px-4 file:py-2 file:text-indigo-700"
              />
            </label>

            <button
              onClick={onSend}
              disabled={sending || !deviceId}
              className="px-4 py-2 text-sm rounded-lg bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50"
            >
              {sending ? 'Envoi…' : 'Envoyer'}
            </button>

            {results.length > 0 && (
              <ul className="text-sm divide-y divide-slate-100 border-t border-slate-100 pt-2">
                {results.map((r, i) => (
                  <li key={i} className="flex items-center justify-between py-1.5">
                    <span className="truncate">{r.name}</span>
                    <span
                      className={
                        r.status === 'ok'
                          ? 'text-green-600'
                          : r.status === 'error'
                            ? 'text-red-600'
                            : 'text-slate-400'
                      }
                    >
                      {r.status === 'ok' ? '✓ déposé' : r.status === 'error' ? `✗ ${r.message}` : '…'}
                    </span>
                  </li>
                ))}
              </ul>
            )}

            <p className="text-xs text-slate-400">Taille max par fichier : {formatBytes(200 * 1024 * 1024)}.</p>
          </div>
        )}
      </div>
    </main>
  );
}
