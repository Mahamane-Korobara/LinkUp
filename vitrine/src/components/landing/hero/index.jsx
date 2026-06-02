"use client";
import { motion } from "framer-motion";
import { Download, PlayCircle, ShieldCheck, WifiOff, UserX } from "lucide-react";
import { SITE } from "@/lib/site";
import ConnectVisual from "./ConnectVisual";

const TRUST = [
  { icon: WifiOff, label: "Sans câble" },
  { icon: UserX, label: "Sans compte" },
  { icon: ShieldCheck, label: "Sans cloud" },
];

export default function HeroSection() {
  return (
    <section className="relative overflow-hidden pt-28 pb-16 sm:pt-32 sm:pb-24">
      <div className="bg-grid pointer-events-none absolute inset-0" />
      <div className="pointer-events-none absolute -top-32 left-1/2 -z-0 h-[420px] w-[820px] -translate-x-1/2 rounded-full grad-soft blur-3xl" />

      <div className="relative mx-auto grid max-w-6xl items-center gap-12 px-5 lg:grid-cols-[1.05fr_0.95fr]">
        {/* Colonne texte */}
        <div>
          <motion.span
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="inline-flex items-center gap-2 rounded-full border border-[color:var(--border)] bg-white px-3 py-1.5 text-xs font-semibold text-[color:var(--primary)] shadow-[var(--shadow-card)]"
          >
            <span className="relative flex size-2">
              <span className="absolute inline-flex size-2 animate-ping rounded-full bg-[color:var(--primary)] opacity-75" />
              <span className="relative inline-flex size-2 rounded-full bg-[color:var(--primary)]" />
            </span>
            16 outils du quotidien, dans une seule app
          </motion.span>

          <motion.h1
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.05 }}
            className="mt-5 text-4xl font-extrabold tracking-tight text-balance sm:text-5xl md:text-6xl md:leading-[1.05]"
          >
            Ton téléphone et ton PC,{" "}
            <span className="text-gradient">reliés en un scan</span>
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.12 }}
            className="mt-5 max-w-xl text-lg text-[color:var(--muted-foreground)] text-pretty"
          >
            Fichiers, photos, liens, presse-papier, caméra… passent d’un appareil
            à l’autre sans fil. Tu scannes un QR code une fois, et tout devient
            disponible des deux côtés. Pas de câble, pas de compte, pas de cloud.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.18 }}
            className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-center"
          >
            <a
              href={SITE.androidApk}
              className="inline-flex items-center justify-center gap-2 rounded-2xl brand-gradient px-6 py-3.5 text-base font-semibold text-white shadow-[var(--shadow-pop)] transition-transform hover:-translate-y-0.5 active:translate-y-0"
            >
              <Download className="size-5" />
              Télécharger l’app Android
            </a>
            <a
              href="#etapes"
              className="inline-flex items-center justify-center gap-2 rounded-2xl border border-[color:var(--border)] bg-white px-6 py-3.5 text-base font-semibold text-[color:var(--foreground)] transition-colors hover:bg-[color:var(--muted)]"
            >
              <PlayCircle className="size-5 text-[color:var(--primary)]" />
              Voir comment ça marche
            </a>
          </motion.div>

          <motion.ul
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.6, delay: 0.3 }}
            className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-3"
          >
            {TRUST.map((t) => (
              <li
                key={t.label}
                className="flex items-center gap-2 text-sm font-medium text-[color:var(--muted-foreground)]"
              >
                <t.icon className="size-4 text-[color:var(--primary)]" />
                {t.label}
              </li>
            ))}
            <li className="text-sm font-medium text-[color:var(--muted-foreground)]">
              · Gratuit & open source
            </li>
          </motion.ul>
        </div>

        {/* Colonne visuelle */}
        <motion.div
          initial={{ opacity: 0, scale: 0.94 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.7, delay: 0.15, ease: [0.22, 1, 0.36, 1] }}
        >
          <ConnectVisual />
        </motion.div>
      </div>
    </section>
  );
}
