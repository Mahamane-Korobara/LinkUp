'use client';

import { useCallback, useEffect, useState } from 'react';

import { DASHBOARD_HEADERS, LARAVEL_BASE, formatBytes, formatDate } from '../../lib/api';

/**
 * Page « Galerie » (S6) — parcourt les photos/vidéos indexées depuis les
 * téléphones, par vignettes paginées. Les originaux restent sur le tél jusqu'à
 * un import (à venir).
 */

const PAGE_SIZE = 50;

type ImportStatus = 'requested' | 'done' | null;

type GalleryItem = {
  id: string;
  device_id: string | null;
  media_id: string;
  mime: string;
  size: number;
  taken_at: string | null;
  width: number | null;
  height: number | null;
  has_thumb: boolean;
  import_status: ImportStatus;
};

async function loadGallery(page: number): Promise<{ items: GalleryItem[]; lastPage: number; total: number }> {
  const res = await fetch(`${LARAVEL_BASE}/api/gallery?page=${page}&size=${PAGE_SIZE}`, {
    headers: DASHBOARD_HEADERS,
    cache: 'no-store',
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  return {
    items: (data.items ?? []) as GalleryItem[],
    lastPage: (data.last_page ?? 1) as number,
    total: (data.total ?? 0) as number,
  };
}

/** Demande au PC d'importer les originaux de la sélection. */
async function requestImport(ids: string[]): Promise<number> {
  const res = await fetch(`${LARAVEL_BASE}/api/gallery/import`, {
    method: 'POST',
    headers: { ...DASHBOARD_HEADERS, 'Content-Type': 'application/json' },
    body: JSON.stringify({ ids }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return ((await res.json()).requested ?? 0) as number;
}

/**
 * Vignette : un `<img>` ne peut pas envoyer le header `X-Linkup-Client` exigé
 * par l'endpoint → on récupère l'image via fetch (avec le header) puis on
 * l'affiche via une object URL.
 */
function Thumb({
  item,
  selected,
  onToggle,
}: {
  item: GalleryItem;
  selected: boolean;
  onToggle: (id: string) => void;
}) {
  const [url, setUrl] = useState<string | null>(null);

  useEffect(() => {
    if (!item.has_thumb) return;
    let active = true;
    let objectUrl: string | null = null;
    fetch(`${LARAVEL_BASE}/api/gallery/${item.id}/thumb`, { headers: DASHBOARD_HEADERS })
      .then((r) => (r.ok ? r.blob() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((blob) => {
        if (!active) return;
        objectUrl = URL.createObjectURL(blob);
        setUrl(objectUrl);
      })
      .catch(() => {});
    return () => {
      active = false;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [item.id, item.has_thumb]);

  const isVideo = item.mime.startsWith('video/');

  return (
    <button
      type="button"
      onClick={() => onToggle(item.id)}
      className={`relative aspect-square overflow-hidden rounded-lg bg-slate-200 ring-offset-2 transition ${
        selected ? 'ring-2 ring-indigo-600' : 'hover:ring-2 hover:ring-slate-300'
      }`}
    >
      {url ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={url} alt={item.media_id} className="h-full w-full object-cover" />
      ) : (
        <div className="flex h-full w-full items-center justify-center text-slate-400">
          {item.has_thumb ? '…' : '🕓'}
        </div>
      )}
      {isVideo && (
        <span className="absolute bottom-1 right-1 rounded bg-black/60 px-1 text-xs text-white">▶</span>
      )}
      {item.import_status === 'done' && (
        <span className="absolute top-1 left-1 rounded bg-green-600 px-1 text-xs text-white" title="Original importé">
          ✓
        </span>
      )}
      {item.import_status === 'requested' && (
        <span className="absolute top-1 left-1 rounded bg-amber-500 px-1 text-xs text-white" title="Import demandé — en attente du téléphone">
          ⏳
        </span>
      )}
      {selected && (
        <span className="absolute top-1 right-1 flex h-5 w-5 items-center justify-center rounded-full bg-indigo-600 text-xs text-white">
          ✓
        </span>
      )}
    </button>
  );
}

export default function GalleryPage() {
  const [items, setItems] = useState<GalleryItem[]>([]);
  const [page, setPage] = useState(1);
  const [lastPage, setLastPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [importing, setImporting] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  const toggle = useCallback((id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const fetchPage = useCallback(async (p: number) => {
    setLoading(true);
    try {
      const { items: it, lastPage: lp, total: t } = await loadGallery(p);
      setItems((prev) => (p === 1 ? it : [...prev, ...it]));
      setLastPage(lp);
      setTotal(t);
      setPage(p);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchPage(1);
  }, [fetchPage]);

  const hasMore = page < lastPage;

  const doImport = useCallback(async () => {
    if (selected.size === 0) return;
    setImporting(true);
    setNotice(null);
    try {
      const n = await requestImport([...selected]);
      setNotice(`${n} import(s) demandé(s) — ouvre la galerie sur le téléphone pour envoyer les originaux.`);
      setSelected(new Set());
      await fetchPage(1); // rafraîchit les badges (requested)
    } catch (e) {
      setNotice(`Échec de la demande d'import : ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setImporting(false);
    }
  }, [selected, fetchPage]);

  return (
    <main className="min-h-screen bg-slate-50 p-8">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-2xl font-bold mb-1">Galerie</h1>
        <p className="text-slate-600 text-sm mb-4">
          Les photos &amp; vidéos de tes téléphones appairés{total > 0 ? ` — ${total} éléments` : ''}.
          {' '}Sélectionne des médias puis demande l&apos;import des originaux.
        </p>

        <div className="flex items-center gap-3 mb-4 min-h-9">
          <button
            onClick={doImport}
            disabled={selected.size === 0 || importing}
            className="px-4 py-2 text-sm rounded-lg bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-40"
          >
            {importing ? 'Demande…' : `Importer les originaux${selected.size > 0 ? ` (${selected.size})` : ''}`}
          </button>
          {selected.size > 0 && (
            <button onClick={() => setSelected(new Set())} className="text-sm text-slate-500 hover:text-slate-700">
              Tout désélectionner
            </button>
          )}
        </div>

        {notice && (
          <div className="bg-indigo-50 border border-indigo-200 rounded p-3 text-indigo-800 text-sm mb-4">
            {notice}
          </div>
        )}

        {error && (
          <div className="bg-red-50 border border-red-200 rounded p-3 text-red-700 text-sm mb-4">
            {error} — Laravel doit tourner sur <code>{LARAVEL_BASE}</code>.
          </div>
        )}

        {!loading && items.length === 0 && !error && (
          <div className="bg-white rounded-xl border border-slate-200 p-8 text-center text-slate-500">
            Aucun média indexé. Ouvre la galerie depuis l&apos;app du téléphone pour lancer l&apos;indexation.
          </div>
        )}

        <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-2">
          {items.map((item) => (
            <Thumb key={item.id} item={item} selected={selected.has(item.id)} onToggle={toggle} />
          ))}
        </div>

        {(hasMore || loading) && (
          <div className="mt-6 text-center">
            <button
              onClick={() => fetchPage(page + 1)}
              disabled={loading || !hasMore}
              className="px-4 py-2 text-sm rounded-lg bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50"
            >
              {loading ? 'Chargement…' : 'Charger plus'}
            </button>
          </div>
        )}
      </div>
    </main>
  );
}
