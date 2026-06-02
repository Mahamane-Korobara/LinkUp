"use client";
import { motion } from "framer-motion";
import { Check, X, Sparkles, Link2, Cable, MessageCircle, Mail, Cloud } from "lucide-react";

const METHODS = [
  {
    Icon: Cable,
    name: "Câble / clé USB",
    tagline: "Le matériel qu’on cherche",
    issues: ["À avoir sur soi", "Le bon port jamais là", "Branchement manuel"],
  },
  {
    Icon: MessageCircle,
    name: "WhatsApp à soi-même",
    tagline: "Le détour du quotidien",
    issues: ["Qualité compressée", "Photos une par une", "Discussion encombrée"],
  },
  {
    Icon: Mail,
    name: "E-mail à soi-même",
    tagline: "Le bricolage lent",
    issues: ["Limite de taille", "Lent à l’envoi", "Boîte polluée"],
  },
  {
    Icon: Cloud,
    name: "Cloud / Drive",
    tagline: "Le tiers de confiance",
    issues: ["Compte obligatoire", "Données chez un tiers", "Upload puis download"],
  },
];

const LINKUP_RESPONSES = [
  "Sans fil, rien à brancher",
  "Qualité d’origine préservée",
  "Tes données restent sur ton réseau",
  "Un scan, puis ça reconnecte seul",
];

export default function Comparison() {
  return (
    <section className="relative overflow-hidden bg-zinc-50 py-20 sm:py-28">
      <div className="relative mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
        <motion.header
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.4 }}
          transition={{ duration: 0.6 }}
          className="mx-auto mb-14 max-w-2xl text-center sm:mb-20"
        >
          <span className="mb-5 inline-flex items-center gap-2 rounded-full border border-violet-200 bg-violet-100 px-3 py-1.5 text-[11px] font-bold uppercase tracking-[0.2em] text-violet-700">
            <Sparkles className="size-3" />
            Pourquoi Linkup
          </span>
          <h2 className="font-heading text-4xl font-black leading-[1.05] tracking-tight text-zinc-900 sm:text-5xl lg:text-[56px]">
            Comparé à ce que tu
            <br />
            <span className="text-violet-600">fais peut-être déjà.</span>
          </h2>
          <p className="mt-5 text-base leading-relaxed text-zinc-500 sm:text-lg">
            La même tâche, sans le détour. Pas de matériel, pas de compte, pas de
            perte de qualité.
          </p>
        </motion.header>

        <div className="mb-6 grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
          {METHODS.map((m, i) => (
            <MethodCard key={m.name} m={m} index={i} />
          ))}
        </div>

        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.3 }}
          transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
          className="relative"
        >
          <div
            className="pointer-events-none absolute -inset-6"
            style={{
              background:
                "radial-gradient(ellipse, rgba(124,58,237,0.25) 0%, transparent 70%)",
              filter: "blur(40px)",
            }}
          />
          <div
            className="relative overflow-hidden rounded-2xl border border-violet-300/40 bg-gradient-to-br from-violet-600 via-violet-700 to-violet-800 p-6 text-white sm:p-8"
            style={{
              boxShadow:
                "0 30px 70px -20px rgba(124,58,237,0.5), inset 0 1px 0 0 rgba(255,255,255,0.15)",
            }}
          >
            <div
              className="pointer-events-none absolute inset-0 opacity-10"
              style={{
                backgroundImage:
                  "linear-gradient(to right, white 1px, transparent 1px), linear-gradient(to bottom, white 1px, transparent 1px)",
                backgroundSize: "40px 40px",
              }}
            />
            <div className="relative grid items-center gap-6 sm:gap-10 lg:grid-cols-[auto_1fr]">
              <div className="flex items-center gap-4">
                <div className="grid size-16 shrink-0 place-items-center rounded-2xl border border-white/20 bg-white/15 backdrop-blur sm:size-20">
                  <Link2 className="size-8 text-white sm:size-10" strokeWidth={2} />
                </div>
                <div>
                  <div className="mb-1 text-[10px] font-bold uppercase tracking-[0.18em] text-violet-200">
                    La réponse
                  </div>
                  <h3 className="font-heading text-2xl font-black leading-none tracking-tight sm:text-3xl">
                    Linkup
                  </h3>
                  <div className="mt-1 text-[12px] text-violet-200">
                    Le pont sans fil tél ↔ PC
                  </div>
                </div>
              </div>

              <div className="grid gap-x-6 gap-y-3 sm:grid-cols-2">
                {LINKUP_RESPONSES.map((r, i) => (
                  <motion.div
                    key={r}
                    initial={{ opacity: 0, x: -10 }}
                    whileInView={{ opacity: 1, x: 0 }}
                    viewport={{ once: true }}
                    transition={{ delay: 0.2 + i * 0.08 }}
                    className="flex items-start gap-2.5 text-sm"
                  >
                    <span className="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full border border-white/10 bg-white/20 backdrop-blur">
                      <Check className="size-3 text-white" strokeWidth={3} />
                    </span>
                    <span className="font-medium leading-snug text-white/95">{r}</span>
                  </motion.div>
                ))}
              </div>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
}

function MethodCard({ m, index }) {
  const { Icon } = m;
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, amount: 0.3 }}
      transition={{ duration: 0.5, delay: index * 0.08 }}
      className="group relative overflow-hidden rounded-2xl border border-zinc-200 bg-white p-4 transition-colors hover:border-zinc-300 sm:p-5"
    >
      <div className="mb-4 flex size-12 items-center justify-center rounded-xl border border-zinc-200 bg-white text-zinc-400 shadow-sm">
        <Icon className="size-6" />
      </div>
      <div className="mb-3">
        <div className="text-sm font-bold leading-tight text-zinc-900">{m.name}</div>
        <div className="mt-0.5 text-[11px] text-zinc-500">{m.tagline}</div>
      </div>
      <ul className="mt-3 space-y-1.5 border-t border-zinc-100 pt-3">
        {m.issues.map((issue) => (
          <li
            key={issue}
            className="flex items-start gap-2 text-[11.5px] leading-snug text-zinc-600"
          >
            <X className="mt-0.5 size-3 shrink-0 text-red-500" strokeWidth={3} />
            <span>{issue}</span>
          </li>
        ))}
      </ul>
    </motion.div>
  );
}
