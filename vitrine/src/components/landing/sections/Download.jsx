"use client";
import { useState } from "react";
import { motion } from "framer-motion";
import {
  Sparkles,
  Smartphone,
  Monitor,
  ArrowDownToLine,
  Check,
} from "lucide-react";
import { SITE } from "@/lib/site";
import InstallModal from "@/components/landing/InstallModal";

export default function DownloadSection() {
  const [showInstall, setShowInstall] = useState(false);
  return (
    <section
      id="telecharger"
      className="relative overflow-hidden bg-zinc-950 py-24 sm:py-32"
    >
      {/* grille */}
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.05]"
        style={{
          backgroundImage:
            "linear-gradient(to right, white 1px, transparent 1px), linear-gradient(to bottom, white 1px, transparent 1px)",
          backgroundSize: "60px 60px",
          maskImage: "radial-gradient(ellipse at center, black 30%, transparent 80%)",
          WebkitMaskImage:
            "radial-gradient(ellipse at center, black 30%, transparent 80%)",
        }}
      />
      {/* glow violet animé */}
      <motion.div
        animate={{ scale: [1, 1.15, 1], opacity: [0.35, 0.55, 0.35] }}
        transition={{ duration: 6, repeat: Infinity, ease: "easeInOut" }}
        className="pointer-events-none absolute left-1/2 top-1/2 h-[500px] w-[800px] -translate-x-1/2 -translate-y-1/2"
        style={{
          background: "radial-gradient(ellipse, rgba(124,58,237,0.5) 0%, transparent 60%)",
          filter: "blur(80px)",
        }}
      />

      <div className="relative mx-auto max-w-4xl px-4 sm:px-6 lg:px-8">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="mb-12 text-center"
        >
          <span className="mb-6 inline-flex items-center gap-2 rounded-full border border-violet-500/20 bg-violet-500/10 px-3 py-1.5 text-[11px] font-bold uppercase tracking-[0.2em] text-violet-300">
            <Sparkles className="size-3" />
            Prêt à relier tes appareils ?
          </span>
          <h2 className="font-heading text-4xl font-black leading-[1.02] tracking-tight text-white sm:text-5xl lg:text-[60px]">
            Installe Linkup,
            <br />
            c’est{" "}
            <span className="relative inline-block">
              <span className="relative z-10 text-violet-400">gratuit.</span>
              <span className="absolute -bottom-1 left-0 right-0 -z-0 h-3 rounded-sm bg-violet-500/30" />
            </span>
          </h2>
          <p className="mx-auto mt-5 max-w-xl text-base leading-relaxed text-zinc-400 sm:text-lg">
            Deux fichiers : l’app pour ton téléphone, le programme pour ton PC.
            Téléchargement direct, un seul clic.
          </p>
        </motion.div>

        <div className="grid gap-5 md:grid-cols-2">
          <DownloadCard
            delay={0}
            icon={Smartphone}
            kicker="Sur ton téléphone"
            sub="Android uniquement · 8.0 ou +"
            href={SITE.androidApk}
            fileLabel="linkup.apk"
            size={SITE.androidSize}
            steps={[
              "Ouvre le fichier téléchargé",
              "Autorise l’installation si demandé",
              "Lance Linkup et appuie sur « Scanner »",
            ]}
          />
          <DownloadCard
            delay={0.12}
            icon={Monitor}
            kicker="Sur ton ordinateur"
            sub="Linux · toutes distributions"
            href={SITE.pcBundle}
            fileLabel="Linkup.AppImage"
            size={SITE.pcSize}
            soon="Windows — bientôt disponible"
            onClick={() => setShowInstall(true)}
            steps={[
              "Clic droit → Propriétés → « Autoriser l’exécution »",
              "Double-clique le fichier",
              "Linkup s’ouvre — icône ajoutée au menu et au bureau",
            ]}
            alt={{ href: SITE.pcDeb, label: "Debian/Ubuntu/Mint : .deb" }}
          />
        </div>

        <p className="mt-8 text-center text-xs text-zinc-500">
          Téléchargement direct depuis le site · aucune inscription · open source
        </p>
      </div>

      <InstallModal open={showInstall} onClose={() => setShowInstall(false)} />
    </section>
  );
}

function DownloadCard({ icon: Icon, kicker, sub, href, fileLabel, size, steps, soon, alt, onClick, delay }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true }}
      transition={{ duration: 0.55, delay }}
      className="flex flex-col rounded-3xl border border-white/10 bg-white/[0.04] p-6 backdrop-blur-sm sm:p-7"
    >
      <div className="flex items-center gap-3">
        <span className="grid size-12 place-items-center rounded-2xl bg-white text-zinc-900">
          <Icon className="size-6" />
        </span>
        <div>
          <h3 className="font-heading text-lg font-black tracking-tight text-white">
            {kicker}
          </h3>
          <p className="text-[13px] text-zinc-400">{sub}</p>
        </div>
      </div>

      <a
        href={href}
        download
        onClick={onClick}
        className="group mt-6 inline-flex items-center justify-between gap-2 rounded-xl bg-white px-5 py-3.5 font-semibold text-zinc-900 shadow-2xl shadow-violet-900/40 transition-all hover:bg-zinc-100"
      >
        <span className="flex items-center gap-2 text-sm">
          <ArrowDownToLine className="size-5 text-violet-600" />
          Télécharger
          <span className="font-mono text-[12px] text-zinc-400">{fileLabel}</span>
        </span>
        <span className="rounded-full bg-zinc-100 px-2.5 py-1 text-[11px] font-bold text-zinc-500 group-hover:bg-violet-100 group-hover:text-violet-700">
          {size}
        </span>
      </a>

      {soon && (
        <div className="mt-2.5 flex items-center justify-center gap-2 rounded-xl border border-dashed border-white/15 px-4 py-2.5 text-[13px] font-medium text-zinc-500">
          <Monitor className="size-4" />
          {soon}
        </div>
      )}

      <ul className="mt-5 space-y-2.5">
        {steps.map((s, i) => (
          <li key={s} className="flex items-start gap-2.5 text-sm text-zinc-300">
            <span className="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full bg-violet-500/20 text-[10px] font-bold text-violet-300">
              {i + 1}
            </span>
            {s}
          </li>
        ))}
      </ul>

      {alt && (
        <a
          href={alt.href}
          download
          className="mt-4 inline-flex items-center gap-1.5 text-xs font-medium text-zinc-500 underline-offset-4 hover:text-violet-300 hover:underline"
        >
          <ArrowDownToLine className="size-3.5" />
          {alt.label}
        </a>
      )}
    </motion.div>
  );
}
