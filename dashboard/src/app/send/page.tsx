'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import {
  SendHorizontal,
  Smartphone,
  Paperclip,
  CheckCircle2,
  XCircle,
  Loader2,
  X,
  FileText,
} from 'lucide-react';

import {
  LARAVEL_BASE,
  apiFetch,
  formatBytes,
  loadDevices,
  type DeviceDto,
} from '@/lib/api';
import { PageHeader } from '@/components/PageHeader';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ErrorBanner, EmptyState } from '@/components/ui/states';

/**
 * Page « Envoyer » (S6 — PC → tél).
 *
 * Sélection MULTIPLE et cumulative : on peut piocher des fichiers en plusieurs
 * fois (ils s'ajoutent à la file au lieu de se remplacer), en retirer un, puis
 * tout envoyer d'un coup. Chaque fichier part en POST /api/outbox/{device} et a
 * son propre statut. Les envois réussis quittent la file ; les échecs y restent
 * pour pouvoir réessayer.
 */

/** Statut d'un fichier : 'pending' | 'ok' | message d'erreur. */
type Status = 'pending' | 'ok' | string;

/** Téléphones APPROUVÉS uniquement (seuls éligibles à recevoir un fichier). */
async function loadApprovedDevices(): Promise<DeviceDto[]> {
  return (await loadDevices()).filter((d) => d.status === 'approved');
}

async function sendFile(deviceId: string, file: File): Promise<void> {
  const form = new FormData();
  form.append('file', file);
  // apiFetch remonte déjà le message d'erreur JSON de Laravel (ex. POST trop gros).
  await apiFetch(`/api/outbox/${deviceId}`, { method: 'POST', body: form });
}

/** Clé stable d'un fichier (anti-doublon dans la file). */
const keyOf = (f: File) => `${f.name}-${f.size}-${f.lastModified}`;

