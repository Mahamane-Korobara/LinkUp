'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Trash2,
  TriangleAlert,
  Inbox,
  ClipboardList,
  Smartphone,
  Undo2,
  Check,
  Loader2,
} from 'lucide-react';

import { LARAVEL_BASE, apiFetch, formatBytes } from '@/lib/api';
import { usePolling } from '@/hooks/usePolling';
import { PageHeader } from '@/components/PageHeader';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ErrorBanner } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';

/**
 * Réinitialisation du PC : efface TOUT ce que les téléphones ont laissé
 * (fichiers reçus, transferts, presse-papier, pairing).
 *
 * UX en deux garde-fous : (1) une modale de confirmation qui détaille ce qui
 * va disparaître, puis (2) un compte à rebours de 5 s ANNULABLE avant que la
 * suppression ne parte réellement au serveur. Tant que le rebours n'est pas
 * écoulé, rien n'est touché.
 */

const UNDO_SECONDS = 5;
const POLL_INTERVAL_MS = 5000;

type Summary = { files: number; bytes: number; clipboard: number; devices: number };
type Phase = 'idle' | 'pending' | 'deleting' | 'done';

async function loadSummary(): Promise<Summary> {
  return (await (await apiFetch('/api/data/summary')).json()) as Summary;
}

export default function DataPage() {
  const {
    data: summary,
    error: loadError,
    loadedOnce,
    setData,
  } = usePolling<Summary | null>(loadSummary, POLL_INTERVAL_MS, null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [phase, setPhase] = useState<Phase>('idle');
  const [remaining, setRemaining] = useState(UNDO_SECONDS);

  const tickRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const fireRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearTimers = useCallback(() => {
    if (tickRef.current) clearInterval(tickRef.current);
    if (fireRef.current) clearTimeout(fireRef.current);
    tickRef.current = null;
    fireRef.current = null;
  }, []);

  // Nettoyage si on quitte la page pendant le rebours → aucune suppression.
  useEffect(() => clearTimers, [clearTimers]);

  const wipe = useCallback(async () => {
    clearTimers();
    setPhase('deleting');
    try {
      await apiFetch('/api/data', { method: 'DELETE' });
      setPhase('done');
      setActionError(null);
      setData(await loadSummary());
    } catch (e) {
      setActionError(e instanceof Error ? e.message : String(e));
      setPhase('idle');
    }
  }, [clearTimers, setData]);

  // Lance le rebours annulable de 5 s après confirmation.
  const armCountdown = useCallback(() => {
    setConfirmOpen(false);
    setActionError(null);
    setRemaining(UNDO_SECONDS);
    setPhase('pending');
    tickRef.current = setInterval(() => {
      setRemaining((r) => Math.max(0, r - 1));
    }, 1000);
    fireRef.current = setTimeout(wipe, UNDO_SECONDS * 1000);
  }, [wipe]);

  const cancel = useCallback(() => {
    clearTimers();
    setPhase('idle');
  }, [clearTimers]);

  const total = summary ? summary.files + summary.clipboard + summary.devices : 0;
  const nothingToDelete = summary !== null && total === 0;

  return (
    <>
      <PageHeader
        icon={Trash2}
        title="Réinitialiser le PC"
        subtitle="Efface tout ce que les téléphones ont laissé sur cet ordinateur : fichiers reçus, transferts, presse-papier et appairages."
      />

      {loadError && <ErrorBanner message={loadError} base={LARAVEL_BASE} />}
      {actionError && <ErrorBanner message={actionError} />}

      {phase === 'done' && (
        <motion.div
          initial={{ opacity: 0, y: -6 }}
          animate={{ opacity: 1, y: 0 }}
          className="mb-4 flex items-center gap-3 rounded-xl border border-emerald-200 bg-emerald-50 p-3.5 text-sm text-emerald-700"
        >
          <Check className="size-4.5 shrink-0" />
          <p className="font-medium">Tout a été supprimé. Le PC est reparti de zéro.</p>
        </motion.div>
      )}

      {!loadedOnce && !loadError ? (
        <Skeleton className="h-56 w-full rounded-2xl" />
      ) : summary ? (
        <Card className="overflow-hidden">
          <div className="flex items-start gap-3.5 border-b border-zinc-100 bg-red-50/40 p-5">
            <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-red-100 text-red-600">
              <TriangleAlert className="size-5" />
            </span>
            <div>
              <h2 className="font-semibold text-zinc-900">Zone de danger</h2>
              <p className="mt-0.5 text-sm text-zinc-500">
                Cette action est <strong>irréversible</strong>. Les téléphones déjà
                appairés devront re-scanner le QR pour se reconnecter.
              </p>
            </div>
          </div>

          <div className="divide-y divide-zinc-100">
            <StatRow
              icon={Inbox}
              label="Fichiers reçus"
              value={`${summary.files} fichier${summary.files > 1 ? 's' : ''}`}
              hint={summary.bytes > 0 ? formatBytes(summary.bytes) : undefined}
            />
            <StatRow
              icon={ClipboardList}
              label="Presse-papier"
              value={`${summary.clipboard} entrée${summary.clipboard > 1 ? 's' : ''}`}
            />
            <StatRow
              icon={Smartphone}
              label="Téléphones appairés"
              value={`${summary.devices} appareil${summary.devices > 1 ? 's' : ''}`}
            />
          </div>

          <div className="flex items-center justify-between gap-4 border-t border-zinc-100 p-5">
            <p className="text-sm text-zinc-500">
              {nothingToDelete
                ? 'Rien à supprimer pour l’instant.'
                : 'Tu pourras encore annuler pendant 5 secondes.'}
            </p>
            <Button
              variant="destructive"
              onClick={() => setConfirmOpen(true)}
              disabled={nothingToDelete || phase === 'pending' || phase === 'deleting'}
            >
              <Trash2 /> Tout supprimer
            </Button>
          </div>
        </Card>
      ) : null}

      {/* Garde-fou 1 — modale de confirmation détaillée. */}
      <AnimatePresence>
        {confirmOpen && summary && (
          <motion.div
            className="fixed inset-0 z-50 flex items-center justify-center bg-zinc-900/40 p-4 backdrop-blur-sm"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setConfirmOpen(false)}
          >
            <motion.div
              className="w-full max-w-md rounded-2xl border border-zinc-100 bg-white p-6 shadow-card"
              initial={{ opacity: 0, scale: 0.96, y: 8 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.96, y: 8 }}
              onClick={(e) => e.stopPropagation()}
            >
              <span className="grid size-11 place-items-center rounded-2xl bg-red-100 text-red-600">
                <TriangleAlert className="size-5.5" />
              </span>
              <h2 className="mt-4 text-lg font-bold text-zinc-900">Tout supprimer ?</h2>
              <p className="mt-1 text-sm text-zinc-500">
                Vont être effacés définitivement de ce PC :
              </p>
              <ul className="mt-3 space-y-1.5 text-sm text-zinc-700">
                <li className="flex items-center gap-2">
                  <Inbox className="size-4 text-zinc-400" />
                  {summary.files} fichier{summary.files > 1 ? 's' : ''} reçu
                  {summary.files > 1 ? 's' : ''}
                  {summary.bytes > 0 && (
                    <span className="text-zinc-400">({formatBytes(summary.bytes)})</span>
                  )}
                </li>
                <li className="flex items-center gap-2">
                  <ClipboardList className="size-4 text-zinc-400" />
                  {summary.clipboard} entrée{summary.clipboard > 1 ? 's' : ''} de
                  presse-papier
                </li>
                <li className="flex items-center gap-2">
                  <Smartphone className="size-4 text-zinc-400" />
                  {summary.devices} téléphone{summary.devices > 1 ? 's' : ''} appairé
                  {summary.devices > 1 ? 's' : ''}
                </li>
              </ul>
              <div className="mt-6 flex justify-end gap-2">
                <Button variant="outline" onClick={() => setConfirmOpen(false)}>
                  Annuler
                </Button>
                <Button variant="destructive" onClick={armCountdown}>
                  <Trash2 /> Oui, tout supprimer
                </Button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Garde-fou 2 — rebours de 5 s annulable avant l'appel serveur. */}
      <AnimatePresence>
        {(phase === 'pending' || phase === 'deleting') && (
          <motion.div
            className="fixed inset-x-0 bottom-0 z-50 flex justify-center p-4"
            initial={{ opacity: 0, y: 24 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 24 }}
          >
            <div className="w-full max-w-md overflow-hidden rounded-2xl border border-zinc-100 bg-white shadow-card">
              <div className="flex items-center gap-3 p-4">
                <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-red-100 text-red-600">
                  {phase === 'deleting' ? (
                    <Loader2 className="size-5 animate-spin" />
                  ) : (
                    <Trash2 className="size-5" />
                  )}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-semibold text-zinc-900">
                    {phase === 'deleting'
                      ? 'Suppression en cours…'
                      : `Suppression dans ${remaining} s`}
                  </p>
                  <p className="truncate text-xs text-zinc-500">
                    {phase === 'deleting'
                      ? 'Effacement des fichiers et des données…'
                      : 'Clique sur Annuler pour tout garder.'}
                  </p>
                </div>
                {phase === 'pending' && (
                  <Button variant="outline" size="sm" onClick={cancel}>
                    <Undo2 /> Annuler
                  </Button>
                )}
              </div>
              {phase === 'pending' && (
                <motion.div
                  className="h-1 bg-red-500"
                  initial={{ width: '100%' }}
                  animate={{ width: '0%' }}
                  transition={{ duration: UNDO_SECONDS, ease: 'linear' }}
                />
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}

function StatRow({
  icon: Icon,
  label,
  value,
  hint,
}: {
  icon: typeof Inbox;
  label: string;
  value: string;
  hint?: string;
}) {
  return (
    <div className="flex items-center gap-3 px-5 py-3.5">
      <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-zinc-100 text-zinc-500">
        <Icon className="size-4.5" />
      </span>
      <span className="flex-1 text-sm font-medium text-zinc-700">{label}</span>
      <span className="text-sm font-semibold text-zinc-900">{value}</span>
      {hint && <span className="text-xs text-zinc-400">{hint}</span>}
    </div>
  );
}
