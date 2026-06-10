/**
 * Constantes & helpers partagés par les pages du dashboard Linkup.
 *
 * Centralisé ici pour éviter la duplication entre /devices, /files et /pair
 * (base API, header anti-CSRF, formatage date/octets).
 */

/**
 * Base de l'API Laravel de l'agent local.
 *
 * Dans le bundle PC, le dashboard ET l'API sont servis par FrankenPHP sur la
 * MÊME origine (port quelconque, ex. 8770) : on utilise alors des URLs RELATIVES
 * (`''`) pour ne dépendre d'aucun port codé en dur. En dev, le dashboard tourne
 * sur :3000 et l'API sur :8000 → base absolue.
 */
export const LARAVEL_BASE =
  process.env.NEXT_PUBLIC_LINKUP_SAME_ORIGIN === '1'
    ? ''
    : (process.env.NEXT_PUBLIC_LARAVEL_URL ?? 'http://localhost:8000');

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
 * Appel à l'API de l'agent local, centralisé : préfixe la base, injecte le
 * header anti-CSRF, force `no-store` et lève sur statut non-2xx. Évite de
 * répéter ce boilerplate dans chaque page (cf. audit DRY).
 */
export async function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const res = await fetch(`${LARAVEL_BASE}${path}`, {
    cache: 'no-store',
    ...init,
    headers: { ...DASHBOARD_HEADERS, ...init.headers },
  });
  if (!res.ok) {
    let message = `HTTP ${res.status}`;
    try {
      message = (await res.clone().json()).message ?? message;
    } catch {
      /* corps non-JSON : on garde le code HTTP */
    }
    throw new Error(message);
  }
  return res;
}

/** Catégorie de média d'un fichier reçu (rangement bridge → onglets dashboard). */
export type FileCategory = 'photos' | 'video' | 'fichiers';

/**
 * URL d'aperçu (octets bruts) d'un fichier reçu, servie INLINE par l'agent.
 * Utilisable directement comme `src` d'une balise <img>/<video> (la route est
 * hors `dashboard.client`, car ces balises n'émettent pas le header custom).
 */
export function fileRawUrl(transferId: string): string {
  return `${LARAVEL_BASE}/api/files/${transferId}/raw`;
}

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

/** Statut d'un téléphone côté agent. */
export type DeviceStatus = 'pending' | 'approved' | 'rejected';

/** Représentation d'un téléphone telle qu'exposée par `/api/pairing/devices`. */
export type DeviceDto = {
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

/**
 * Liste des téléphones connus de l'agent. Centralisé ici (utilisé par /devices,
 * /send et /pair) pour ne plus dupliquer l'appel + le type dans chaque page.
 */
export async function loadDevices(): Promise<DeviceDto[]> {
  const data = await (await apiFetch('/api/pairing/devices')).json();
  return (data.devices ?? []) as DeviceDto[];
}
