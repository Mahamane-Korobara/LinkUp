'use client';

import { useCallback, useEffect, useState } from 'react';

import { DASHBOARD_HEADERS, LARAVEL_BASE, formatBytes, formatDate } from '../../lib/api';

/**
 * Page « Galerie » (S6) — parcourt les photos/vidéos indexées depuis les
 * téléphones, par vignettes paginées. Les originaux restent sur le tél jusqu'à
 * un import (à venir).
 */

const PAGE_SIZE = 50;

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

/**
 * Vignette : un `<img>` ne peut pas envoyer le header `X-Linkup-Client` exigé
 * par l'endpoint → on récupère l'image via fetch (avec le header) puis on
 * l'affiche via une object URL.
 */
function Thumb({ item }: { item: GalleryItem }) {
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
    <div className="relative aspect-square overflow-hidden rounded-lg bg-slate-200">
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
    </div>
  );
}

export default function GalleryPage() {
  const [items, setItems] = useState<GalleryItem[]>([]);
  const [page, setPage] = useState(1);
  const [lastPage, setLastPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

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

  return (
    <main className="min-h-screen bg-slate-50 p-8">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-2xl font-bold mb-1">Galerie</h1>
        <p className="text-slate-600 text-sm mb-6">
          Les photos &amp; vidéos de tes téléphones appairés{total > 0 ? ` — ${total} éléments` : ''}.
        </p>

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
            <Thumb key={item.id} item={item} />
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
