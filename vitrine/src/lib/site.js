// Configuration centrale de la vitrine.
// Les fichiers d'installation sont servis EN DIRECT depuis le VPS
// sahelstack.tech (Apache, Content-Disposition: attachment) → un seul clic,
// aucun détour par GitHub. Voir vitrine/public/downloads/README.md pour
// l'upload (rsync) et la config Apache.

export const SITE = {
  name: "Linkup",
  tagline: "Ton téléphone et ton PC, reliés en un scan",

  // Téléchargements directs (servis par le VPS, hors Vercel).
  // ⚠️ Tailles indicatives — à rafraîchir à chaque release (`du -h dist/*` après
  //    build, cf. README downloads) car elles dérivent à chaque rebuild.
  androidApk: "https://linkup.sahelstack.tech/dl/linkup.apk",
  androidSize: "29 Mo",
  // Variante 32-bit (armeabi-v7a) pour les téléphones ANCIENS où l'APK principal
  // (64-bit) refuse de s'installer (« application non installée »).
  androidApk32: "https://linkup.sahelstack.tech/dl/linkup-32bit.apk",
  androidSize32: "25 Mo",
  // PC : AppImage universelle (aucune installation, toutes distros) — primaire.
  pcBundle: "https://linkup.sahelstack.tech/dl/linkup.AppImage",
  pcSize: "157 Mo",
  // Option Debian/Ubuntu/Mint via gestionnaire de paquets.
  pcDeb: "https://linkup.sahelstack.tech/dl/linkup-pc.deb",
  pcDebSize: "148 Mo",

  repo: "https://github.com/Mahamane-Korobara/LinkUp",
};
