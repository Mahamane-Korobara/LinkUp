"use client";
import {
  FileUp,
  ClipboardCheck,
  Link as LinkIcon,
  Images,
  Download,
  FileAudio,
  RefreshCw,
  Webcam,
  Mic,
  Presentation,
  ScanLine,
  Bell,
  Volume2,
  BellRing,
} from "lucide-react";
import { SectionHeading } from "@/components/ui/Section";
import Reveal from "@/components/ui/Reveal";

const GROUPS = [
  {
    title: "Fichiers & contenu",
    items: [
      { icon: FileUp, name: "Transfert de fichiers", desc: "N’importe quel fichier, dans les deux sens. Reprend tout seul si ça coupe." },
      { icon: ClipboardCheck, name: "Presse-papier partagé", desc: "Copie sur un appareil, colle sur l’autre. Textes, liens, codes." },
      { icon: LinkIcon, name: "Lien rapide", desc: "Envoie une page web, elle s’ouvre direct sur le grand écran." },
      { icon: Images, name: "Galerie à distance", desc: "Parcours les photos du tél depuis le PC et récupère celles que tu veux." },
    ],
  },
  {
    title: "Médias",
    items: [
      { icon: Download, name: "Téléchargeur vidéo", desc: "Colle un lien de vidéo, elle se télécharge sur ton PC." },
      { icon: FileAudio, name: "Transcription", desc: "Un audio enregistré devient du texte, automatiquement." },
      { icon: RefreshCw, name: "Conversion", desc: "Change le format d’un fichier : vidéo en audio, image, etc." },
    ],
  },
  {
    title: "Caméra & son",
    items: [
      { icon: Webcam, name: "Caméra du téléphone", desc: "Utilise la caméra de ton tél comme webcam sur le PC (Zoom, Meet…)." },
      { icon: Mic, name: "Micro du téléphone", desc: "Capte un son plus net avec le micro du tél, côté PC." },
      { icon: Presentation, name: "Télécommande slides", desc: "Tourne tes diapos depuis ton téléphone, sans pointeur." },
      { icon: ScanLine, name: "Scanner", desc: "Scanne un QR ou code-barre, le résultat s’affiche sur le PC." },
    ],
  },
  {
    title: "Contrôle du PC",
    items: [
      { icon: Bell, name: "Notifications miroir", desc: "Tes notifs Android s’affichent sur l’écran du PC." },
      { icon: Volume2, name: "Contrôle média", desc: "Play, pause et volume de ton PC pilotés depuis le tél." },
      { icon: BellRing, name: "Faire sonner le tél", desc: "Téléphone perdu dans le canapé ? Fais-le sonner depuis le PC." },
    ],
  },
];

export default function Features() {
  return (
    <section id="outils" className="relative py-20 sm:py-28">
      <div className="mx-auto max-w-6xl px-5">
        <SectionHeading
          eyebrow="La boîte à outils"
          title="Une seule app, 16 outils du quotidien"
          subtitle="Au lieu d’une appli différente pour chaque besoin, Linkup réunit tous les petits ponts utiles entre ton téléphone et ton PC. Tu actives seulement ceux qui te servent."
        />

        <div className="mt-14 space-y-12">
          {GROUPS.map((group) => (
            <div key={group.title}>
              <Reveal>
                <div className="mb-5 flex items-center gap-3">
                  <h3 className="text-sm font-bold uppercase tracking-wider text-[color:var(--primary)]">
                    {group.title}
                  </h3>
                  <span className="h-px flex-1 bg-[color:var(--border)]" />
                  <span className="text-xs font-medium text-[color:var(--muted-foreground)]">
                    {group.items.length} outils
                  </span>
                </div>
              </Reveal>

              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                {group.items.map((item, i) => (
                  <Reveal key={item.name} delay={i * 0.05}>
                    <article className="group h-full rounded-2xl border border-[color:var(--border)] bg-white p-5 shadow-[var(--shadow-card)] transition-all hover:-translate-y-1 hover:border-transparent hover:shadow-[var(--shadow-pop)]">
                      <div className="grid size-10 place-items-center rounded-xl grad-soft text-[color:var(--primary)] transition-colors group-hover:brand-gradient group-hover:text-white">
                        <item.icon className="size-5" />
                      </div>
                      <h4 className="mt-3.5 font-bold leading-snug">{item.name}</h4>
                      <p className="mt-1.5 text-sm leading-relaxed text-[color:var(--muted-foreground)]">
                        {item.desc}
                      </p>
                    </article>
                  </Reveal>
                ))}
              </div>
            </div>
          ))}
        </div>

        <Reveal>
          <p className="mt-12 text-center text-sm text-[color:var(--muted-foreground)]">
            + un terminal sécurisé et un aperçu de tes sites en cours de
            développement, pour les utilisateurs avancés.
          </p>
        </Reveal>
      </div>
    </section>
  );
}