export default function SendPage() {
  const [devices, setDevices] = useState<DeviceDto[]>([]);
  const [deviceId, setDeviceId] = useState<string>('');
  const [error, setError] = useState<string | null>(null);
  const [files, setFiles] = useState<File[]>([]);
  const [results, setResults] = useState<Record<string, Status>>({});
  const [sending, setSending] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    loadApprovedDevices()
      .then((ds) => {
        setDevices(ds);
        if (ds.length > 0) setDeviceId(ds[0].device_id);
      })
      .catch((e) => setError(e instanceof Error ? e.message : String(e)));
  }, []);

  // Ajoute la sélection à la file (cumulatif + anti-doublon).
  const addFiles = useCallback((picked: FileList | null) => {
    if (!picked || picked.length === 0) return;
    setFiles((prev) => {
      const seen = new Set(prev.map(keyOf));
      const next = [...prev];
      for (const f of Array.from(picked)) {
        if (!seen.has(keyOf(f))) {
          seen.add(keyOf(f));
          next.push(f);
        }
      }
      return next;
    });
  }, []);

  const removeFile = useCallback((key: string) => {
    setFiles((prev) => prev.filter((f) => keyOf(f) !== key));
    setResults((r) => {
      if (!(key in r)) return r;
      const rest = { ...r };
      delete rest[key];
      return rest;
    });
  }, []);

  const onSend = useCallback(async () => {
    if (files.length === 0 || !deviceId) return;
    setSending(true);

    const succeeded = new Set<string>();
    for (const f of files) {
      const k = keyOf(f);
      setResults((r) => ({ ...r, [k]: 'pending' }));
      try {
        await sendFile(deviceId, f);
        setResults((r) => ({ ...r, [k]: 'ok' }));
        succeeded.add(k);
      } catch (e) {
        setResults((r) => ({ ...r, [k]: e instanceof Error ? e.message : String(e) }));
      }
    }

    setSending(false);
    // Les réussis quittent la file ; les échecs restent (réessai possible).
    setFiles((prev) => prev.filter((f) => !succeeded.has(keyOf(f))));
  }, [files, deviceId]);

  const totalBytes = files.reduce((sum, f) => sum + f.size, 0);

  return (
    <>
      <PageHeader
        icon={SendHorizontal}
        title="Envoyer au téléphone"
        subtitle="Dépose un ou plusieurs fichiers pour un téléphone appairé : il les récupère depuis l’écran « Reçus du PC »."
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
            <div className="mb-1.5 flex items-center justify-between">
              <span className="text-sm font-medium text-zinc-700">Fichiers</span>
              {files.length > 0 && (
                <span className="text-xs text-zinc-400">
                  {files.length} fichier{files.length > 1 ? 's' : ''} · {formatBytes(totalBytes)}
                </span>
              )}
            </div>

            <label className="flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-zinc-300 bg-zinc-50/60 px-4 py-7 text-center transition-colors hover:border-violet-400 hover:bg-violet-50/40">
              <Paperclip className="size-6 text-zinc-400" />
              <span className="text-sm font-medium text-zinc-600">
                {files.length > 0 ? 'Ajouter d’autres fichiers' : 'Clique pour choisir des fichiers'}
              </span>
              <span className="text-xs text-zinc-400">
                Sélection multiple possible (Ctrl/Maj), ou en plusieurs fois.
              </span>
              <input
                ref={inputRef}
                type="file"
                multiple
                className="hidden"
                onChange={(e) => {
                  addFiles(e.target.files);
                  // Réinitialise pour pouvoir re-choisir le même fichier ensuite.
                  e.target.value = '';
                }}
              />
            </label>

            {files.length > 0 && (
              <ul className="mt-3 space-y-1.5">
                {files.map((f) => {
                  const k = keyOf(f);
                  const st = results[k];
                  return (
                    <li
                      key={k}
                      className="flex items-center gap-3 rounded-xl border border-zinc-100 bg-white px-3 py-2 shadow-card"
                    >
                      <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-zinc-100 text-zinc-500">
                        <FileText className="size-4" />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm font-medium text-zinc-800">
                          {f.name}
                        </span>
                        <span className="text-xs text-zinc-400">{formatBytes(f.size)}</span>
                      </span>
                      <StatusTag status={st} />
                      {!sending && st !== 'ok' && (
                        <button
                          type="button"
                          onClick={() => removeFile(k)}
                          aria-label="Retirer"
                          className="grid size-7 shrink-0 place-items-center rounded-lg text-zinc-400 hover:bg-zinc-100 hover:text-zinc-700"
                        >
                          <X className="size-4" />
                        </button>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </div>

          <div className="flex items-center justify-between">
            <p className="text-xs text-zinc-400">
              Taille max par fichier : {formatBytes(200 * 1024 * 1024)}.
            </p>
            <Button onClick={onSend} disabled={sending || !deviceId || files.length === 0}>
              {sending ? <Loader2 className="animate-spin" /> : <SendHorizontal />}
              {sending
                ? 'Envoi…'
                : `Envoyer${files.length > 0 ? ` (${files.length})` : ''}`}
            </Button>
          </div>
        </Card>
      )}
    </>
  );
}

function StatusTag({ status }: { status?: Status }) {
  if (!status) return null;
  if (status === 'ok') {
    return (
      <span className="inline-flex shrink-0 items-center gap-1.5 text-sm font-medium text-emerald-600">
        <CheckCircle2 className="size-4" /> déposé
      </span>
    );
  }
  if (status === 'pending') {
    return (
      <span className="inline-flex shrink-0 items-center gap-1.5 text-sm text-zinc-400">
        <Loader2 className="size-4 animate-spin" /> envoi
      </span>
    );
  }
  return (
    <span
      className="inline-flex shrink-0 items-center gap-1.5 text-sm font-medium text-red-600"
      title={status}
    >
      <XCircle className="size-4" /> échec
    </span>
  );
}
