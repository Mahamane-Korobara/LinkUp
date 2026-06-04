'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import {
  Inbox,
  FileText,
  ExternalLink,
  Images,
  Film,
  Play,
  File,
  FileSpreadsheet,
  FileArchive,
  FileAudio,
  FileCode,
  FileType,
  type LucideIcon,
} from 'lucide-react';

import {
  LARAVEL_BASE,
  apiFetch,
  fileRawUrl,
  formatBytes,
  formatDate,
  type FileCategory,
} from '@/lib/api';
import { usePolling } from '@/hooks/usePolling';
import { cn } from '@/lib/utils';
import { PageHeader } from '@/components/PageHeader';
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
  const data = await (await apiFetch('/api/files')).json();
  return (data.files ?? []) as FileDto[];
}

// --- Aperçu des documents (onglet Fichier) ---------------------------------
// Le navigateur sait rendre INLINE les PDF et le texte brut → on les affiche en
// aperçu, comme la galerie le fait pour les photos/vidéos. Les binaires (docx,
// xlsx, zip, audio…) n'ont pas d'aperçu hors-ligne → carte à icône typée.

/** Extensions dont le contenu est du texte lisible (aperçu via un extrait). */
const TEXT_EXTS = new Set([
  'txt', 'md', 'markdown', 'csv', 'tsv', 'log', 'json', 'xml', 'yml', 'yaml',
  'ini', 'conf', 'env', 'toml', 'html', 'css', 'sql', 'sh', 'bash',
  'js', 'ts', 'jsx', 'tsx', 'py', 'php', 'java', 'c', 'cpp', 'h', 'rs', 'go', 'rb',
]);

type DocPreview = 'pdf' | 'text' | 'icon';

function extOf(filename: string): string {
  const i = filename.lastIndexOf('.');
  return i >= 0 ? filename.slice(i + 1).toLowerCase() : '';
}

function previewKind(ext: string): DocPreview {
  if (ext === 'pdf') return 'pdf';
  if (TEXT_EXTS.has(ext)) return 'text';
  return 'icon';
}

/** Icône + couleur d'accent pour les fichiers sans aperçu visuel. */
function iconFor(ext: string): { Icon: LucideIcon; cls: string } {
  if (['zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz'].includes(ext))
    return { Icon: FileArchive, cls: 'text-amber-600' };
  if (['xls', 'xlsx', 'ods'].includes(ext))
    return { Icon: FileSpreadsheet, cls: 'text-emerald-600' };
  if (['mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac'].includes(ext))
    return { Icon: FileAudio, cls: 'text-fuchsia-600' };
  if (['doc', 'docx', 'odt', 'rtf'].includes(ext))
    return { Icon: FileType, cls: 'text-blue-600' };
  if (TEXT_EXTS.has(ext)) return { Icon: FileCode, cls: 'text-violet-600' };
  return { Icon: File, cls: 'text-zinc-500' };
}

// Contenu d'un transfert terminé = immuable → on cache l'extrait texte pour ne
// pas le re-télécharger à chaque tick de polling.
const textPreviewCache = new Map<string, string>();

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
      await apiFetch(`/api/files/${transferId}/open`, { method: 'POST' });
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
        <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
          {docs.map((f, i) => (
            <FileTile
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

function FileTile({
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
  const ext = extOf(file.filename);
  const kind = previewKind(ext);
  const meta = [
    formatBytes(file.size),
    file.device ? `de ${file.device}` : null,
    formatDate(file.completed_at) || null,
  ]
    .filter(Boolean)
    .join(' · ');

  return (
    <motion.button
      type="button"
      onClick={onOpen}
      disabled={busy}
      title={`${file.filename}${meta ? ` — ${meta}` : ''} (cliquer pour ouvrir sur le PC)`}
      initial={{ opacity: 0, scale: 0.96 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.3, delay: Math.min(index * 0.03, 0.3) }}
      className="group relative flex aspect-[3/4] flex-col overflow-hidden rounded-2xl border border-zinc-200 bg-white text-left outline-none focus-visible:ring-2 focus-visible:ring-violet-500/50"
    >
      {/* Zone d'aperçu : PDF (1ʳᵉ page), extrait texte, ou icône typée. */}
      <div className="relative flex-1 overflow-hidden bg-zinc-50">
        {kind === 'pdf' && <PdfPreview id={file.transfer_id} />}
        {kind === 'text' && <TextPreview id={file.transfer_id} />}
        {kind === 'icon' && <IconPreview ext={ext} />}

        <span className="absolute left-2 top-2 inline-flex items-center rounded-md bg-black/65 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-white backdrop-blur-sm">
          {ext || 'fichier'}
        </span>
      </div>

      {/* Pied : nom + taille + action « ouvrir sur le PC ». */}
      <div className="flex items-center justify-between gap-2 border-t border-zinc-100 px-2.5 py-2">
        <div className="min-w-0">
          <div className="truncate text-xs font-semibold text-zinc-800">{file.filename}</div>
          <div className="truncate text-[11px] text-zinc-400">{formatBytes(file.size)}</div>
        </div>
        <span className="grid size-7 shrink-0 place-items-center rounded-lg bg-zinc-100 text-zinc-500 transition-colors group-hover:bg-violet-600 group-hover:text-white">
          {busy ? <span className="text-[10px]">…</span> : <ExternalLink className="size-3.5" />}
        </span>
      </div>
    </motion.button>
  );
}

function PdfPreview({ id }: { id: string }) {
  // #toolbar=0… masque l'UI du viewer Chromium → vignette propre de la 1ʳᵉ page.
  // loading=lazy : ne charge que les PDF réellement visibles (grille longue).
  const src = `${fileRawUrl(id)}#toolbar=0&navpanes=0&scrollbar=0&view=FitH&page=1`;
  return (
    <iframe
      src={src}
      title="Aperçu PDF"
      tabIndex={-1}
      loading="lazy"
      className="pointer-events-none absolute inset-0 size-full border-0 bg-white"
    />
  );
}

function TextPreview({ id }: { id: string }) {
  const [text, setText] = useState<string | null>(textPreviewCache.get(id) ?? null);

  useEffect(() => {
    if (text !== null) return;
    let active = true;
    // Range : on ne tire que les 2 premiers Ko (suffisant pour l'aperçu).
    fetch(fileRawUrl(id), { headers: { Range: 'bytes=0-2047' } })
      .then((r) => r.text())
      .then((t) => {
        const snippet = t.slice(0, 1200);
        textPreviewCache.set(id, snippet);
        if (active) setText(snippet);
      })
      .catch(() => {
        if (active) setText('');
      });
    return () => {
      active = false;
    };
  }, [id, text]);

  return (
    <pre className="pointer-events-none absolute inset-0 size-full overflow-hidden whitespace-pre-wrap break-words p-2.5 text-[8px] leading-[1.35] text-zinc-600">
      {text ?? ''}
    </pre>
  );
}

function IconPreview({ ext }: { ext: string }) {
  const { Icon, cls } = iconFor(ext);
  return (
    <div className="absolute inset-0 grid place-items-center">
      <Icon className={cn('size-14', cls)} strokeWidth={1.5} />
    </div>
  );
}
