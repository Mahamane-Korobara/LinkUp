"use client";
import { motion } from "framer-motion";
import { ShieldCheck, WifiOff, UserX, Lock, Github } from "lucide-react";
import { SITE } from "@/lib/site";

const POINTS = [
  {
    icon: WifiOff,
    title: "Tout passe par ton réseau",
    text: "Tes fichiers voyagent directement d’un appareil à l’autre sur ton Wi-Fi. Ils ne partent pas sur un serveur lointain.",
  },
  {
    icon: UserX,
    title: "Aucun compte à créer",
    text: "Pas d’e-mail, pas de mot de passe, pas de profil. Tu installes et tu scannes, point.",
  },
  {
    icon: Lock,
    title: "Liaison chiffrée et approuvée",
    text: "Chaque appareil doit être approuvé sur ton PC avant de se connecter. La liaison est chiffrée de bout en bout.",
  },
];

export default function Privacy() {
  return (
    <section className="relative py-20 sm:py-28">
      <div className="mx-auto max-w-6xl px-5">
        <div className="relative overflow-hidden rounded-[2rem] bg-[color:var(--ink)] px-6 py-14 text-white shadow-[var(--shadow-pop)] sm:px-12">
          {/* déco */}
          <div className="pointer-events-none absolute -right-24 -top-24 size-72 rounded-full grad-soft blur-3xl opacity-60" />
          <div className="pointer-events-none absolute -bottom-28 -left-20 size-72 rounded-full grad-soft blur-3xl opacity-40" />

          <div className="relative mx-auto max-w-2xl text-center">
            <span className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-white/80">
              <ShieldCheck className="size-4" />
              Tes données restent chez toi
            </span>
            <h2 className="mt-5 text-3xl font-extrabold tracking-tight text-balance sm:text-4xl">
              Pensé pour ta vie privée, pas pour la revendre
            </h2>
            <p className="mt-4 text-white/70 text-pretty">
              Contrairement aux solutions liées à un cloud, Linkup ne stocke rien
              ailleurs que chez toi. Et le code est ouvert : n’importe qui peut
              vérifier ce qu’il fait.
            </p>
          </div>

          <div className="relative mt-12 grid gap-5 sm:grid-cols-3">
            {POINTS.map((p, i) => (
              <motion.div
                key={p.title}
                initial={{ opacity: 0, y: 18 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: "-60px" }}
                transition={{ duration: 0.5, delay: i * 0.1 }}
                className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm"
              >
                <div className="grid size-11 place-items-center rounded-xl bg-white/10 text-white">
                  <p.icon className="size-5.5" />
                </div>
                <h3 className="mt-4 font-bold">{p.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-white/65">
                  {p.text}
                </p>
              </motion.div>
            ))}
          </div>

          <div className="relative mt-10 text-center">
            <a
              href={SITE.repo}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-xl border border-white/15 bg-white/5 px-5 py-3 text-sm font-semibold text-white transition-colors hover:bg-white/10"
            >
              <Github className="size-4.5" />
              Voir le code source
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
