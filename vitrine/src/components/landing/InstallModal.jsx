"use client";
import { useEffect } from "react";
import { AnimatePresence, motion } from "framer-motion";
import {
  X,
  Download,
  MousePointerClick,
  Rocket,
  ShieldCheck,
  Package,
} from "lucide-react";
import { SITE } from "@/lib/site";

/**
 * Modal d'aide à l'installation du PC (AppImage), affiché APRÈS le clic
 * « Télécharger ». Pensé pour un utilisateur lambda : 3 étapes ultra-claires,
 * l'étape clé (rendre exécutable) mise en avant.
 */
const STEPS = [
  {
    icon: Download,
    title: "Le téléchargement démarre",
    body: (
      <>
        Le fichier <code className="rounded bg-zinc-100 px-1.5 py-0.5 font-mono text-[12px] text-zinc-700">Linkup.AppImage</code>{" "}
        arrive dans ton dossier <strong>Téléchargements</strong>.
      </>
    ),
  },
  {
    icon: ShieldCheck,
    title: "Autorise-le à s’ouvrir",
    highlight: true,
    body: (
      <>
        <strong>Clic droit</strong> sur le fichier → <strong>Propriétés</strong> →
        onglet <strong>Permissions</strong> → coche{" "}
        <strong>« Autoriser l’exécution du fichier comme un programme »</strong>.
      </>
    ),
  },
  {
    icon: Rocket,
    title: "Double-clique : c’est lancé",
    body: (
      <>
        Linkup s’ouvre, le tableau de bord apparaît, et une icône{" "}
        <strong>Linkup</strong> s’ajoute à ton menu et à ton bureau. Pour le
        couper : ferme simplement la fenêtre.
      </>
    ),
  },
];

export default function InstallModal({ open, onClose }) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e) => e.key === "Escape" && onClose();
    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [open, onClose]);

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-[100] flex items-center justify-center p-4"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
        >
          <motion.div
            className="absolute inset-0 bg-zinc-950/70 backdrop-blur-sm"
            onClick={onClose}
          />

          <motion.div
            role="dialog"
            aria-modal="true"
            aria-label="Installer Linkup sur ordinateur"
            className="relative w-full max-w-lg overflow-hidden rounded-2xl border border-zinc-200 bg-white shadow-2xl"
            initial={{ opacity: 0, scale: 0.96, y: 14 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.96, y: 14 }}
            transition={{ type: "spring", stiffness: 300, damping: 26 }}
          >
            {/* En-tête */}
            <div className="relative bg-zinc-900 px-6 py-5 text-white">
              <button
                onClick={onClose}
                aria-label="Fermer"
                className="absolute right-4 top-4 grid size-8 place-items-center rounded-lg text-zinc-400 transition-colors hover:bg-white/10 hover:text-white"
              >
                <X className="size-4" />
              </button>
              <span className="inline-flex items-center gap-2 rounded-full border border-violet-400/30 bg-violet-500/15 px-2.5 py-1 text-[11px] font-bold uppercase tracking-wider text-violet-300">
                Linux
              </span>
              <h3 className="mt-3 font-heading text-2xl font-black tracking-tight">
                Installer Linkup
              </h3>
              <p className="mt-1 text-sm text-zinc-400">
                3 étapes, moins d’une minute — aucune compétence requise.
              </p>
            </div>

            {/* Étapes */}
            <div className="space-y-3 px-6 py-6">
              {STEPS.map((s, i) => (
                <div
                  key={s.title}
                  className={`flex gap-4 rounded-xl border p-3.5 ${
                    s.highlight
                      ? "border-violet-200 bg-violet-50/70"
                      : "border-zinc-100 bg-zinc-50/50"
                  }`}
                >
                  <div className="flex flex-col items-center">
                    <span
                      className={`grid size-9 shrink-0 place-items-center rounded-xl text-sm font-black ${
                        s.highlight
                          ? "bg-violet-600 text-white"
                          : "bg-zinc-900 text-white"
                      }`}
                    >
                      {i + 1}
                    </span>
                  </div>
                  <div className="min-w-0 pt-0.5">
                    <div className="flex items-center gap-2">
                      <s.icon
                        className={`size-4 ${s.highlight ? "text-violet-600" : "text-zinc-500"}`}
                      />
                      <p className="font-semibold text-zinc-900">{s.title}</p>
                    </div>
                    <p className="mt-1 text-[13px] leading-relaxed text-zinc-600">
                      {s.body}
                    </p>
                  </div>
                </div>
              ))}
            </div>

            {/* Pied : alternative .deb + fermer */}
            <div className="flex flex-col gap-3 border-t border-zinc-100 bg-zinc-50/60 px-6 py-4 sm:flex-row sm:items-center sm:justify-between">
              <a
                href={SITE.pcDeb}
                download
                className="inline-flex items-center gap-1.5 text-xs font-medium text-zinc-500 underline-offset-4 hover:text-violet-700 hover:underline"
              >
                <Package className="size-3.5" />
                Debian / Ubuntu / Mint : préfère le .deb
              </a>
              <button
                onClick={onClose}
                className="inline-flex items-center justify-center gap-2 rounded-xl bg-violet-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm shadow-violet-200 transition-colors hover:bg-violet-700"
              >
                <MousePointerClick className="size-4" />
                J’ai compris
              </button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
