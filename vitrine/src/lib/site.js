// Configuration centrale de la vitrine.
// Les fichiers d'installation sont servis EN DIRECT depuis le VPS
// sahelstack.tech (Apache, Content-Disposition: attachment) → un seul clic,
// aucun détour par GitHub. Voir vitrine/public/downloads/README.md pour
// l'upload (rsync) et la config Apache.

export const SITE = {
  name: "Linkup",
  tagline: "Ton téléphone et ton PC, reliés en un scan",

  // Téléchargements directs (servis par le VPS, hors Vercel)
  androidApk: "https://linkup.sahelstack.tech/dl/linkup.apk",
  androidSize: "65 Mo",
  // PC : AppImage universelle (aucune installation, toutes distros) — primaire.
  pcBundle: "https://linkup.sahelstack.tech/dl/linkup.AppImage",
  pcSize: "141 Mo",
  // Option Debian/Ubuntu/Mint via gestionnaire de paquets.
  pcDeb: "https://linkup.sahelstack.tech/dl/linkup-pc.deb",
  pcDebSize: "138 Mo",

  repo: "https://github.com/Mahamane-Korobara/LinkUp",
};
