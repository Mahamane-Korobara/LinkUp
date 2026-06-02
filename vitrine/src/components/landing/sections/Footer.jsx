import { Link2, Github } from "lucide-react";
import { SITE } from "@/lib/site";

const COLS = [
  {
    title: "Produit",
    links: [
      { label: "Le problème", href: "#probleme" },
      { label: "Comment ça marche", href: "#etapes" },
      { label: "Les outils", href: "#outils" },
      { label: "Télécharger", href: "#telecharger" },
    ],
  },
  {
    title: "Ressources",
    links: [
      { label: "Code source", href: SITE.repo, external: true },
      { label: "App Android", href: SITE.androidApk },
      { label: "Programme PC", href: SITE.pcBundle },
    ],
  },
];

export default function Footer() {
  return (
    <footer className="border-t border-zinc-100 bg-white">
      <div className="mx-auto max-w-7xl px-4 py-14 sm:px-6 lg:px-8">
        <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
          <div className="lg:col-span-2">
            <div className="flex items-center gap-2">
              <span className="grid size-10 place-items-center rounded-xl bg-zinc-900 text-white">
                <Link2 className="size-5" strokeWidth={2.5} />
              </span>
              <span className="text-xl font-bold tracking-tight text-zinc-900">
                Linkup
              </span>
            </div>
            <p className="mt-4 max-w-sm text-sm leading-relaxed text-zinc-500">
              Ton téléphone et ton PC, reliés en un scan. Fichiers, photos et
              presse-papier — sans câble, sans compte, sans cloud.
            </p>
            <a
              href={SITE.repo}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-5 inline-flex items-center gap-2 rounded-lg border border-zinc-200 px-3 py-2 text-sm font-medium text-zinc-700 transition-colors hover:bg-zinc-50"
            >
              <Github className="size-4" />
              GitHub
            </a>
          </div>

          {COLS.map((col) => (
            <div key={col.title}>
              <h4 className="text-sm font-bold text-zinc-900">{col.title}</h4>
              <ul className="mt-4 space-y-2.5">
                {col.links.map((l) => (
                  <li key={l.label}>
                    <a
                      href={l.href}
                      {...(l.external
                        ? { target: "_blank", rel: "noopener noreferrer" }
                        : {})}
                      className="text-sm text-zinc-500 transition-colors hover:text-zinc-900"
                    >
                      {l.label}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-12 flex flex-col items-center justify-between gap-3 border-t border-zinc-100 pt-6 text-sm text-zinc-500 sm:flex-row">
          <p>© {new Date().getFullYear()} Linkup · SahelStack</p>
          <p>Gratuit & open source</p>
        </div>
      </div>
    </footer>
  );
}
