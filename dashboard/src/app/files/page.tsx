'use client';

import { useCallback, useState } from 'react';

import { DASHBOARD_HEADERS, LARAVEL_BASE, formatBytes, formatDate } from '../../lib/api';
import { usePolling } from '../../hooks/usePolling';

/**
 * Page « Fichiers reçus » (S4) — liste les fichiers envoyés par les téléphones
 * et permet de les ouvrir sur le PC, sans aller fouiller dans ~/Linkup/Inbox.
 */

const POLL_INTERVAL_MS = 3000;

type FileDto = {
  transfer_id: string;
  filename: string;
  size: number;
  device: string | null;
  completed_at: string | null;
};

async function loadFiles(): Promise<FileDto[]> {
  const res = await fetch(`${LARAVEL_BASE}/api/files`, {
    headers: DASHBOARD_HEADERS,
    cache: 'no-store',
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  return (data.files ?? []) as FileDto[];
}

export default function FilesPage() {
  const { data: files, error, loadedOnce } = usePolling<FileDto[]>(
    loadFiles,
    POLL_INTERVAL_MS,
    [],
  );
  const [busyId, setBusyId] = useState<string | null>(null);
  const [openError, setOpenError] = useState<string | null>(null);

  const openOnPc = useCallback(async (transferId: string) => {
    setBusyId(transferId);
    try {
      const res = await fetch(`${LARAVEL_BASE}/api/files/${transferId}/open`, {
        method: 'POST',
        headers: DASHBOARD_HEADERS,
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setOpenError(null);
    } catch (e) {
      setOpenError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusyId(null);
    }
  }, []);

  const shownError = openError ?? error;

  return (
    <main className="min-h-screen bg-slate-50 p-8">
      <div className="max-w-2xl mx-auto">
        <h1 className="text-2xl font-bold mb-1">Fichiers reçus</h1>
        <p className="text-slate-600 text-sm mb-6">
          Les fichiers envoyés depuis ton téléphone, ouvrables directement sur ce PC.
        </p>

        {shownError && (
          <div className="bg-red-50 border border-red-200 rounded p-3 text-red-700 text-sm mb-4">
            {shownError} — Laravel doit tourner sur <code>{LARAVEL_BASE}</code>.
          </div>
        )}

        {loadedOnce && files.length === 0 && !error && (
          <div className="bg-white rounded-xl border border-slate-200 p-8 text-center text-slate-500">
            Aucun fichier reçu pour l&apos;instant.
          </div>
        )}

        <div className="space-y-3">
          {files.map((f) => (
            <div
              key={f.transfer_id}
              className="bg-white rounded-xl border border-slate-200 p-4 flex items-center justify-between gap-4"
            >
              <div className="min-w-0">
                <div className="font-medium truncate">📄 {f.filename}</div>
                <div className="text-xs text-slate-500 mt-1 space-x-3">
                  <span>{formatBytes(f.size)}</span>
                  {f.device && <span>de {f.device}</span>}
                  {formatDate(f.completed_at) && <span>{formatDate(f.completed_at)}</span>}
                </div>
              </div>
              <button
                onClick={() => openOnPc(f.transfer_id)}
                disabled={busyId === f.transfer_id}
                className="px-3 py-2 text-sm rounded-lg bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50 shrink-0"
              >
                {busyId === f.transfer_id ? '…' : 'Ouvrir'}
              </button>
            </div>
          ))}
        </div>
      </div>
    </main>
  );
}
