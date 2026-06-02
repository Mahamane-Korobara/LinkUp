import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Export 100% statique (dossier `out/`) : le dashboard est pré-rendu en
  // HTML/JS et servi par l'agent — AUCUN runtime Node sur la machine cible
  // (stratégie « bundler les runtimes », cf. packaging). Pages toutes en
  // `'use client'` + fetch vers Laravel → exportables. `images.unoptimized`
  // car l'optimiseur d'images exige un serveur Node.
  output: "export",
  images: { unoptimized: true },
};

export default nextConfig;
