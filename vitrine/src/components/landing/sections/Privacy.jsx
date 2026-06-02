"use client";
import { motion } from "framer-motion";
import { WifiOff, UserX, Lock, Github } from "lucide-react";
import { SITE } from "@/lib/site";

const POINTS = [
  {
    icon: WifiOff,
    title: "Tout passe par ton réseau",
    text: "Tes fichiers voyagent directement d’un appareil à l’autre sur ton Wi-Fi. Ils ne partent sur aucun serveur lointain.",
  },
  {
    icon: UserX,
    title: "Aucun compte à créer",
    text: "Pas d’e-mail, pas de mot de passe, pas de profil. Tu installes, tu scannes, c’est tout.",
  },
  {
    icon: Lock,
    title: "Liaison approuvée et chiffrée",
    text: "Chaque appareil doit être approuvé sur ton PC avant de se connecter, et la liaison est chiffrée de bout en bout.",
  },
];

export default function Privacy() {
  return (
    <section className="relative overflow-hidden bg-white py-20 sm:py-28">
      <div className="relative mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
        <div className="grid items-start gap-12 lg:grid-cols-[0.9fr_1.1fr] lg:gap-16">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, amount: 0.4 }}
            transition={{ duration: 0.6 }}
          >
            <span className="mb-5 inline-flex items-center gap-2 text-[11px] font-bold uppercase tracking-[0.2em] text-zinc-500">
              <span className="h-px w-8 bg-zinc-300" />
              Ta vie privée
            </span>
            <h2 className="font-heading text-4xl font-black leading-[1.05] tracking-tight text-zinc-900 sm:text-5xl">
              Tes données
              <br />
              <span className="relative inline-block">
                <span className="relative z-10">restent chez toi.</span>
                <span className="absolute -bottom-0.5 left-0 right-0 -z-0 h-2.5 rounded-sm bg-violet-200" />
              </span>
            </h2>
            <p className="mt-5 max-w-md text-base leading-relaxed text-zinc-500">
              Contrairement aux solutions liées à un cloud, Linkup ne stocke rien
              ailleurs que chez toi. Et le code est ouvert : n’importe qui peut
              vérifier ce qu’il fait.
            </p>
            <a
              href={SITE.repo}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-7 inline-flex items-center gap-2 rounded-xl border border-zinc-200 bg-white px-5 py-3 text-sm font-semibold text-zinc-900 shadow-card transition-colors hover:bg-zinc-50"
            >
              <Github className="size-4.5" />
              Voir le code source
            </a>
          </motion.div>

          <div className="space-y-4">
            {POINTS.map((p, i) => (
              <motion.div
                key={p.title}
                initial={{ opacity: 0, x: 24 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true, amount: 0.3 }}
                transition={{ duration: 0.55, delay: i * 0.1 }}
                className="flex items-start gap-4 rounded-2xl border border-zinc-200 bg-white p-5 shadow-card sm:p-6"
              >
                <span className="grid size-12 shrink-0 place-items-center rounded-2xl bg-violet-50 text-violet-700 ring-1 ring-violet-100">
                  <p.icon className="size-5.5" />
                </span>
                <div>
                  <h3 className="font-heading text-lg font-black tracking-tight text-zinc-900">
                    {p.title}
                  </h3>
                  <p className="mt-1 text-sm leading-relaxed text-zinc-500">
                    {p.text}
                  </p>
                </div>
              </motion.div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
