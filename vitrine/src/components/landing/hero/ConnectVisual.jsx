"use client";
import { motion } from "framer-motion";
import {
  Smartphone,
  Monitor,
  QrCode,
  FileText,
  Link2,
  Image as ImageIcon,
  Clipboard,
} from "lucide-react";

const FLOATERS = [
  { icon: FileText, label: "Document.pdf", className: "left-[-6%] top-[18%]", delay: 0 },
  { icon: ImageIcon, label: "12 photos", className: "right-[-4%] top-[8%]", delay: 0.6 },
  { icon: Link2, label: "Lien ouvert", className: "right-[2%] bottom-[20%]", delay: 1.1 },
  { icon: Clipboard, label: "Copié ✓", className: "left-[-2%] bottom-[12%]", delay: 1.6 },
];

export default function ConnectVisual() {
  return (
    <div className="relative mx-auto aspect-square w-full max-w-[480px]">
      {/* halo */}
      <div className="absolute inset-0 grad-soft rounded-[2.5rem] blur-2xl" />

      {/* carte centrale */}
      <div className="relative flex h-full items-center justify-center">
        <div className="relative flex w-full items-center justify-between gap-3 rounded-[2rem] border border-[color:var(--border)] bg-white/70 p-6 shadow-[var(--shadow-pop)] backdrop-blur-xl sm:p-8">
          {/* Téléphone */}
          <DeviceCard
            icon={Smartphone}
            title="Téléphone"
            sub="Android"
            tone="from-indigo-500 to-violet-500"
          />

          {/* Liaison animée */}
          <div className="relative flex flex-1 flex-col items-center">
            <div className="relative grid place-items-center">
              <span className="pulse-ring absolute size-12 rounded-full border-2 border-[color:var(--primary)]" />
              <span
                className="pulse-ring absolute size-12 rounded-full border-2 border-[color:var(--accent)]"
                style={{ animationDelay: "1.2s" }}
              />
              <div className="brand-gradient relative grid size-12 place-items-center rounded-2xl text-white shadow-[var(--shadow-card)]">
                <QrCode className="size-6" />
              </div>
            </div>
            {/* paquets qui voyagent */}
            <div className="relative mt-4 h-1.5 w-full overflow-hidden rounded-full bg-[color:var(--muted)]">
              <motion.span
                className="brand-gradient absolute inset-y-0 left-0 w-1/3 rounded-full"
                animate={{ x: ["-40%", "260%"] }}
                transition={{ duration: 1.8, repeat: Infinity, ease: "easeInOut" }}
              />
            </div>
            <span className="mt-2 text-[11px] font-semibold text-[color:var(--muted-foreground)]">
              relié · sans câble
            </span>
          </div>

          {/* PC */}
          <DeviceCard
            icon={Monitor}
            title="Ordinateur"
            sub="Windows · Linux"
            tone="from-sky-500 to-cyan-400"
          />
        </div>

        {/* étiquettes flottantes */}
        {FLOATERS.map((f) => (
          <motion.div
            key={f.label}
            className={`absolute ${f.className} flex items-center gap-2 rounded-xl border border-[color:var(--border)] bg-white px-3 py-2 shadow-[var(--shadow-card)]`}
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1, y: [0, -7, 0] }}
            transition={{
              opacity: { delay: f.delay, duration: 0.5 },
              scale: { delay: f.delay, duration: 0.5 },
              y: { delay: f.delay, duration: 5, repeat: Infinity, ease: "easeInOut" },
            }}
          >
            <f.icon className="size-4 text-[color:var(--primary)]" />
            <span className="text-xs font-semibold whitespace-nowrap">{f.label}</span>
          </motion.div>
        ))}
      </div>
    </div>
  );
}

function DeviceCard({ icon: Icon, title, sub, tone }) {
  return (
    <div className="flex flex-col items-center gap-2">
      <div
        className={`grid size-16 place-items-center rounded-2xl bg-gradient-to-br ${tone} text-white shadow-[var(--shadow-card)] sm:size-20`}
      >
        <Icon className="size-8 sm:size-9" strokeWidth={1.8} />
      </div>
      <div className="text-center">
        <p className="text-sm font-bold leading-tight">{title}</p>
        <p className="text-[11px] text-[color:var(--muted-foreground)]">{sub}</p>
      </div>
    </div>
  );
}
