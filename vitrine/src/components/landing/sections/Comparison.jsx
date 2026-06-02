"use client";
import { Check, X } from "lucide-react";
import { SectionHeading } from "@/components/ui/Section";
import Reveal from "@/components/ui/Reveal";

const ROWS = [
  {
    task: "Transférer un fichier",
    before: "Câble, clé USB ou se l’envoyer par WhatsApp",
    after: "Sans fil, instantané, dans les deux sens",
  },
  {
    task: "Ouvrir un lien sur le PC",
    before: "Retaper l’URL à la main",
    after: "Un tap, la page s’ouvre toute seule",
  },
  {
    task: "Récupérer ses photos",
    before: "Une par une, qualité perdue",
    after: "La galerie entière, qualité d’origine",
  },
  {
    task: "Utiliser une webcam",
    before: "En acheter une ou installer 3 logiciels",
    after: "La caméra de ton téléphone, direct",
  },
  {
    task: "Tes données",
    before: "Stockées sur un cloud que tu ne contrôles pas",
    after: "Restent sur ton réseau, un point c’est tout",
  },
];

export default function Comparison() {
  return (
    <section className="relative py-20 sm:py-28">
      <div className="mx-auto max-w-5xl px-5">
        <SectionHeading
          eyebrow="Avant / après"
          title="La même tâche, sans la galère"
          subtitle="Linkup ne réinvente rien : il remplace les bricolages que tu fais déjà tous les jours par un seul geste simple."
        />

        <Reveal>
          <div className="mt-12 overflow-hidden rounded-2xl border border-[color:var(--border)] bg-white shadow-[var(--shadow-card)]">
            {/* en-tête */}
            <div className="grid grid-cols-1 border-b border-[color:var(--border)] bg-[color:var(--muted)] text-sm font-bold sm:grid-cols-[1.1fr_1.4fr_1.4fr]">
              <div className="hidden px-5 py-4 sm:block">La tâche</div>
              <div className="px-5 py-4 text-[color:var(--muted-foreground)]">
                À l’ancienne
              </div>
              <div className="px-5 py-4 text-[color:var(--primary)]">
                Avec Linkup
              </div>
            </div>

            {ROWS.map((r, i) => (
              <div
                key={r.task}
                className={`grid grid-cols-1 items-center gap-x-2 sm:grid-cols-[1.1fr_1.4fr_1.4fr] ${
                  i % 2 ? "bg-[color:var(--muted)]/40" : "bg-white"
                }`}
              >
                <div className="px-5 pt-4 text-sm font-bold sm:py-4">{r.task}</div>
                <div className="flex items-start gap-2 px-5 py-2 text-sm text-[color:var(--muted-foreground)] sm:py-4">
                  <X className="mt-0.5 size-4 shrink-0 text-red-400" />
                  {r.before}
                </div>
                <div className="flex items-start gap-2 px-5 pb-4 text-sm font-medium sm:py-4">
                  <Check className="mt-0.5 size-4 shrink-0 text-[color:var(--primary)]" />
                  {r.after}
                </div>
              </div>
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  );
}
