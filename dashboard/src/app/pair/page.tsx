'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { motion } from 'framer-motion';
import { QrCode, Timer, RefreshCw, ChevronDown } from 'lucide-react';

import { LARAVEL_BASE } from '@/lib/api';
import { PageHeader } from '@/components/PageHeader';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ErrorBanner } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';

/**
 * Page S2.J2 T2.8 — affiche le QR de pairing du PC.
 * Logique inchangée : fetch /api/pairing/qr, countdown TTL + auto-refresh,
 * détection d'un scan (nouveau pending) → redirection /devices.
 */

type PairingPayload = {
  url: string;
  otp: string;
  expires_at: string;
  ttl_seconds: number;
};

async function fetchQrPayload(): Promise<PairingPayload> {
  const res = await fetch(`${LARAVEL_BASE}/api/pairing/qr`, {
    headers: { Accept: 'application/json' },
    cache: 'no-store',
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return (await res.json()) as PairingPayload;
}

export default function PairPage() {
  const router = useRouter();
  const [payload, setPayload] = useState<PairingPayload | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [remaining, setRemaining] = useState(0);
  const [qrTimestamp, setQrTimestamp] = useState<number>(() => Date.now());

  const fetchPairing = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await fetchQrPayload();
      setPayload(data);
      setRemaining(data.ttl_seconds);
      setQrTimestamp(Date.now());
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const data = await fetchQrPayload();
        if (!active) return;
        setPayload(data);
        setRemaining(data.ttl_seconds);
        setQrTimestamp(Date.now());
        setError(null);
        setLoading(false);
      } catch (e) {
        if (!active) return;
        setError(e instanceof Error ? e.message : String(e));
        setLoading(false);
      }
    })();
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (remaining <= 0) return;
    const interval = setInterval(() => {
      setRemaining((r) => {
        if (r <= 1) {
          fetchPairing();
          return 0;
        }
        return r - 1;
      });
    }, 1000);
    return () => clearInterval(interval);
  }, [remaining, fetchPairing]);

  const baselinePendingIds = useRef<Set<string> | null>(null);
  useEffect(() => {
    let cancelled = false;
    const poll = async () => {
      try {
        const res = await fetch(`${LARAVEL_BASE}/api/pairing/devices`, {
          headers: { Accept: 'application/json', 'X-Linkup-Client': 'dashboard' },
          cache: 'no-store',
        });
        if (!res.ok) return;
        const data = await res.json();
        const pendingIds: string[] = (data.devices ?? [])
          .filter((d: { status: string }) => d.status === 'pending')
          .map((d: { device_id: string }) => d.device_id);

        if (baselinePendingIds.current === null) {
          baselinePendingIds.current = new Set(pendingIds);
          return;
        }
        const fresh = pendingIds.some((id) => !baselinePendingIds.current!.has(id));
        if (fresh && !cancelled) router.push('/devices');
      } catch {
        // réseau indisponible : on retentera au prochain tick
      }
    };
    poll();
    const id = setInterval(poll, 2000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [router]);

  return (
    <>
      <PageHeader
        icon={QrCode}
        title="Appairer un téléphone"
        subtitle="Scanne ce QR code avec l’app Linkup sur ton téléphone Android."
      />

      {error && <ErrorBanner message={error} base={LARAVEL_BASE} />}

      <Card className="mx-auto max-w-md overflow-hidden">
        {loading && !payload && !error && (
          <div className="flex flex-col items-center gap-4 p-8">
            <Skeleton className="size-72 rounded-2xl" />
            <Skeleton className="h-8 w-44 rounded-full" />
          </div>
        )}

        {error && (
          <div className="p-6">
            <Button onClick={fetchPairing} className="w-full">
              <RefreshCw /> Réessayer
            </Button>
          </div>
        )}

        {payload && !error && (
          <div className="flex flex-col items-center p-6 sm:p-8">
            <motion.div
              initial={{ opacity: 0, scale: 0.96 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ duration: 0.4 }}
              className="rounded-2xl border border-zinc-100 bg-white p-3 shadow-card"
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                key={qrTimestamp}
                src={`${LARAVEL_BASE}/api/pairing/qr.png?ts=${qrTimestamp}`}
                alt="QR code de pairing"
                width={288}
                height={288}
                className="rounded-lg"
              />
            </motion.div>

            <div className="mt-5 inline-flex items-center gap-2 rounded-full bg-violet-50 px-4 py-2 text-sm text-violet-700">
              <Timer className="size-4" />
              <span className="font-mono font-bold tabular-nums">{remaining}s</span>
              <span className="text-violet-500">avant un nouveau code</span>
            </div>

            <details className="mt-6 w-full text-xs text-zinc-500">
              <summary className="flex cursor-pointer list-none items-center gap-1.5 font-medium">
                <ChevronDown className="size-3.5" />
                URL technique
              </summary>
              <p className="mt-2 break-all rounded-lg bg-zinc-50 p-2 font-mono">
                {payload.url}
              </p>
            </details>
          </div>
        )}
      </Card>
    </>
  );
}
