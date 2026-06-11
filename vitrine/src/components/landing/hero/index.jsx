"use client";
import { motion } from "framer-motion";
import {
  ArrowDownToLine,
  Sparkles,
  Smartphone,
  Monitor,
  FileUp,
  ClipboardCheck,
  Images,
  Check,
  WifiOff,
  UserX,
  ShieldCheck,
} from "lucide-react";
import { SITE } from "@/lib/site";

export default function HeroSection() {
  return (
    <section className="relative flex min-h-screen flex-col overflow-hidden bg-white pt-20">
      {/* grille subtile */}
      <div
        className="pointer-events-none absolute inset-0 z-0 opacity-[0.15]"
        style={{
          backgroundImage:
            "linear-gradient(to right, #808080 1px, transparent 1px), linear-gradient(to bottom, #808080 1px, transparent 1px)",
          backgroundSize: "60px 60px",
          maskImage: "linear-gradient(to bottom, black 45%, transparent 100%)",
          WebkitMaskImage:
            "linear-gradient(to bottom, black 45%, transparent 100%)",
        }}
      />
      {/* glow violet derrière le visuel */}
      <div
        className="pointer-events-none absolute right-0 top-1/2 z-0 hidden h-[650px] w-[650px] -translate-y-1/2 translate-x-1/4 lg:block"
        style={{
          background:
            "radial-gradient(circle, rgba(124,58,237,0.18) 0%, transparent 60%)",
          filter: "blur(60px)",
        }}
      />

      <div className="relative z-10 mx-auto flex w-full max-w-7xl flex-1 flex-col justify-center gap-12 px-4 py-10 sm:px-6 lg:px-8">
        <div className="grid items-center gap-10 lg:grid-cols-2">
          {/* ─── GAUCHE ─── */}
          <div>
            <motion.div
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.1 }}
              className="mb-6 flex items-center gap-2"
            >
              <Sparkles className="size-3.5 text-violet-500" />
              <span className="text-xs font-semibold uppercase tracking-widest text-violet-600">
                Le pont sans fil tél ↔ PC
              </span>
              <span className="h-px max-w-15 flex-1 bg-violet-200" />
            </motion.div>

            {/* h1 = élément LCP : rendu immédiat (pas d'entrée opacity/translate)
                pour ne pas retarder le Largest Contentful Paint. */}
            <motion.h1
              initial={false}
              className="font-heading mb-5 text-[clamp(2.1rem,5.5vw,4rem)] font-black leading-[1.05] tracking-tight text-zinc-900"
            >
              Ton téléphone et ton PC,{" "}
              <span className="relative inline-block">
                <span className="relative z-10">reliés en un scan</span>
                <motion.span
                  initial={{ scaleX: 0 }}
                  animate={{ scaleX: 1 }}
                  transition={{ delay: 0.7, duration: 0.5 }}
                  className="absolute bottom-1 left-0 right-0 z-0 h-3 origin-left rounded-sm bg-violet-300"
                />
              </span>
            </motion.h1>

            <motion.p
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.35 }}
              className="mb-9 max-w-md text-base leading-relaxed text-zinc-500 sm:text-lg"
            >
              Fichiers, photos et presse-papier passent d’un appareil à l’autre{" "}
              <strong className="font-semibold text-zinc-700">
                sans fil
              </strong>
              , en scannant un QR code. Et{" "}
              <strong className="font-semibold text-zinc-700">
                même sans PC
              </strong>{" "}
              : télécharge des vidéos (YouTube, TikTok…) et transcris-les en
              texte. Pas de câble, pas de compte, pas de cloud.
            </motion.p>

            <motion.div
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.45 }}
              className="flex flex-col items-start gap-5 sm:flex-row sm:items-center sm:gap-4"
            >
              <a
                href="#telecharger"
                className="group inline-flex h-12 items-center gap-2 rounded-xl bg-zinc-900 pl-6 pr-2.5 text-sm font-semibold text-white shadow-md shadow-violet-200/60 transition-all hover:bg-zinc-800"
              >
                Télécharger Linkup
                <span className="flex size-8 items-center justify-center rounded-full bg-violet-500/20 transition-all group-hover:bg-violet-500/40">
                  <ArrowDownToLine className="size-4" />
                </span>
              </a>
              <a
                href="#outils"
                className="py-2 text-sm font-semibold tracking-wide text-zinc-500 underline decoration-violet-300 decoration-2 underline-offset-8 transition-colors hover:text-violet-700"
              >
                Voir les outils
              </a>
            </motion.div>

            <motion.ul
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ delay: 0.6 }}
              className="mt-9 flex flex-wrap items-center gap-x-6 gap-y-2"
            >
              {[
                { icon: WifiOff, label: "Sans câble" },
                { icon: UserX, label: "Sans compte" },
                { icon: ShieldCheck, label: "Sans cloud" },
              ].map((t) => (
                <li
                  key={t.label}
                  className="flex items-center gap-2 text-sm font-medium text-zinc-500"
                >
                  <t.icon className="size-4 text-violet-500" />
                  {t.label}
                </li>
              ))}
            </motion.ul>
          </div>

          {/* ─── DROITE — mockup produit ─── */}
          <motion.div
            initial={{ opacity: 0, x: 30 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.2, duration: 0.5 }}
            className="relative mt-4 h-[520px] sm:h-[580px] lg:mt-0 lg:h-[620px]"
          >
            <AppMockup />
            <div className="hidden lg:block">
              <FloatingClipboard />
              <FloatingStat />
              <FloatingReceived />
              <FloatingActivity />
            </div>
          </motion.div>
        </div>
      </div>
    </section>
  );
}

