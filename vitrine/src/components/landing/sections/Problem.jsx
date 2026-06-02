"use client";
import { Cable, Send, ImageOff, Camera, Presentation } from "lucide-react";
import { SectionHeading } from "@/components/ui/Section";
import Reveal from "@/components/ui/Reveal";

const SCENES = [
  {
    icon: ImageOff,
    title: "Les photos prisonnières du tel",
    text: "12 photos d’un tableau à récupérer sur le PC. Sans câble, tu finis par te les envoyer par WhatsApp… une par une, en perdant la qualité.",
  },
  {
    icon: Send,
    title: "Le lien qu’on retape à la main",
    text: "Un article trouvé sur le téléphone, à ouvrir sur le grand écran. Tu retapes l’URL à la main — avec deux fautes de frappe.",
  },
  {
    icon: Camera,
    title: "La webcam cassée",
    text: "Un appel vidéo depuis le PC, mais la webcam est morte. Ton téléphone a une super caméra… qu’aucun logiciel ne sait utiliser simplement.",
  },
  {
    icon: Cable,
    title: "Le câble qu’on ne trouve jamais",
    text: "Un fichier à passer du tel au PC. Clé USB, câble introuvable, e-mail à soi-même : à chaque fois, le même bricolage.",
  },
  {
    icon: Presentation,
    title: "La présentation sans pointeur",
    text: "Tu présentes un PDF en réunion et tu voudrais tourner les diapos depuis ton téléphone, sans courir vers le clavier.",
  },
];

export default function Problem() {
  return (
    <section id="probleme" className="relative py-20 sm:py-28">
      <div className="mx-auto max-w-6xl px-5">
        <SectionHeading
          eyebrow="Ça vous parle ?"
          title="On connaît tous ces petites galères"
          subtitle="Faire passer un fichier, un lien ou une photo entre son téléphone et son PC reste étonnamment pénible. Linkup remplace tous ces bricolages par un seul geste."
        />

        <div className="mt-14 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {SCENES.map((s, i) => (
            <Reveal key={s.title} delay={i * 0.07}>
              <article className="group h-full rounded-2xl border border-[color:var(--border)] bg-white p-6 shadow-[var(--shadow-card)] transition-all hover:-translate-y-1 hover:shadow-[var(--shadow-pop)]">
                <div className="grid size-11 place-items-center rounded-xl grad-soft text-[color:var(--primary)] transition-colors group-hover:brand-gradient group-hover:text-white">
                  <s.icon className="size-5.5" />
                </div>
                <h3 className="mt-4 text-lg font-bold">{s.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-[color:var(--muted-foreground)]">
                  {s.text}
                </p>
              </article>
            </Reveal>
          ))}

          <Reveal delay={SCENES.length * 0.07}>
            <article className="flex h-full flex-col justify-center rounded-2xl brand-gradient p-6 text-white shadow-[var(--shadow-pop)]">
              <h3 className="text-xl font-extrabold leading-snug text-balance">
                Et si tout ça tenait dans un seul scan&nbsp;?
              </h3>
              <p className="mt-2 text-sm text-white/85">
                C’est exactement ce que fait Linkup. Découvre comment juste en
                dessous.
              </p>
            </article>
          </Reveal>
        </div>
      </div>
    </section>
  );
}
