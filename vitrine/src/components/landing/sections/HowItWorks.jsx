"use client";
import { motion } from "framer-motion";
import { MonitorDown, ScanLine, Sparkles } from "lucide-react";
import { SectionHeading } from "@/components/ui/Section";
import Reveal from "@/components/ui/Reveal";

const STEPS = [
  {
    icon: MonitorDown,
    n: "1",
    title: "Installe sur ton PC",
    text: "Un dossier à décompresser, un double-clic. Rien d’autre à installer — ni logiciel compliqué, ni inscription.",
  },
  {
    icon: ScanLine,
    n: "2",
    title: "Scanne le QR avec ton tél",
    text: "L’app ouvre un scanner. Tu vises le QR code affiché sur ton PC. La liaison se fait en moins de 5 secondes.",
  },
  {
    icon: Sparkles,
    n: "3",
    title: "Tout devient relié",
    text: "Fichiers, photos, presse-papier, caméra… disponibles des deux côtés, instantanément. Et ça se reconnecte tout seul ensuite.",
  },
];

export default function HowItWorks() {
  return (
    <section id="etapes" className="relative py-20 sm:py-28">
      <div className="grad-soft pointer-events-none absolute inset-x-0 top-0 h-px" />
      <div className="mx-auto max-w-6xl px-5">
        <SectionHeading
          eyebrow="En 3 étapes"
          title="Relié en moins d’une minute"
          subtitle="Pas de manuel à lire. Tu installes, tu scannes, c’est prêt — la première fois comme toutes les suivantes."
        />

        <div className="relative mt-16 grid gap-6 md:grid-cols-3">
          {/* ligne de liaison en fond (desktop) */}
          <div className="absolute top-9 left-[16%] right-[16%] hidden h-0.5 md:block">
            <div className="brand-gradient h-full w-full opacity-30" />
          </div>

          {STEPS.map((s, i) => (
            <Reveal key={s.n} delay={i * 0.12}>
              <div className="relative flex h-full flex-col items-center rounded-2xl border border-[color:var(--border)] bg-white p-7 text-center shadow-[var(--shadow-card)]">
                <div className="relative">
                  <motion.span
                    className="brand-gradient grid size-16 place-items-center rounded-2xl text-white shadow-[var(--shadow-pop)]"
                    whileHover={{ rotate: -6, scale: 1.05 }}
                  >
                    <s.icon className="size-7" strokeWidth={1.9} />
                  </motion.span>
                  <span className="absolute -right-2 -top-2 grid size-7 place-items-center rounded-full border-2 border-white bg-[color:var(--ink)] text-xs font-bold text-white">
                    {s.n}
                  </span>
                </div>
                <h3 className="mt-5 text-lg font-bold">{s.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-[color:var(--muted-foreground)]">
                  {s.text}
                </p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
