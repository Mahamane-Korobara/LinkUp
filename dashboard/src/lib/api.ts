/**
 * Constantes & helpers partagés par les pages du dashboard Linkup.
 *
 * Centralisé ici pour éviter la duplication entre /devices, /files et /pair
 * (base API, header anti-CSRF, formatage date/octets).
 */

/** Base de l'API Laravel de l'agent local. */
export const LARAVEL_BASE =
  process.env.NEXT_PUBLIC_LARAVEL_URL ?? 'http://localhost:8000';

/**
 * Header exigé par l'agent sur les routes de gestion (anti-CSRF, cf.
 * RequireDashboardClient côté Laravel). Couplé au CORS restreint, il bloque
 * les requêtes cross-site (un site tiers ne peut pas l'émettre sans preflight).
 */
export const DASHBOARD_HEADERS = {
  Accept: 'application/json',
  'X-Linkup-Client': 'dashboard',
} as const;

/**
 * Date ISO → « jj/mm hh:mm » (fr-FR). Chaîne vide si absente/invalide.
 * Passe `{ year: true }` pour inclure l'année (« jj/mm/aaaa hh:mm »).
 */
export function formatDate(iso: string | null, opts: { year?: boolean } = {}): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString('fr-FR', {
    day: '2-digit',
    month: '2-digit',
    ...(opts.year ? { year: 'numeric' as const } : {}),
    hour: '2-digit',
    minute: '2-digit',
  });
}

/** Octets → « 12 Ko / 3.4 Mo / 1.2 Go ». */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} o`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} Ko`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} Mo`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} Go`;
}
