"use client";
import { Smartphone, Monitor, Download, CheckCircle2 } from "lucide-react";
import { SITE } from "@/lib/site";
import { SectionHeading } from "@/components/ui/Section";
import Reveal from "@/components/ui/Reveal";

export default function DownloadSection() {
  return (
    <section id="telecharger" className="relative py-20 sm:py-28">
      <div className="bg-grid pointer-events-none absolute inset-0 opacity-60" />
      <div className="relative mx-auto max-w-5xl px-5">
        <SectionHeading
          eyebrow="Prêt à relier tes appareils ?"
          title="Installe Linkup, c’est gratuit"
          subtitle="Deux petites installations : l’app sur ton téléphone, le programme sur ton PC. Puis tu scannes, et c’est parti."
        />

        <div className="mt-12 grid gap-6 md:grid-cols-2">
          {/* Téléphone */}
          <Reveal>
            <div className="flex h-full flex-col rounded-2xl border border-[color:var(--border)] bg-white p-7 shadow-[var(--shadow-card)]">
              <div className="flex items-center gap-3">
                <div className="grid size-12 place-items-center rounded-2xl bg-gradient-to-br from-indigo-500 to-violet-500 text-white">
                  <Smartphone className="size-6" />
                </div>
                <div>
                  <h3 className="text-lg font-bold">Sur ton téléphone</h3>
                  <p className="text-sm text-[color:var(--muted-foreground)]">
                    Android 8 ou plus récent
                  </p>
                </div>
              </div>

              <a
                href={SITE.androidApk}
                className="mt-6 inline-flex items-center justify-center gap-2 rounded-xl brand-gradient px-5 py-3.5 font-semibold text-white shadow-[var(--shadow-pop)] transition-transform hover:-translate-y-0.5"
              >
                <Download className="size-5" />
                Télécharger l’app (.apk)
              </a>

              <ul className="mt-5 space-y-2 text-sm text-[color:var(--muted-foreground)]">
                <Step>Ouvre le fichier téléchargé sur ton téléphone</Step>
                <Step>
                  Autorise l’installation si Android le demande (« cette source »)
                </Step>
                <Step>Lance Linkup et appuie sur « Scanner »</Step>
              </ul>
            </div>
          </Reveal>

          {/* PC */}
          <Reveal delay={0.1}>
            <div className="flex h-full flex-col rounded-2xl border border-[color:var(--border)] bg-white p-7 shadow-[var(--shadow-card)]">
              <div className="flex items-center gap-3">
                <div className="grid size-12 place-items-center rounded-2xl bg-gradient-to-br from-sky-500 to-cyan-400 text-white">
                  <Monitor className="size-6" />
                </div>
                <div>
                  <h3 className="text-lg font-bold">Sur ton ordinateur</h3>
                  <p className="text-sm text-[color:var(--muted-foreground)]">
                    Windows 10/11 · Linux
                  </p>
                </div>
              </div>

              <div className="mt-6 grid grid-cols-2 gap-3">
                <a
                  href={SITE.pcWindows}
                  className="inline-flex items-center justify-center gap-2 rounded-xl border border-[color:var(--border)] bg-white px-4 py-3.5 text-sm font-semibold transition-colors hover:bg-[color:var(--muted)]"
                >
                  <Monitor className="size-4.5 text-[color:var(--primary)]" />
                  Windows
                  <span className="text-[10px] font-bold text-[color:var(--accent)]">
                    bientôt
                  </span>
                </a>
                <a
                  href={SITE.pcLinux}
                  className="inline-flex items-center justify-center gap-2 rounded-xl border border-[color:var(--border)] bg-white px-4 py-3.5 text-sm font-semibold transition-colors hover:bg-[color:var(--muted)]"
                >
                  <Monitor className="size-4.5 text-[color:var(--primary)]" />
                  Linux
                </a>
              </div>

              <ul className="mt-5 space-y-2 text-sm text-[color:var(--muted-foreground)]">
                <Step>Décompresse le dossier téléchargé</Step>
                <Step>Lance Linkup — un QR code s’affiche</Step>
                <Step>Rien d’autre à installer sur ton PC</Step>
              </ul>
            </div>
          </Reveal>
        </div>

        <Reveal>
          <p className="mt-8 text-center text-sm text-[color:var(--muted-foreground)]">
            Besoin d’une autre version ?{" "}
            <a
              href={SITE.releases}
              target="_blank"
              rel="noopener noreferrer"
              className="font-semibold text-[color:var(--primary)] underline-offset-4 hover:underline"
            >
              Toutes les versions sur GitHub
            </a>
          </p>
        </Reveal>
      </div>
    </section>
  );
}

function Step({ children }) {
  return (
    <li className="flex items-start gap-2">
      <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-[color:var(--primary)]" />
      <span>{children}</span>
    </li>
  );
}
