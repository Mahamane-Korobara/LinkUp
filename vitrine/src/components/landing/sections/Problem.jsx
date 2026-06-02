"use client";
import Image from "next/image";
import { motion } from "framer-motion";
import { AlertCircle, Sparkles } from "lucide-react";

const SCENES = [
  {
    num: "01",
    name: "Mahamane",
    avatar: dicebear("MahamaneP", { female: false }),
    role: "vient de photographier un tableau",
    quote:
      "12 photos sur mon téléphone, à mettre dans un document sur le PC. Pas de câble. Je finis par me les envoyer par WhatsApp, une par une, en perdant la qualité.",
    outcome: "Une tâche de 10 secondes lui prend 10 minutes.",
    tag: "Photos prisonnières",
  },
  {
    num: "02",
    name: "Aïcha",
    avatar: dicebear("AichaP", { female: true }),
    role: "reçoit un code sur son téléphone",
    quote:
      "Le code de connexion arrive par SMS sur le tél, mais je dois le taper sur le PC. Je le recopie chiffre par chiffre, en me trompant à chaque fois.",
    outcome: "Copier d’un appareil et coller sur l’autre : impossible.",
    tag: "Copier-coller bloqué",
  },
  {
    num: "03",
    name: "Karim",
    avatar: dicebear("KarimL", { female: false }),
    role: "doit passer un fichier au PC",
    quote:
      "Un seul fichier à transférer. Clé USB introuvable, câble jamais le bon, alors je m’envoie un e-mail à moi-même… et j’attends.",
    outcome: "À chaque fois, le même bricolage qui fait perdre du temps.",
    tag: "Le câble introuvable",
  },
];

export default function Problem() {
  return (
    <section id="probleme" className="relative overflow-hidden bg-white py-20 sm:py-28">
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.04]"
        style={{
          backgroundImage: "linear-gradient(to right, #7c3aed 1px, transparent 1px)",
          backgroundSize: "60px 100%",
        }}
      />

      <div className="relative mx-auto max-w-5xl px-4 sm:px-6 lg:px-8">
        <motion.header
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.5 }}
          transition={{ duration: 0.6 }}
          className="mb-14 max-w-2xl sm:mb-20"
        >
          <span className="mb-5 inline-flex items-center gap-2 text-[11px] font-bold uppercase tracking-[0.2em] text-zinc-500">
            <span className="h-px w-8 bg-zinc-300" />
            Le problème
          </span>
          <h2 className="font-heading text-4xl font-black leading-[1.05] tracking-tight text-zinc-900 sm:text-5xl lg:text-[56px]">
            Trois histoires.
            <br />
            <span className="relative inline-block">
              <span className="relative z-10">Tout le monde</span>
              <span className="absolute -bottom-0.5 left-0 right-0 -z-0 h-2.5 rounded-sm bg-violet-200" />
            </span>{" "}
            les a vécues.
          </h2>
        </motion.header>

        <div className="space-y-12 sm:space-y-16">
          {SCENES.map((s, i) => (
            <SceneCard key={s.num} scene={s} reverse={i % 2 === 1} />
          ))}
        </div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.5 }}
          transition={{ duration: 0.6 }}
          className="mt-16 flex items-center justify-center gap-3 text-zinc-500 sm:mt-24"
        >
          <span className="h-px w-12 bg-zinc-300" />
          <Sparkles className="size-4 text-violet-500" />
          <span className="text-sm font-semibold tracking-wide">
            Et si un seul scan suffisait ?
          </span>
          <Sparkles className="size-4 text-violet-500" />
          <span className="h-px w-12 bg-zinc-300" />
        </motion.div>
      </div>
    </section>
  );
}

function SceneCard({ scene, reverse }) {
  return (
    <motion.article
      initial={{ opacity: 0, y: 40 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, amount: 0.3 }}
      transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
      className={`relative flex flex-col gap-6 sm:gap-10 ${
        reverse ? "sm:flex-row-reverse" : "sm:flex-row"
      } items-start`}
    >
      <div className="relative flex shrink-0 flex-row items-center gap-4 sm:w-44 sm:flex-col">
        <div className="relative">
          <span
            className="font-heading block select-none font-black leading-none text-zinc-100"
            style={{ fontSize: "clamp(80px, 14vw, 140px)", letterSpacing: "-0.05em" }}
          >
            {scene.num}
          </span>
          <Image
            src={scene.avatar}
            alt=""
            width={72}
            height={72}
            unoptimized
            className="absolute -bottom-2 -right-2 size-16 rounded-full shadow-lg shadow-violet-200/50 ring-4 ring-white sm:bottom-1 sm:right-1 sm:size-18"
          />
        </div>
      </div>

      <div className="min-w-0 flex-1">
        <div className="mb-3 text-sm font-semibold text-zinc-900">
          <span className="text-violet-700">{scene.name}</span>{" "}
          <span className="font-normal text-zinc-500">{scene.role}.</span>
        </div>

        <blockquote className="font-heading mb-4 border-l-2 border-violet-300 pl-4 text-xl font-bold leading-snug tracking-tight text-zinc-900 sm:pl-5 sm:text-2xl lg:text-[26px]">
          « {scene.quote} »
        </blockquote>

        <p className="mb-5 max-w-xl text-sm leading-relaxed text-zinc-500 sm:text-base">
          {scene.outcome}
        </p>

        <div className="inline-flex items-center gap-2 rounded-full border border-red-100 bg-red-50 px-3 py-1.5 text-[11px] font-bold uppercase tracking-wider text-red-700">
          <AlertCircle className="size-3.5" />
          {scene.tag}
        </div>
      </div>
    </motion.article>
  );
}

function dicebear(seed, { female }) {
  const top = female
    ? "curly,bigHair,fro,bun"
    : "shortCurly,theCaesar,shortFlat,dreads01";
  const facialHair = female ? "0" : "40";
  const skin = female ? "ae5d29" : "5c3317";
  return `https://api.dicebear.com/9.x/avataaars/svg?seed=${encodeURIComponent(
    seed
  )}&skinColor=${skin}&top=${top}&facialHairProbability=${facialHair}&facialHairColor=2c1b18&hairColor=2c1b18&backgroundColor=ede9fe&radius=50`;
}
