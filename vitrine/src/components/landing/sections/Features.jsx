"use client";
import { motion } from "framer-motion";
import {
  FileUp,
  ClipboardCheck,
  Images,
  MonitorSmartphone,
  Smartphone,
  Sparkles,
  Check,
  Link as LinkIcon,
  Webcam,
  Mic,
  Download,
  FileAudio,
  RefreshCw,
  Presentation,
  ScanLine,
  Bell,
  Volume2,
  BellRing,
} from "lucide-react";

// Les outils réellement disponibles aujourd'hui (alpha LAN).
const AVAILABLE = [
  {
    icon: FileUp,
    title: "Transfert de fichiers",
    text: "Envoie n’importe quel fichier du téléphone vers le PC et inversement. Le transfert reprend tout seul si la connexion coupe.",
    points: ["Dans les deux sens", "Reprise automatique", "Plusieurs fichiers"],
  },
  {
    icon: ClipboardCheck,
    title: "Presse-papier partagé",
    text: "Tu copies un texte, un lien ou un code sur un appareil — tu le colles sur l’autre. Fini de recopier à la main.",
    points: ["Texte, liens, codes", "Tél → PC et PC → tél", "Historique récent"],
  },
  {
    icon: Images,
    title: "Galerie à distance",
    text: "Parcours les photos et vidéos de ton téléphone depuis le PC, et récupère exactement celles que tu veux, en pleine qualité.",
    points: ["Qualité d’origine", "Sélection multiple", "Aperçu rapide"],
  },
  {
    icon: Smartphone,
    title: "De téléphone à téléphone",
    text: "Pas de PC sous la main ? Un téléphone devient le point de partage, l’autre scanne son QR — et vous échangez fichiers, photos et vidéos directement.",
    points: ["Sans aucun PC", "Un scan pour relier", "Fichiers, photos, vidéos"],
  },
  {
    icon: MonitorSmartphone,
    title: "Aperçu de dev sur le téléphone",
    text: "Tu développes un site ou une app sur ton PC ? Ouvre-le tel quel sur ton téléphone, en vrai HTTPS de confiance — sans rien installer.",
    points: ["Le localhost du PC sur le tél", "Caméra, micro & géoloc actifs", "Zéro certificat à installer"],
  },
  {
    icon: Download,
    title: "Téléchargeur vidéo",
    text: "Colle le lien d’une vidéo (YouTube, TikTok, Instagram, X…) : aperçu, puis télécharge-la en vidéo ou en audio, et partage le fichier. Aucun PC nécessaire.",
    points: ["YouTube, TikTok, Insta, X…", "Vidéo ou audio (MP3)", "Marche sans PC"],
  },
  {
    icon: FileAudio,
    title: "Transcription IA",
    text: "Transforme la parole d’une vidéo en texte bien mis en forme — même sans sous-titres, l’IA écoute l’audio — puis exporte le document en PDF.",
    points: ["Même sans sous-titres", "Document soigné → PDF", "Garde la langue d’origine"],
  },
];

// Outils prévus, pas encore disponibles.
const SOON = [
  { icon: LinkIcon, label: "Lien rapide" },
  { icon: Webcam, label: "Caméra webcam" },
  { icon: Mic, label: "Micro du tél" },
  { icon: RefreshCw, label: "Conversion" },
  { icon: Presentation, label: "Télécommande slides" },
  { icon: ScanLine, label: "Scanner" },
  { icon: Bell, label: "Notifs miroir" },
  { icon: Volume2, label: "Contrôle média" },
  { icon: BellRing, label: "Faire sonner le tél" },
];

