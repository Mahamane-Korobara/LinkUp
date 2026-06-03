'use client';

import { useCallback, useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import {
  Inbox,
  FileText,
  ExternalLink,
  HardDrive,
  Clock,
  Images,
  Film,
  Play,
} from 'lucide-react';

import {
  DASHBOARD_HEADERS,
  LARAVEL_BASE,
  fileRawUrl,
  formatBytes,
  formatDate,
  type FileCategory,
} from '@/lib/api';
import { usePolling } from '@/hooks/usePolling';
import { cn } from '@/lib/utils';
import { PageHeader } from '@/components/PageHeader';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ErrorBanner, EmptyState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';

/**
 * Page « Fichiers reçus » (S4 + S6.6) — séparée comme sur le tél :
 *   • Galerie : photos & vidéos en grille, avec aperçu (image / 1ʳᵉ frame).
 *   • Fichier : documents et autres, en liste.
 * Logique réseau inchangée : poll /api/files (qui expose `category`),
 * POST /api/files/{id}/open pour ouvrir sur le PC, aperçu via /api/files/{id}/raw.
 */

const POLL_INTERVAL_MS = 3000;

type FileDto = {
  transfer_id: string;
  filename: string;
  category: FileCategory;
  size: number;
  device: string | null;
  completed_at: string | null;
};

type Tab = 'galerie' | 'fichier';

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
  const [tab, setTab] = useState<Tab>('galerie');
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

  const media = useMemo(
    () => files.filter((f) => f.category === 'photos' || f.category === 'video'),
    [files],
  );
  const docs = useMemo(() => files.filter((f) => f.category === 'fichiers'), [files]);

  const shownError = openError ?? error;
  const shown = tab === 'galerie' ? media : docs;

  return (
    <>
      <PageHeader
        icon={Inbox}
        title="Fichiers reçus"
        subtitle="Ce que ton téléphone t’a envoyé, rangé par type et ouvrable directement sur ce PC."
      />

      {shownError && <ErrorBanner message={shownError} base={LARAVEL_BASE} />}

      <Tabs
        tab={tab}
        onChange={setTab}
        galerieCount={media.length}
        fichierCount={docs.length}
      />

      {!loadedOnce && !error && (
        <div className="mt-4">
          {tab === 'galerie' ? (
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
              {[0, 1, 2, 3].map((i) => (
                <Skeleton key={i} className="aspect-square w-full rounded-2xl" />
              ))}
            </div>
          ) : (
            <div className="space-y-3">
              {[0, 1, 2].map((i) => (
                <Skeleton key={i} className="h-16 w-full rounded-2xl" />
              ))}
            </div>
          )}
        </div>
      )}

      {loadedOnce && shown.length === 0 && !error && (
        <div className="mt-4">
          {tab === 'galerie' ? (
            <EmptyState icon={Images}>
              Aucune photo ni vidéo reçue. Envoie des médias depuis l’onglet
              Galerie de l’app sur ton téléphone, ils apparaîtront ici.
            </EmptyState>
          ) : (
            <EmptyState icon={FileText}>
              Aucun document reçu. Envoie un fichier depuis ton téléphone, il
              apparaîtra ici.
            </EmptyState>
          )}
        </div>
      )}

      {tab === 'galerie' && media.length > 0 && (
        <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
          {media.map((f, i) => (
            <GalleryTile
              key={f.transfer_id}
              file={f}
              index={i}
              busy={busyId === f.transfer_id}
              onOpen={() => openOnPc(f.transfer_id)}
            />
          ))}
        </div>
      )}

      {tab === 'fichier' && docs.length > 0 && (
        <div className="mt-4 space-y-3">
          {docs.map((f, i) => (
            <FileRow
              key={f.transfer_id}
              file={f}
              index={i}
              busy={busyId === f.transfer_id}
              onOpen={() => openOnPc(f.transfer_id)}
            />
          ))}
        </div>
      )}
    </>
  );
}

