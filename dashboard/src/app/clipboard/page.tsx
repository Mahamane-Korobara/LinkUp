'use client';

import { useState } from 'react';
import { motion } from 'framer-motion';
import {
  ClipboardList,
  Copy,
  Check,
  ExternalLink,
  Smartphone,
  Monitor,
  Clock,
} from 'lucide-react';

import { DASHBOARD_HEADERS, LARAVEL_BASE, formatDate } from '@/lib/api';
import { usePolling } from '@/hooks/usePolling';
import { PageHeader } from '@/components/PageHeader';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ErrorBanner, EmptyState } from '@/components/ui/states';
import { cn } from '@/lib/utils';

/**
 * Page « Presse-papier » (S5) — logique inchangée : poll /api/clipboard/history,
 * copy-back via navigator.clipboard, filtres origine, ouverture des liens.
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
  { key: 'sent', label: 'Du téléphone' },
  { key: 'received', label: 'Du PC' },
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
    <>
      <PageHeader
        icon={ClipboardList}
        title="Presse-papier"
        subtitle="Les textes synchronisés avec ton téléphone. Clique pour recopier sur ce PC. Effacé automatiquement après 2 jours."
      />

      <div className="mb-4 inline-flex gap-1 rounded-xl border border-zinc-200 bg-white p-1">
        {FILTERS.map((f) => (
          <button
            key={f.key}
            onClick={() => setFilter(f.key)}
            className={cn(
              'rounded-lg px-3.5 py-1.5 text-sm font-medium transition-colors',
              filter === f.key
                ? 'bg-violet-600 text-white'
                : 'text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900',
            )}
          >
            {f.label}
          </button>
        ))}
      </div>

      {error && <ErrorBanner message={error} base={LARAVEL_BASE} />}

      {loadedOnce && shown.length === 0 && !error && (
        <EmptyState icon={ClipboardList}>
          {items.length === 0
            ? 'Aucun contenu partagé pour l’instant. Copie un texte sur ton téléphone pour le voir ici.'
            : 'Rien dans ce filtre.'}
        </EmptyState>
      )}

      <div className="space-y-3">
        {shown.map((item, i) => {
          const fromPc = item.origin === 'pc';
          return (
            <motion.div
              key={item.id}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3, delay: Math.min(i * 0.03, 0.25) }}
            >
              <Card className="flex items-start justify-between gap-4 p-4">
                <div className="min-w-0 flex-1">
                  <p className="line-clamp-3 whitespace-pre-wrap break-words font-mono text-sm text-zinc-800">
                    {item.content}
                  </p>
                  <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-xs text-zinc-400">
                    <span className="inline-flex items-center gap-1">
                      {fromPc ? (
                        <Monitor className="size-3.5" />
                      ) : (
                        <Smartphone className="size-3.5" />
                      )}
                      {fromPc ? 'depuis le PC' : 'depuis le téléphone'}
                    </span>
                    {formatDate(item.created_at) && (
                      <span className="inline-flex items-center gap-1">
                        <Clock className="size-3.5" /> {formatDate(item.created_at)}
                      </span>
                    )}
                  </div>
                </div>

                <div className="flex shrink-0 flex-col gap-2">
                  <Button variant="outline" size="sm" onClick={() => copy(item)}>
                    {copiedId === item.id ? <Check /> : <Copy />}
                    {copiedId === item.id ? 'Copié' : 'Copier'}
                  </Button>
                  {isUrl(item.content) && (
                    <a
                      href={item.content.trim()}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex h-8 items-center justify-center gap-2 rounded-xl border border-zinc-200 bg-white px-3 text-[13px] font-semibold text-zinc-700 transition-colors hover:bg-zinc-50"
                    >
                      <ExternalLink className="size-4" /> Ouvrir
                    </a>
                  )}
                </div>
              </Card>
            </motion.div>
          );
        })}
      </div>
    </>
  );
}