export default function Features() {
  return (
    <section id="outils" className="relative overflow-hidden bg-white py-20 sm:py-28">
      <div className="relative mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
        <motion.header
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.4 }}
          transition={{ duration: 0.6 }}
          className="mb-14 max-w-2xl"
        >
          <span className="mb-5 inline-flex items-center gap-2 text-[11px] font-bold uppercase tracking-[0.2em] text-zinc-500">
            <span className="h-px w-8 bg-zinc-300" />
            Les outils
          </span>
          <h2 className="font-heading text-4xl font-black leading-[1.05] tracking-tight text-zinc-900 sm:text-5xl lg:text-[56px]">
            Ce que tu peux faire{" "}
            <span className="relative inline-block">
              <span className="relative z-10">dès aujourd’hui.</span>
              <span className="absolute -bottom-0.5 left-0 right-0 -z-0 h-2.5 rounded-sm bg-violet-200" />
            </span>
          </h2>
          <p className="mt-5 text-base leading-relaxed text-zinc-500 sm:text-lg">
            Linkup réunit les ponts les plus utiles entre ton téléphone et ton
            PC — et même entre deux téléphones. Plus des outils qui marchent
            seuls, sans aucun PC. Tout est disponible aujourd’hui.
          </p>
        </motion.header>

        {/* Disponible maintenant */}
        <div className="mb-6 flex items-center gap-3">
          <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-3 py-1 text-[11px] font-bold uppercase tracking-wider text-emerald-700">
            <span className="size-1.5 rounded-full bg-emerald-500" />
            Disponible maintenant
          </span>
          <span className="h-px flex-1 bg-zinc-100" />
        </div>

        <div className="grid gap-5 md:grid-cols-3">
          {AVAILABLE.map((f, i) => (
            <motion.article
              key={f.title}
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, amount: 0.3 }}
              transition={{ duration: 0.55, delay: i * 0.1 }}
              className="group relative flex h-full flex-col overflow-hidden rounded-3xl border border-zinc-200 bg-white p-6 shadow-card transition-all hover:-translate-y-1 hover:shadow-pop sm:p-7"
            >
              <div className="mb-5 flex size-12 items-center justify-center rounded-2xl bg-zinc-900 text-white transition-colors group-hover:bg-violet-600">
                <f.icon className="size-6" strokeWidth={2} />
              </div>
              <h3 className="font-heading text-xl font-black tracking-tight text-zinc-900">
                {f.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-zinc-500">
                {f.text}
              </p>
              <ul className="mt-5 space-y-2 border-t border-zinc-100 pt-5">
                {f.points.map((p) => (
                  <li key={p} className="flex items-center gap-2 text-[13px] font-medium text-zinc-700">
                    <span className="grid size-4.5 place-items-center rounded-full bg-violet-100 text-violet-700">
                      <Check className="size-3" strokeWidth={3} />
                    </span>
                    {p}
                  </li>
                ))}
              </ul>
            </motion.article>
          ))}
        </div>

        {/* Bientôt */}
        <div className="mb-6 mt-16 flex items-center gap-3">
          <span className="inline-flex items-center gap-1.5 rounded-full bg-violet-50 px-3 py-1 text-[11px] font-bold uppercase tracking-wider text-violet-700">
            <Sparkles className="size-3" />
            Bientôt
          </span>
          <span className="h-px flex-1 bg-zinc-100" />
        </div>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.2 }}
          transition={{ duration: 0.5 }}
          className="rounded-3xl border border-dashed border-zinc-200 bg-zinc-50/60 p-6 sm:p-8"
        >
          <p className="mb-5 max-w-2xl text-sm text-zinc-500">
            La boîte à outils s’agrandit : caméra de ton téléphone en webcam,
            micro déporté, conversion de fichiers, notifications du tél sur le
            PC, et plus encore. Ces outils arrivent au fil des mises à jour.
          </p>
          <div className="flex flex-wrap gap-2.5">
            {SOON.map((s) => (
              <span
                key={s.label}
                className="inline-flex items-center gap-2 rounded-full border border-zinc-200 bg-white px-3.5 py-2 text-[13px] font-medium text-zinc-600"
              >
                <s.icon className="size-4 text-zinc-400" />
                {s.label}
              </span>
            ))}
          </div>
        </motion.div>
      </div>
    </section>
  );
}