function Tabs({
  tab,
  onChange,
  galerieCount,
  fichierCount,
}: {
  tab: Tab;
  onChange: (t: Tab) => void;
  galerieCount: number;
  fichierCount: number;
}) {
  const items: { id: Tab; label: string; icon: typeof Images; count: number }[] = [
    { id: 'galerie', label: 'Galerie', icon: Images, count: galerieCount },
    { id: 'fichier', label: 'Fichier', icon: FileText, count: fichierCount },
  ];
  return (
    <div className="inline-flex rounded-xl border border-zinc-200 bg-zinc-50 p-1">
      {items.map((it) => {
        const active = tab === it.id;
        return (
          <button
            key={it.id}
            onClick={() => onChange(it.id)}
            className={cn(
              'relative flex items-center gap-2 rounded-lg px-3.5 py-2 text-sm font-medium transition-colors',
              active ? 'text-zinc-900' : 'text-zinc-500 hover:text-zinc-700',
            )}
          >
            {active && (
              <motion.span
                layoutId="files-tab"
                className="absolute inset-0 rounded-lg bg-white shadow-card"
                transition={{ type: 'spring', stiffness: 400, damping: 32 }}
              />
            )}
            <it.icon className="relative size-4" />
            <span className="relative">{it.label}</span>
            <span
              className={cn(
                'relative rounded-md px-1.5 py-0.5 text-[11px] font-semibold tabular-nums',
                active ? 'bg-violet-100 text-violet-700' : 'bg-zinc-200/70 text-zinc-500',
              )}
            >
              {it.count}
            </span>
          </button>
        );
      })}
    </div>
  );
}

function GalleryTile({
  file,
  index,
  busy,
  onOpen,
}: {
  file: FileDto;
  index: number;
  busy: boolean;
  onOpen: () => void;
}) {
  const isVideo = file.category === 'video';
  // `#t=0.1` force le navigateur à peindre la 1ʳᵉ frame en mode metadata.
  const src = isVideo ? `${fileRawUrl(file.transfer_id)}#t=0.1` : fileRawUrl(file.transfer_id);

  return (
    <motion.button
      type="button"
      onClick={onOpen}
      disabled={busy}
      initial={{ opacity: 0, scale: 0.96 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.3, delay: Math.min(index * 0.03, 0.3) }}
      className="group relative aspect-square overflow-hidden rounded-2xl border border-zinc-200 bg-zinc-100 text-left outline-none focus-visible:ring-2 focus-visible:ring-violet-500/50"
    >
      {isVideo ? (
        <video
          src={src}
          preload="metadata"
          muted
          playsInline
          className="size-full object-cover"
        />
      ) : (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={src}
          alt={file.filename}
          loading="lazy"
          className="size-full object-cover"
        />
      )}

      {/* Badge type vidéo */}
      {isVideo && (
        <span className="absolute left-2 top-2 inline-flex items-center gap-1 rounded-md bg-black/60 px-1.5 py-0.5 text-[11px] font-medium text-white backdrop-blur-sm">
          <Film className="size-3" />
          Vidéo
        </span>
      )}

      {/* Voile + nom + action au survol */}
      <div className="pointer-events-none absolute inset-0 flex flex-col justify-end bg-gradient-to-t from-black/70 via-black/0 to-transparent opacity-0 transition-opacity group-hover:opacity-100">
        <div className="flex items-end justify-between gap-2 p-2.5">
          <span className="truncate text-xs font-medium text-white">{file.filename}</span>
          <span className="grid size-7 shrink-0 place-items-center rounded-lg bg-white/90 text-zinc-900">
            {isVideo ? <Play className="size-3.5" /> : <ExternalLink className="size-3.5" />}
          </span>
        </div>
      </div>
    </motion.button>
  );
}

function FileRow({
  file,
  index,
  busy,
  onOpen,
}: {
  file: FileDto;
  index: number;
  busy: boolean;
  onOpen: () => void;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: Math.min(index * 0.04, 0.3) }}
    >
      <Card className="flex items-center justify-between gap-4 p-4">
        <div className="flex min-w-0 items-center gap-3">
          <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-violet-50 text-violet-600">
            <FileText className="size-5" />
          </span>
          <div className="min-w-0">
            <div className="truncate font-semibold text-zinc-900">{file.filename}</div>
            <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-xs text-zinc-400">
              <span className="inline-flex items-center gap-1">
                <HardDrive className="size-3.5" /> {formatBytes(file.size)}
              </span>
              {file.device && <span>de {file.device}</span>}
              {formatDate(file.completed_at) && (
                <span className="inline-flex items-center gap-1">
                  <Clock className="size-3.5" /> {formatDate(file.completed_at)}
                </span>
              )}
            </div>
          </div>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={onOpen}
          disabled={busy}
          className="shrink-0"
        >
          <ExternalLink /> {busy ? '…' : 'Ouvrir'}
        </Button>
      </Card>
    </motion.div>
  );
}
