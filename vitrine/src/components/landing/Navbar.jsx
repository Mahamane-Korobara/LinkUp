"use client";
import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Link2, Menu, X, ArrowDownToLine } from "lucide-react";

const LINKS = [
  { label: "Le problème", href: "#probleme" },
  { label: "Comment ça marche", href: "#etapes" },
  { label: "Les outils", href: "#outils" },
];

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => {
      const next = window.scrollY > 20;
      setScrolled((prev) => (prev === next ? prev : next));
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <motion.header
      initial={{ y: -100 }}
      animate={{ y: 0 }}
      transition={{ duration: 0.6, ease: [0.22, 1, 0.36, 1] }}
      className={`fixed inset-x-0 top-0 z-50 transition-all duration-500 ${
        scrolled
          ? "border-b border-zinc-100 bg-white/80 shadow-sm backdrop-blur-xl"
          : "bg-transparent"
      }`}
    >
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="flex h-16 items-center justify-between lg:h-20">
          <a href="#" className="group flex items-center gap-2">
            <div className="flex size-10 items-center justify-center rounded-xl bg-zinc-900 shadow-md shadow-zinc-200 transition-transform group-hover:scale-105">
              <Link2 className="size-5 text-white" strokeWidth={2.5} />
            </div>
            <span className="text-xl font-bold tracking-tight text-zinc-900">
              Linkup
            </span>
          </a>

          <nav className="hidden items-center gap-1 lg:flex">
            {LINKS.map((l) => (
              <a
                key={l.label}
                href={l.href}
                className="rounded-lg px-4 py-2 text-sm font-medium text-zinc-500 transition-colors hover:bg-zinc-100/60 hover:text-zinc-900"
              >
                {l.label}
              </a>
            ))}
          </nav>

          <div className="hidden lg:flex">
            <a
              href="#telecharger"
              className="group inline-flex h-11 items-center gap-2 rounded-xl bg-zinc-900 pl-5 pr-2.5 text-sm font-semibold text-white shadow-md shadow-zinc-200 transition-all hover:bg-zinc-800"
            >
              Télécharger
              <span className="flex size-8 items-center justify-center rounded-full bg-violet-500/20 transition-all group-hover:bg-violet-500/40">
                <ArrowDownToLine className="size-4" />
              </span>
            </a>
          </div>

          <button
            className="rounded-xl p-2 text-zinc-600 transition-colors hover:bg-zinc-100 lg:hidden"
            onClick={() => setOpen(!open)}
            aria-label={open ? "Fermer le menu" : "Ouvrir le menu"}
          >
            {open ? <X className="size-6" /> : <Menu className="size-6" />}
          </button>
        </div>
      </div>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            className="overflow-hidden border-b border-zinc-100 bg-white shadow-2xl lg:hidden"
          >
            <div className="space-y-2 px-4 py-6">
              {LINKS.map((l) => (
                <a
                  key={l.label}
                  href={l.href}
                  onClick={() => setOpen(false)}
                  className="block rounded-2xl px-4 py-3 text-lg font-medium text-zinc-600 transition-colors hover:bg-zinc-50 hover:text-zinc-900"
                >
                  {l.label}
                </a>
              ))}
              <a
                href="#telecharger"
                onClick={() => setOpen(false)}
                className="mt-2 flex h-12 items-center justify-center gap-2 rounded-2xl bg-zinc-900 font-bold text-white"
              >
                <ArrowDownToLine className="size-5" /> Télécharger
              </a>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.header>
  );
}