/* ── Mockup central : écran de l'app Linkup ─────────────────────────── */
function AppMockup() {
  return (
    <motion.div
      animate={{ y: [0, -12, 0], rotateZ: [-1, 1, -1] }}
      transition={{ duration: 8, repeat: Infinity, ease: "easeInOut" }}
      className="absolute left-1/2 top-1/2 w-[340px] -translate-x-1/2 -translate-y-1/2"
    >
      {/* cartes fantômes derrière */}
      <div
        className="absolute inset-0 -z-10 rounded-[2rem] border border-zinc-100 bg-white shadow-xl"
        style={{ transform: "translate(18px, 22px) rotate(4deg) scale(0.95)", opacity: 0.5 }}
      />
      <div
        className="absolute inset-0 -z-20 rounded-[2rem] border border-zinc-100 bg-white shadow-md"
        style={{ transform: "translate(-18px, 12px) rotate(-3deg) scale(0.9)", opacity: 0.3 }}
      />

      <div className="overflow-hidden rounded-[2rem] border border-zinc-200 bg-white shadow-2xl shadow-violet-200/40">
        {/* header app */}
        <div className="flex items-center justify-between bg-zinc-950 px-5 py-4 text-white">
          <div className="flex items-center gap-2">
            <span className="grid size-7 place-items-center rounded-lg bg-violet-600">
              <Smartphone className="size-3.5" />
            </span>
            <span className="text-sm font-bold">Linkup</span>
          </div>
          <span className="flex items-center gap-1.5 rounded-full bg-white/10 px-2.5 py-1 text-[10px] font-semibold">
            <span className="size-1.5 animate-pulse rounded-full bg-emerald-400" />
            Relié
          </span>
        </div>

        {/* appareil connecté */}
        <div className="border-b border-zinc-100 px-5 py-4">
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-2.5">
              <span className="grid size-9 place-items-center rounded-xl bg-violet-50 text-violet-700 ring-1 ring-violet-100">
                <Monitor className="size-4.5" />
              </span>
              <div>
                <div className="text-[13px] font-bold text-zinc-900">Mon PC</div>
                <div className="text-[10px] text-zinc-500">Wi-Fi local · approuvé</div>
              </div>
            </div>
            <span className="grid size-5 place-items-center rounded-full bg-emerald-100">
              <Check className="size-3 text-emerald-600" strokeWidth={3} />
            </span>
          </div>
        </div>

        {/* tuiles modules */}
        <div className="grid grid-cols-3 gap-2 px-5 py-4">
          {[
            { icon: FileUp, label: "Fichiers" },
            { icon: ClipboardCheck, label: "Presse-papier" },
            { icon: Images, label: "Galerie" },
          ].map((m) => (
            <div
              key={m.label}
              className="flex flex-col items-center gap-1.5 rounded-2xl border border-zinc-100 bg-zinc-50/60 py-3"
            >
              <m.icon className="size-5 text-zinc-700" />
              <span className="text-[9.5px] font-semibold text-zinc-600">{m.label}</span>
            </div>
          ))}
        </div>

        {/* transfert en cours */}
        <div className="mx-5 mb-5 rounded-2xl border border-zinc-100 bg-white p-3.5 shadow-card">
          <div className="mb-2 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="grid size-8 place-items-center rounded-lg bg-zinc-900 text-white">
                <FileUp className="size-4" />
              </span>
              <div>
                <div className="text-[12px] font-bold text-zinc-900">Rapport.pdf</div>
                <div className="text-[9.5px] text-zinc-500">tél → PC · 2,4 Mo</div>
              </div>
            </div>
            <span className="text-[11px] font-bold text-violet-600">100%</span>
          </div>
          <div className="h-1.5 overflow-hidden rounded-full bg-zinc-100">
            <motion.span
              className="block h-full rounded-full bg-violet-600"
              initial={{ width: "10%" }}
              animate={{ width: ["10%", "100%"] }}
              transition={{ duration: 2.2, repeat: Infinity, repeatDelay: 1.4, ease: "easeInOut" }}
            />
          </div>
        </div>
      </div>
    </motion.div>
  );
}

