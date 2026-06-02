'use client';

import { useCallback, useState } from 'react';
import { motion } from 'framer-motion';
import { Inbox, FileText, ExternalLink, HardDrive, Clock } from 'lucide-react';

import { DASHBOARD_HEADERS, LARAVEL_BASE, formatBytes, formatDate } from '@/lib/api';
import { usePolling } from '@/hooks/usePolling';
import { PageHeader } from '@/components/PageHeader';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ErrorBanner, EmptyState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';

/**
 * Page « Fichiers reçus » (S4) — logique inchangée : poll /api/files,
 * POST /api/files/{id}/open pour ouvrir sur le PC.
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
    <>
      <PageHeader
        icon={Inbox}
        title="Fichiers reçus"
        subtitle="Les fichiers envoyés depuis ton téléphone, ouvrables directement sur ce PC."
      />

      {shownError && <ErrorBanner message={shownError} base={LARAVEL_BASE} />}

      {!loadedOnce && !error && (
        <div className="space-y-3">
          {[0, 1, 2].map((i) => (
            <Skeleton key={i} className="h-16 w-full rounded-2xl" />
          ))}
        </div>
      )}

      {loadedOnce && files.length === 0 && !error && (
        <EmptyState icon={Inbox}>
          Aucun fichier reçu pour l’instant. Envoie un fichier depuis l’app sur
          ton téléphone, il apparaîtra ici.
        </EmptyState>
      )}

      <div className="space-y-3">
        {files.map((f, i) => (
          <motion.div
            key={f.transfer_id}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.3, delay: Math.min(i * 0.04, 0.3) }}
          >
            <Card className="flex items-center justify-between gap-4 p-4">
              <div className="flex min-w-0 items-center gap-3">
                <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-violet-50 text-violet-600">
                  <FileText className="size-5" />
                </span>
                <div className="min-w-0">
                  <div className="truncate font-semibold text-zinc-900">
                    {f.filename}
                  </div>
                  <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-xs text-zinc-400">
                    <span className="inline-flex items-center gap-1">
                      <HardDrive className="size-3.5" /> {formatBytes(f.size)}
                    </span>
                    {f.device && <span>de {f.device}</span>}
                    {formatDate(f.completed_at) && (
                      <span className="inline-flex items-center gap-1">
                        <Clock className="size-3.5" /> {formatDate(f.completed_at)}
                      </span>
                    )}
                  </div>
                </div>
              </div>
              <Button
                variant="outline"
                size="sm"
                onClick={() => openOnPc(f.transfer_id)}
                disabled={busyId === f.transfer_id}
                className="shrink-0"
              >
                <ExternalLink /> {busyId === f.transfer_id ? '…' : 'Ouvrir'}
              </Button>
            </Card>
          </motion.div>
        ))}
      </div>
    </>
  );
}
