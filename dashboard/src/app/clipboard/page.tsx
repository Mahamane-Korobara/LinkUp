'use client';

import { useState } from 'react';

import { DASHBOARD_HEADERS, LARAVEL_BASE, formatDate } from '../../lib/api';
import { usePolling } from '../../hooks/usePolling';

/**
 * Page « Presse-papier » (S5) — historique des contenus synchronisés entre le
 * téléphone et ce PC, avec copy-back (un clic = recopié dans le presse-papier
 * du navigateur). Les liens http(s) sont ouvrables directement.
 */

const POLL_INTERVAL_MS = 3000;

type ClipItem = {
  id: string;
  content: string;
  origin: string; // 'phone' | 'pc'
  device_id: string | null;
  created_at: string | null;
};

async function loadClipboard(): Promise<ClipItem[]> {
  const res = await fetch(`${LARAVEL_BASE}/api/clipboard/history`, {
    headers: DASHBOARD_HEADERS,
    cache: 'no-store',
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  return (data.items ?? []) as ClipItem[];
}

function isUrl(s: string): boolean {
  return /^https?:\/\//i.test(s.trim());
}

type ClipFilter = 'all' | 'sent' | 'received';

const FILTERS: { key: ClipFilter; label: string }[] = [
  { key: 'all', label: 'Tout' },
  { key: 'sent', label: 'Envoyés du téléphone' },
  { key: 'received', label: 'Reçus du PC' },
];

export default function ClipboardPage() {
  const { data: items, error, loadedOnce } = usePolling<ClipItem[]>(
    loadClipboard,
    POLL_INTERVAL_MS,
    [],
  );
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [filter, setFilter] = useState<ClipFilter>('all');

  const shown = items.filter((i) =>
    filter === 'all' ? true : filter === 'received' ? i.origin === 'pc' : i.origin !== 'pc',
  );

  const copy = async (item: ClipItem) => {
    try {
      await navigator.clipboard.writeText(item.content);
      setCopiedId(item.id);
      setTimeout(() => setCopiedId((c) => (c === item.id ? null : c)), 1500);
    } catch {
      // navigator.clipboard indisponible (contexte non sécurisé) — ignoré.
    }
  };

  return (
    <main className="min-h-screen bg-slate-50 p-8">
      <div className="max-w-2xl mx-auto">
        <h1 className="text-2xl font-bold mb-1">Presse-papier</h1>
        <p className="text-slate-600 text-sm mb-4">
          Les textes synchronisés avec ton téléphone. Clique pour recopier sur ce PC.
          {' '}Effacé automatiquement après 2 jours.
        </p>

        <div className="flex gap-2 mb-4">
          {FILTERS.map((f) => (
            <button
              key={f.key}
              onClick={() => setFilter(f.key)}
              className={`px-3 py-1.5 text-sm rounded-full border ${
                filter === f.key
                  ? 'bg-indigo-600 text-white border-indigo-600'
                  : 'bg-white text-slate-600 border-slate-300 hover:bg-slate-50'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>

        {error && (
          <div className="bg-red-50 border border-red-200 rounded p-3 text-red-700 text-sm mb-4">
            {error} — Laravel doit tourner sur <code>{LARAVEL_BASE}</code>.
          </div>
        )}

        {loadedOnce && shown.length === 0 && !error && (
          <div className="bg-white rounded-xl border border-slate-200 p-8 text-center text-slate-500">
            {items.length === 0 ? 'Aucun contenu partagé pour l\'instant.' : 'Rien dans ce filtre.'}
          </div>
        )}

        <div className="space-y-3">
          {shown.map((item) => (
            <div
              key={item.id}
              className="bg-white rounded-xl border border-slate-200 p-4 flex items-start justify-between gap-4"
            >
              <div className="min-w-0">
                <div className="font-mono text-sm break-words whitespace-pre-wrap line-clamp-3">
                  {item.content}
                </div>
                <div className="text-xs text-slate-500 mt-1 space-x-3">
                  <span>{item.origin === 'pc' ? '🖥️ depuis le PC' : '📱 depuis le téléphone'}</span>
                  {formatDate(item.created_at) && <span>{formatDate(item.created_at)}</span>}
                </div>
              </div>
              <div className="flex flex-col gap-2 shrink-0">
                <button
                  onClick={() => copy(item)}
                  className="px-3 py-2 text-sm rounded-lg bg-indigo-600 text-white hover:bg-indigo-700"
                >
                  {copiedId === item.id ? 'Copié ✓' : 'Copier'}
                </button>
                {isUrl(item.content) && (
                  <a
                    href={item.content.trim()}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="px-3 py-2 text-sm text-center rounded-lg border border-slate-300 text-slate-700 hover:bg-slate-50"
                  >
                    Ouvrir
                  </a>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </main>
  );
}