/* ── Cartes flottantes ──────────────────────────────────────────────── */
function FloatingClipboard() {
  return (
    <motion.div
      initial={{ opacity: 0, y: -20, rotate: -2 }}
      animate={{ opacity: 1, y: [0, -8, 0], rotate: -2 }}
      transition={{
        opacity: { delay: 0.8, duration: 0.4 },
        y: { duration: 5, repeat: Infinity, ease: "easeInOut" },
      }}
      style={{ width: 230 }}
      className="absolute left-0 top-6 z-20 flex items-center gap-3 overflow-hidden rounded-2xl border border-violet-100 bg-white/85 p-3.5 shadow-violet backdrop-blur-xl"
    >
      <span className="absolute bottom-3 left-0 top-3 w-1 rounded-r-full bg-gradient-to-b from-violet-400 to-violet-600" />
      <div className="grid size-11 shrink-0 place-items-center rounded-xl bg-gradient-to-br from-violet-500 to-violet-700 text-white shadow-md shadow-violet-300/50">
        <ClipboardCheck className="size-5" strokeWidth={2.4} />
      </div>
      <div className="min-w-0 flex-1">
        <div className="text-[11.5px] font-bold leading-tight text-zinc-900">
          Presse-papier copié
        </div>
        <div className="mt-0.5 truncate text-[10px] text-zinc-500">
          Collé sur le PC à l’instant
        </div>
      </div>
    </motion.div>
  );
}

function FloatingStat() {
  return (
    <motion.div
      initial={{ opacity: 0, x: 20, rotate: 3 }}
      animate={{ opacity: 1, x: 0, y: [0, 10, 0], rotate: 3 }}
      transition={{
        opacity: { delay: 0.9, duration: 0.4 },
        x: { delay: 0.9, duration: 0.4 },
        y: { duration: 6, repeat: Infinity, ease: "easeInOut", delay: 0.5 },
      }}
      style={{ width: 168 }}
      className="absolute right-0 top-10 z-20 overflow-hidden rounded-2xl bg-gradient-to-br from-zinc-900 via-zinc-900 to-zinc-800 p-4 text-white"
    >
      <div className="absolute -right-10 -top-10 size-36 rounded-full bg-violet-600/35 blur-3xl" />
      <div className="relative mb-2 flex items-center gap-1.5">
        <span className="size-1.5 animate-pulse rounded-full bg-violet-400" />
        <div className="text-[9px] font-bold uppercase tracking-[0.18em] text-violet-300">
          Appairage
        </div>
      </div>
      <div
        className="relative font-black leading-none tracking-tighter text-violet-400"
        style={{ fontSize: "46px", letterSpacing: "-0.04em" }}
      >
        &lt;5s
      </div>
      <div className="relative mt-2 flex items-center gap-1.5 text-[10px] text-zinc-400">
        <span className="h-px w-3 bg-violet-400/60" />
        du scan au connecté
      </div>
    </motion.div>
  );
}

function FloatingReceived() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20, rotate: 2 }}
      animate={{ opacity: 1, y: [0, -6, 0], rotate: 2 }}
      transition={{
        opacity: { delay: 1.0, duration: 0.4 },
        y: { duration: 5.5, repeat: Infinity, ease: "easeInOut", delay: 1 },
      }}
      style={{ width: 220 }}
      className="absolute bottom-24 right-1 z-20 flex items-center gap-3 overflow-hidden rounded-2xl border border-violet-100 bg-white/85 p-3 shadow-violet backdrop-blur-xl"
    >
      <span className="absolute bottom-3 left-0 top-3 w-1 rounded-r-full bg-gradient-to-b from-violet-400 to-violet-600" />
      <div className="grid size-10 shrink-0 place-items-center rounded-xl bg-violet-50 text-violet-700 ring-1 ring-violet-100">
        <Images className="size-5" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate text-[11.5px] font-bold text-zinc-900">
          24 photos importées
        </div>
        <div className="truncate text-[9.5px] text-zinc-500">
          Galerie du tél → PC
        </div>
      </div>
    </motion.div>
  );
}

function FloatingActivity() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10, rotate: -1 }}
      animate={{ opacity: 1, y: 0, rotate: -1 }}
      transition={{ delay: 1.2, duration: 0.4 }}
      className="absolute bottom-6 left-3 z-20 flex items-center gap-2.5 rounded-full border border-violet-100 bg-white/85 py-2 pl-2 pr-4 shadow-violet backdrop-blur-xl"
    >
      <span className="relative flex size-5 items-center justify-center rounded-full bg-gradient-to-br from-violet-100 to-violet-200">
        <span className="absolute inline-flex size-1.5 animate-ping rounded-full bg-violet-600 opacity-75" />
        <span className="relative inline-flex size-1.5 rounded-full bg-violet-600" />
      </span>
      <span className="text-[10.5px] font-bold text-zinc-900">
        Transfert terminé
      </span>
    </motion.div>
  );
}
