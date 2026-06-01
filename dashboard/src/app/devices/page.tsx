'use client';

import { useCallback, useState } from 'react';

import { DASHBOARD_HEADERS, LARAVEL_BASE, formatDate } from '../../lib/api';
import { usePolling } from '../../hooks/usePolling';

/**
 * Page S2.J4 (T2.17) — approbation des téléphones appairés.
 *
 * Flow :
 * 1. Poll /api/pairing/devices toutes les 2s
 * 2. Affiche chaque device avec son empreinte SHA-256 (à comparer avec celle
 *    montrée sur le tel) + son statut
 * 3. Boutons Approuver / Refuser → POST sur l'endpoint correspondant
 *
 * Le tel, lui, poll /api/pairing/poll pour récupérer son token une fois
 * approuvé (S2.J5 côté Flutter).
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
  const res = await fetch(`${LARAVEL_BASE}/api/pairing/devices`, {
    headers: DASHBOARD_HEADERS,
    cache: 'no-store',
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  return (data.devices ?? []) as DeviceDto[];
}

const STATUS_META: Record<DeviceStatus, { label: string; className: string }> = {
  pending: { label: 'En attente', className: 'bg-amber-100 text-amber-800' },
  approved: { label: 'Approuvé', className: 'bg-green-100 text-green-800' },
  rejected: { label: 'Refusé', className: 'bg-red-100 text-red-700' },
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
        const res = await fetch(
          `${LARAVEL_BASE}/api/pairing/devices/${deviceId}/${action}`,
          { method: 'POST', headers: DASHBOARD_HEADERS },
        );
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
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
      if (input === null) return; // annulé
      const name = input.trim();
      if (name === '') return;
      setBusyId(deviceId);
      try {
        const res = await fetch(
          `${LARAVEL_BASE}/api/pairing/devices/${deviceId}/rename`,
          {
            method: 'POST',
            headers: { ...DASHBOARD_HEADERS, 'Content-Type': 'application/json' },
            body: JSON.stringify({ name }),
          },
        );
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
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
    <main className="min-h-screen bg-slate-50 p-8">
      <div className="max-w-2xl mx-auto">
        <h1 className="text-2xl font-bold mb-1">Téléphones appairés</h1>
        <p className="text-slate-600 text-sm mb-6">
          Vérifie que l&apos;empreinte affichée ici correspond à celle de ton
          téléphone avant d&apos;approuver.
        </p>

        {shownError && (
          <div className="bg-red-50 border border-red-200 rounded p-3 text-red-700 text-sm mb-4">
            {shownError} — Laravel doit tourner sur <code>{LARAVEL_BASE}</code>.
          </div>
        )}

        {loadedOnce && devices.length === 0 && !error && (
          <div className="bg-white rounded-xl border border-slate-200 p-8 text-center text-slate-500">
            Aucun téléphone pour l&apos;instant. Va sur{' '}
            <a href="/pair" className="text-indigo-600 underline">
              /pair
            </a>{' '}
            pour afficher le QR.
          </div>
        )}

        {pending.length > 0 && (
          <section className="mb-8">
            <h2 className="text-sm font-semibold text-slate-500 uppercase tracking-wide mb-3">
              En attente d&apos;approbation
            </h2>
            <div className="space-y-3">
              {pending.map((d) => (
                <DeviceCard
                  key={d.device_id}
                  device={d}
                  busy={busyId === d.device_id}
                  onApprove={() => act(d.device_id, 'approve')}
                  onReject={() => act(d.device_id, 'reject')}
                />
              ))}
            </div>
          </section>
        )}

        {others.length > 0 && (
          <section>
            <h2 className="text-sm font-semibold text-slate-500 uppercase tracking-wide mb-3">
              Historique
            </h2>
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
      </div>
    </main>
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
    <div className="bg-white rounded-xl border border-slate-200 p-4 flex items-center justify-between gap-4">
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-medium truncate">
            {device.name ?? 'Téléphone'}
          </span>
          <span className={`text-xs px-2 py-0.5 rounded-full ${meta.className}`}>
            {meta.label}
          </span>
        </div>

        {device.model && (
          <div className="text-sm text-slate-600 mt-0.5 truncate">
            📱 {device.model}
          </div>
        )}
        {osLine && (
          <div className="text-xs text-slate-500 mt-0.5">{osLine}</div>
        )}

        <div className="text-sm text-slate-500 mt-1">
          Empreinte&nbsp;:{' '}
          <code className="font-mono font-semibold text-slate-800 tracking-widest">
            {device.fingerprint}
          </code>
        </div>

        {(pairedAt || approvedAt) && (
          <div className="text-xs text-slate-400 mt-1 space-x-3">
            {pairedAt && <span>Appairé&nbsp;: {pairedAt}</span>}
            {approvedAt && <span>Approuvé&nbsp;: {approvedAt}</span>}
          </div>
        )}
      </div>

      {device.status === 'pending' && onApprove && onReject && (
        <div className="flex gap-2 shrink-0">
          <button
            onClick={onReject}
            disabled={busy}
            className="px-3 py-2 text-sm rounded-lg border border-slate-300 text-slate-700 hover:bg-slate-50 disabled:opacity-50"
          >
            Refuser
          </button>
          <button
            onClick={onApprove}
            disabled={busy}
            className="px-3 py-2 text-sm rounded-lg bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50"
          >
            {busy ? '…' : 'Approuver'}
          </button>
        </div>
      )}

      {device.status !== 'pending' && (onRename || onRevoke) && (
        <div className="flex gap-2 shrink-0">
          {onRename && (
            <button
              onClick={onRename}
              disabled={busy}
              className="px-3 py-2 text-sm rounded-lg border border-slate-300 text-slate-700 hover:bg-slate-50 disabled:opacity-50"
            >
              Renommer
            </button>
          )}
          {onRevoke && (
            <button
              onClick={onRevoke}
              disabled={busy}
              className="px-3 py-2 text-sm rounded-lg border border-red-300 text-red-700 hover:bg-red-50 disabled:opacity-50"
            >
              {busy ? '…' : 'Révoquer'}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
