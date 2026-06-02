"use client";
import { useEffect, useState } from "react";
import { Link2, Download, Menu, X } from "lucide-react";
import { SITE } from "@/lib/site";

const LINKS = [
  { href: "#probleme", label: "Le problème" },
  { href: "#etapes", label: "Comment ça marche" },
  { href: "#outils", label: "Les outils" },
  { href: "#telecharger", label: "Télécharger" },
];

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      className={`fixed inset-x-0 top-0 z-40 transition-all duration-300 ${
        scrolled
          ? "border-b border-[color:var(--border)] bg-white/80 backdrop-blur-xl"
          : "bg-transparent"
      }`}
    >
      <nav className="mx-auto flex h-16 max-w-6xl items-center justify-between px-5">
        <a href="#" className="flex items-center gap-2 font-extrabold tracking-tight">
          <span className="brand-gradient grid size-8 place-items-center rounded-xl text-white shadow-[var(--shadow-card)]">
            <Link2 className="size-4.5" strokeWidth={2.5} />
          </span>
          <span className="text-lg">Linkup</span>
        </a>

        <div className="hidden items-center gap-1 md:flex">
          {LINKS.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="rounded-lg px-3 py-2 text-sm font-medium text-[color:var(--muted-foreground)] transition-colors hover:bg-[color:var(--muted)] hover:text-[color:var(--foreground)]"
            >
              {l.label}
            </a>
          ))}
        </div>

        <div className="flex items-center gap-2">
          <a
            href="#telecharger"
            className="hidden items-center gap-2 rounded-xl brand-gradient px-4 py-2.5 text-sm font-semibold text-white shadow-[var(--shadow-card)] transition-transform hover:-translate-y-0.5 active:translate-y-0 sm:inline-flex"
          >
            <Download className="size-4" />
            Télécharger
          </a>
          <button
            onClick={() => setOpen((v) => !v)}
            className="grid size-10 place-items-center rounded-xl border border-[color:var(--border)] bg-white md:hidden"
            aria-label="Menu"
          >
            {open ? <X className="size-5" /> : <Menu className="size-5" />}
          </button>
        </div>
      </nav>

      {open && (
        <div className="border-t border-[color:var(--border)] bg-white md:hidden">
          <div className="mx-auto flex max-w-6xl flex-col px-5 py-2">
            {LINKS.map((l) => (
              <a
                key={l.href}
                href={l.href}
                onClick={() => setOpen(false)}
                className="rounded-lg px-3 py-3 text-sm font-medium text-[color:var(--muted-foreground)]"
              >
                {l.label}
              </a>
            ))}
            <a
              href={SITE.androidApk}
              onClick={() => setOpen(false)}
              className="mt-1 mb-2 inline-flex items-center justify-center gap-2 rounded-xl brand-gradient px-4 py-3 text-sm font-semibold text-white"
            >
              <Download className="size-4" /> Télécharger l’app
            </a>
          </div>
        </div>
      )}
    </header>
  );
}
