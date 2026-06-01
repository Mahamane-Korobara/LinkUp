'use client';

import { useEffect, useState } from 'react';

export type PollingState<T> = {
  data: T;
  error: string | null;
  /** false tant que le premier tick n'a pas abouti (succès OU échec). */
  loadedOnce: boolean;
  /** Permet une mise à jour optimiste/manuelle (ex. après une action). */
  setData: (value: T) => void;
};

/**
 * Poll [fetcher] immédiatement puis toutes les [intervalMs] ms.
 *
 * `setState` n'est appelé qu'APRÈS l'`await` (jamais de façon synchrone dans
 * l'effet → règle react-hooks/set-state-in-effect respectée). [fetcher] doit
 * être une référence STABLE (fonction module-level), sinon le polling se
 * relance à chaque rendu.
 */
export function usePolling<T>(
  fetcher: () => Promise<T>,
  intervalMs: number,
  initial: T,
): PollingState<T> {
  const [data, setData] = useState<T>(initial);
  const [error, setError] = useState<string | null>(null);
  const [loadedOnce, setLoadedOnce] = useState(false);

  useEffect(() => {
    let active = true;
    const tick = async () => {
      try {
        const next = await fetcher();
        if (!active) return;
        setData(next);
        setError(null);
      } catch (e) {
        if (active) setError(e instanceof Error ? e.message : String(e));
      } finally {
        if (active) setLoadedOnce(true);
      }
    };
    tick();
    const id = setInterval(tick, intervalMs);
    return () => {
      active = false;
      clearInterval(id);
    };
  }, [fetcher, intervalMs]);

  return { data, error, loadedOnce, setData };
}
