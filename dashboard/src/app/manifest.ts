import type { MetadataRoute } from 'next';

// Manifest PWA généré en statique (compatible `output: 'export'`). Permet
// d'« installer » le dashboard comme une app (sur le PC en localhost, contexte
// sécurisé ; depuis un tél en http://<ip>:8000 l'install n'est PAS proposée car
// les navigateurs exigent HTTPS/localhost — le dashboard reste utilisable en web).
export const dynamic = 'force-static';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Linkup — Tableau de bord',
    short_name: 'Linkup',
    description: 'Appairage et gestion des téléphones Linkup connectés à ce PC.',
    start_url: '/devices',
    scope: '/',
    display: 'standalone',
    background_color: '#ffffff',
    theme_color: '#7c3aed',
    lang: 'fr',
    icons: [
      { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
      { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
      {
        src: '/icons/icon-maskable-512.png',
        sizes: '512x512',
        type: 'image/png',
        purpose: 'maskable',
      },
    ],
  };
}
