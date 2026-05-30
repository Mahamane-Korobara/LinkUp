'use client';

import { useCallback, useEffect, useState } from 'react';

/**
 * Page S2.J2 T2.8 — affiche le QR de pairing du PC.
 *
 * Flow :
 * 1. Fetch /api/pairing/qr → reçoit {url, otp, expires_at, ttl_seconds}
 * 2. Affiche le PNG /api/pairing/qr.png?ts=<timestamp> (force le refresh image)
 * 3. Countdown TTL côté client + auto-refresh à expiration
 *
 * Une fois le tel scanné le QR, S2.J4 va ajouter le popup d'approbation
 * via Reverb event `PairingPendingApproval`.
 */

const LARAVEL_BASE = process.env.NEXT_PUBLIC_LARAVEL_URL ?? 'http://localhost:8000';

type PairingPayload = {
  url: string;
  otp: string;
  expires_at: string;
  ttl_seconds: number;
};

export default function PairPage() {
  const [payload, setPayload] = useState<PairingPayload | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [remaining, setRemaining] = useState(0);
  const [qrTimestamp, setQrTimestamp] = useState<number>(() => Date.now());

  const fetchPairing = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`${LARAVEL_BASE}/api/pairing/qr`, {
        headers: { Accept: 'application/json' },
        cache: 'no-store',
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data: PairingPayload = await res.json();
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
    fetchPairing();
  }, [fetchPairing]);

  // Countdown + auto-refresh à expiration
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

  return (
    <main className="min-h-screen flex items-center justify-center bg-slate-50 p-8">
      <div className="bg-white rounded-2xl shadow-lg p-8 max-w-md w-full">
        <h1 className="text-2xl font-bold text-center mb-2">Appairer un téléphone</h1>
        <p className="text-center text-slate-600 text-sm mb-6">
          Scanne ce QR avec l&apos;app Linkup sur ton téléphone Android.
        </p>

        {loading && !payload && (
          <div className="flex items-center justify-center h-64">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-deepPurple-600" />
          </div>
        )}

        {error && (
          <div className="bg-red-50 border border-red-200 rounded p-4 text-red-700 text-sm">
            <p className="font-semibold mb-1">Erreur de chargement</p>
            <p>{error}</p>
            <p className="text-xs mt-2 text-red-500">
              Laravel doit tourner sur <code>{LARAVEL_BASE}</code>.
            </p>
            <button
              onClick={fetchPairing}
              className="mt-3 px-4 py-2 bg-red-600 text-white rounded text-sm hover:bg-red-700"
            >
              Réessayer
            </button>
          </div>
        )}

        {payload && !error && (
          <>
            <div className="flex justify-center mb-4">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={`${LARAVEL_BASE}/api/pairing/qr.png?ts=${qrTimestamp}`}
                alt="QR code de pairing"
                width={320}
                height={320}
                className="border border-slate-200 rounded-lg"
              />
            </div>

            <div className="text-center">
              <div className="inline-flex items-center gap-2 px-4 py-2 bg-slate-100 rounded-full text-sm">
                <span className="font-mono font-semibold">
                  {remaining}s
                </span>
                <span className="text-slate-500">avant nouveau code</span>
              </div>
            </div>

            <details className="mt-6 text-xs text-slate-500">
              <summary className="cursor-pointer">URL technique</summary>
              <p className="break-all font-mono mt-2 bg-slate-50 p-2 rounded">
                {payload.url}
              </p>
            </details>
          </>
        )}
      </div>
    </main>
  );
}
