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
      { label: "Code source", href: SITE.repo },
      { label: "Versions", href: SITE.releases },
    ],
  },
];

export default function Footer() {
  return (
    <footer className="border-t border-[color:var(--border)] bg-white">
      <div className="mx-auto max-w-6xl px-5 py-14">
        <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
          <div className="lg:col-span-2">
            <a href="#" className="flex items-center gap-2 font-extrabold">
              <span className="brand-gradient grid size-8 place-items-center rounded-xl text-white">
                <Link2 className="size-4.5" strokeWidth={2.5} />
              </span>
              <span className="text-lg">Linkup</span>
            </a>
            <p className="mt-4 max-w-sm text-sm text-[color:var(--muted-foreground)]">
              Ton téléphone et ton PC, reliés en un scan. Fichiers, photos, liens
              et bien plus — sans câble, sans compte, sans cloud.
            </p>
            <a
              href={SITE.repo}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-5 inline-flex items-center gap-2 rounded-lg border border-[color:var(--border)] px-3 py-2 text-sm font-medium transition-colors hover:bg-[color:var(--muted)]"
            >
              <Github className="size-4" />
              GitHub
            </a>
          </div>

          {COLS.map((col) => (
            <div key={col.title}>
              <h4 className="text-sm font-bold">{col.title}</h4>
              <ul className="mt-4 space-y-2.5">
                {col.links.map((l) => (
                  <li key={l.label}>
                    <a
                      href={l.href}
                      className="text-sm text-[color:var(--muted-foreground)] transition-colors hover:text-[color:var(--foreground)]"
                    >
                      {l.label}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-12 flex flex-col items-center justify-between gap-3 border-t border-[color:var(--border)] pt-6 text-sm text-[color:var(--muted-foreground)] sm:flex-row">
          <p>© {new Date().getFullYear()} Linkup · SahelStack</p>
          <p>Fait avec soin — gratuit & open source</p>
        </div>
      </div>
    </footer>
  );
}
