"use client";
import { motion } from "framer-motion";
import {
  ArrowDownToLine,
  ScanLine,
  Check,
  Monitor,
  Smartphone,
  QrCode,
} from "lucide-react";

const STEPS = [
  {
    num: "01",
    title: "Installe Linkup",
    text: "Un fichier pour le PC, un pour le téléphone. Tu décompresses, tu lances : rien d’autre à installer, aucune inscription.",
    Visual: VisualInstall,
  },
  {
    num: "02",
    title: "Scanne le QR code",
    text: "Ton PC affiche un QR code. Tu le vises avec l’app sur ton téléphone. La liaison se fait en moins de cinq secondes.",
    Visual: VisualScan,
  },
  {
    num: "03",
    title: "Tout est relié",
    text: "Fichiers, photos et presse-papier passent d’un appareil à l’autre, dans les deux sens. Et ça se reconnecte tout seul ensuite.",
    Visual: VisualLinked,
  },
];

export default function HowItWorks() {
  return (
    <section id="etapes" className="relative overflow-hidden bg-zinc-50 py-20 sm:py-28">
      <div className="relative mx-auto max-w-5xl px-4 sm:px-6 lg:px-8">
        <motion.header
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.4 }}
          transition={{ duration: 0.6 }}
          className="mb-16 max-w-2xl sm:mb-24"
        >
          <span className="mb-5 inline-flex items-center gap-2 text-[11px] font-bold uppercase tracking-[0.2em] text-violet-700">
            <span className="h-px w-8 bg-violet-300" />
            Comment ça marche
          </span>
          <h2 className="font-heading text-4xl font-black leading-[1.05] tracking-tight text-zinc-900 sm:text-5xl lg:text-[56px]">
            Relié en moins
            <br />
            d’une{" "}
            <span className="relative inline-block">
              <span className="relative z-10">minute.</span>
              <span className="absolute -bottom-0.5 left-0 right-0 -z-0 h-2.5 rounded-sm bg-violet-200" />
            </span>
          </h2>
        </motion.header>

        <div className="space-y-10 sm:space-y-14">
          {STEPS.map((s, i) => (
            <StepRow key={s.num} step={s} reverse={i % 2 === 1} />
          ))}
        </div>
      </div>
    </section>
  );
}

function StepRow({ step, reverse }) {
  const { Visual } = step;
  return (
    <motion.div
      initial={{ opacity: 0, y: 40 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, amount: 0.3 }}
      transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
      className={`flex flex-col items-center gap-8 sm:gap-12 lg:gap-16 ${
        reverse ? "sm:flex-row-reverse" : "sm:flex-row"
      }`}
    >
      {/* Texte */}
      <div className="flex-1">
        <div className="mb-4 flex items-center gap-4">
          <span
            className="font-heading font-black leading-none text-violet-200"
            style={{ fontSize: "clamp(56px, 9vw, 88px)", letterSpacing: "-0.05em" }}
          >
            {step.num}
          </span>
          <span className="h-px flex-1 bg-zinc-200" />
        </div>
        <h3 className="font-heading mb-3 text-2xl font-black tracking-tight text-zinc-900 sm:text-3xl">
          {step.title}
        </h3>
        <p className="max-w-md text-base leading-relaxed text-zinc-500">
          {step.text}
        </p>
      </div>

      {/* Visuel */}
      <div className="flex w-full shrink-0 justify-center sm:w-72 lg:w-80">
        <Visual />
      </div>
    </motion.div>
  );
}

/* ── Mini visuels par étape ─────────────────────────────────────────── */
function Card({ children, className = "" }) {
  return (
    <div
      className={`relative w-full max-w-72 overflow-hidden rounded-3xl border border-zinc-200 bg-white p-5 shadow-pop ${className}`}
    >
      {children}
    </div>
  );
}

function VisualInstall() {
  return (
    <Card>
      <div className="space-y-3">
        {[
          { icon: Smartphone, label: "linkup.apk", sub: "Téléphone · 65 Mo" },
          { icon: Monitor, label: "linkup-pc", sub: "Ordinateur · 141 Mo" },
        ].map((f) => (
          <div
            key={f.label}
            className="flex items-center gap-3 rounded-2xl border border-zinc-100 bg-zinc-50/70 p-3"
          >
            <span className="grid size-10 place-items-center rounded-xl bg-zinc-900 text-white">
              <f.icon className="size-5" />
            </span>
            <div className="min-w-0 flex-1">
              <div className="text-[13px] font-bold text-zinc-900">{f.label}</div>
              <div className="text-[10px] text-zinc-500">{f.sub}</div>
            </div>
            <span className="grid size-7 place-items-center rounded-full bg-violet-100 text-violet-700">
              <ArrowDownToLine className="size-4" />
            </span>
          </div>
        ))}
      </div>
    </Card>
  );
}

function VisualScan() {
  return (
    <Card className="flex flex-col items-center">
      <div className="relative grid size-36 place-items-center rounded-2xl bg-zinc-950 p-4">
        <QrCode className="size-full text-white" strokeWidth={1.2} />
        {/* ligne de scan */}
        <motion.span
          className="absolute inset-x-3 h-0.5 rounded-full bg-violet-400 shadow-[0_0_12px_2px_rgba(167,139,250,0.8)]"
          animate={{ top: ["12%", "84%", "12%"] }}
          transition={{ duration: 2.4, repeat: Infinity, ease: "easeInOut" }}
        />
      </div>
      <div className="mt-4 flex items-center gap-2 text-[12px] font-semibold text-zinc-600">
        <ScanLine className="size-4 text-violet-600" />
        Vise le QR avec le tél
      </div>
    </Card>
  );
}

function VisualLinked() {
  return (
    <Card className="flex flex-col items-center">
      <div className="flex w-full items-center justify-between">
        <DeviceDot icon={Smartphone} label="Tél" />
        <div className="relative mx-2 flex-1">
          <div className="h-0.5 w-full rounded-full bg-zinc-100" />
          <motion.span
            className="absolute top-1/2 size-2 -translate-y-1/2 rounded-full bg-violet-600"
            animate={{ left: ["0%", "100%"] }}
            transition={{ duration: 1.6, repeat: Infinity, ease: "easeInOut" }}
          />
        </div>
        <DeviceDot icon={Monitor} label="PC" />
      </div>
      <div className="mt-4 inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-3 py-1.5 text-[11px] font-bold text-emerald-700">
        <Check className="size-3.5" strokeWidth={3} />
        Relié · sans câble
      </div>
    </Card>
  );
}

function DeviceDot({ icon: Icon, label }) {
  return (
    <div className="flex flex-col items-center gap-1.5">
      <span className="grid size-12 place-items-center rounded-2xl bg-violet-50 text-violet-700 ring-1 ring-violet-100">
        <Icon className="size-6" />
      </span>
      <span className="text-[10px] font-semibold text-zinc-500">{label}</span>
    </div>
  );
}
