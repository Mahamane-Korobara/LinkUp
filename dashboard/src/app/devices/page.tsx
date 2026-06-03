'use client';

import { useCallback, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Smartphone,
  Check,
  X,
  Pencil,
  ShieldOff,
  Fingerprint,
  Clock,
  ShieldCheck,
} from 'lucide-react';

import { LARAVEL_BASE, apiFetch, formatDate } from '@/lib/api';
import { usePolling } from '@/hooks/usePolling';
import { PageHeader } from '@/components/PageHeader';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { ErrorBanner, EmptyState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';

/**
 * Page S2.J4 (T2.17) — approbation des téléphones appairés.
 * Logique inchangée : poll /api/pairing/devices, approve/reject/rename.
 */

const POLL_INTERVAL_MS = 2000;

type DeviceStatus = 'pending' | 'approved' | 'rejected';

type DeviceDto = {
  device_id: string;
  name: string | null;
  model: string | null;
  platform: string | null;
  os_version: string | null;
  fingerprint: string;
  status: DeviceStatus;
  paired_at: string | null;
  approved_at: string | null;
};

async function loadDevices(): Promise<DeviceDto[]> {
  const data = await (await apiFetch('/api/pairing/devices')).json();
  return (data.devices ?? []) as DeviceDto[];
}

const STATUS_META: Record<DeviceStatus, { label: string; tone: 'amber' | 'green' | 'red' }> = {
  pending: { label: 'En attente', tone: 'amber' },
  approved: { label: 'Approuvé', tone: 'green' },
  rejected: { label: 'Refusé', tone: 'red' },
};

export default function DevicesPage() {
  const { data: devices, error, loadedOnce, setData } = usePolling<DeviceDto[]>(
    loadDevices,
    POLL_INTERVAL_MS,
    [],
  );
  const [busyId, setBusyId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const act = useCallback(
    async (deviceId: string, action: 'approve' | 'reject') => {
      setBusyId(deviceId);
      try {
        await apiFetch(`/api/pairing/devices/${deviceId}/${action}`, { method: 'POST' });
        setData(await loadDevices());
        setActionError(null);
      } catch (e) {
        setActionError(e instanceof Error ? e.message : String(e));
      } finally {
        setBusyId(null);
      }
    },
    [setData],
  );

  const rename = useCallback(
    async (deviceId: string, current: string | null) => {
      const input = window.prompt('Nouveau nom du téléphone', current ?? '');
      if (input === null) return;
      const name = input.trim();
      if (name === '') return;
      setBusyId(deviceId);
      try {
        await apiFetch(`/api/pairing/devices/${deviceId}/rename`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ name }),
        });
        setData(await loadDevices());
        setActionError(null);
      } catch (e) {
        setActionError(e instanceof Error ? e.message : String(e));
      } finally {
        setBusyId(null);
      }
    },
    [setData],
  );

  const shownError = actionError ?? error;
  const pending = devices.filter((d) => d.status === 'pending');
  const others = devices.filter((d) => d.status !== 'pending');

  return (
    <>
      <PageHeader
        icon={Smartphone}
        title="Téléphones appairés"
        subtitle="Vérifie que l’empreinte affichée ici correspond à celle de ton téléphone avant d’approuver."
      />

      {shownError && <ErrorBanner message={shownError} base={LARAVEL_BASE} />}

      {!loadedOnce && !error && (
        <div className="space-y-3">
          {[0, 1].map((i) => (
            <Skeleton key={i} className="h-24 w-full rounded-2xl" />
          ))}
        </div>
      )}

      {loadedOnce && devices.length === 0 && !error && (
        <EmptyState icon={Smartphone}>
          Aucun téléphone pour l’instant. Va sur{' '}
          <a href="/pair" className="font-semibold text-violet-600 underline">
            Appairer
          </a>{' '}
          pour afficher le QR code.
        </EmptyState>
      )}

      {pending.length > 0 && (
        <section className="mb-8">
          <SectionTitle icon={Clock}>En attente d’approbation</SectionTitle>
          <div className="space-y-3">
            <AnimatePresence initial={false}>
              {pending.map((d) => (
                <DeviceCard
                  key={d.device_id}
                  device={d}
                  busy={busyId === d.device_id}
                  onApprove={() => act(d.device_id, 'approve')}
                  onReject={() => act(d.device_id, 'reject')}
                />
              ))}
            </AnimatePresence>
          </div>
        </section>
      )}

      {others.length > 0 && (
        <section>
          <SectionTitle icon={ShieldCheck}>Historique</SectionTitle>
          <div className="space-y-3">
            {others.map((d) => (
              <DeviceCard
                key={d.device_id}
                device={d}
                busy={busyId === d.device_id}
                onRename={() => rename(d.device_id, d.name)}
                onRevoke={
                  d.status === 'approved'
                    ? () => act(d.device_id, 'reject')
                    : undefined
                }
              />
            ))}
          </div>
        </section>
      )}
    </>
  );
}

function SectionTitle({ icon: Icon, children }: { icon: typeof Clock; children: React.ReactNode }) {
  return (
    <h2 className="mb-3 flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-zinc-400">
      <Icon className="size-3.5" />
      {children}
    </h2>
  );
}

function DeviceCard({
  device,
  busy,
  onApprove,
  onReject,
  onRename,
  onRevoke,
}: {
  device: DeviceDto;
  busy: boolean;
  onApprove?: () => void;
  onReject?: () => void;
  onRename?: () => void;
  onRevoke?: () => void;
}) {
  const meta = STATUS_META[device.status];
  const pairedAt = formatDate(device.paired_at, { year: true });
  const approvedAt = formatDate(device.approved_at, { year: true });
  const osLine = [device.platform, device.os_version].filter(Boolean).join(' • ');

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, scale: 0.98 }}
      transition={{ duration: 0.3 }}
    >
      <Card className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between sm:gap-4">
        <div className="flex min-w-0 items-start gap-3">
          <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-zinc-100 text-zinc-500">
            <Smartphone className="size-5" />
          </span>
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span className="truncate font-semibold text-zinc-900">
                {device.name ?? 'Téléphone'}
              </span>
              <Badge tone={meta.tone}>{meta.label}</Badge>
            </div>

            {device.model && (
              <div className="mt-0.5 truncate text-sm text-zinc-600">{device.model}</div>
            )}
            {osLine && <div className="mt-0.5 text-xs text-zinc-400">{osLine}</div>}

            <div className="mt-1.5 flex items-center gap-1.5 text-sm text-zinc-500">
              <Fingerprint className="size-3.5 text-zinc-400" />
              <code className="font-mono font-semibold tracking-widest text-zinc-800">
                {device.fingerprint}
              </code>
            </div>

            {(pairedAt || approvedAt) && (
              <div className="mt-1 flex flex-wrap gap-x-3 text-xs text-zinc-400">
                {pairedAt && <span>Appairé : {pairedAt}</span>}
                {approvedAt && <span>Approuvé : {approvedAt}</span>}
              </div>
            )}
          </div>
        </div>

        {device.status === 'pending' && onApprove && onReject && (
          <div className="flex shrink-0 gap-2">
            <Button variant="outline" size="sm" onClick={onReject} disabled={busy}>
              <X /> Refuser
            </Button>
            <Button size="sm" onClick={onApprove} disabled={busy}>
              <Check /> {busy ? '…' : 'Approuver'}
            </Button>
          </div>
        )}

        {device.status !== 'pending' && (onRename || onRevoke) && (
          <div className="flex shrink-0 gap-2">
            {onRename && (
              <Button variant="outline" size="sm" onClick={onRename} disabled={busy}>
                <Pencil /> Renommer
              </Button>
            )}
            {onRevoke && (
              <Button variant="destructive" size="sm" onClick={onRevoke} disabled={busy}>
                <ShieldOff /> {busy ? '…' : 'Révoquer'}
              </Button>
            )}
          </div>
        )}
      </Card>
    </motion.div>
  );
}
