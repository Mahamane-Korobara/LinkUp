"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import {
  QrCode,
  Smartphone,
  Inbox,
  SendHorizontal,
  ClipboardList,
  Globe,
  Link2,
  Menu,
  X,
  type LucideIcon,
} from "lucide-react";

import { LARAVEL_BASE } from "@/lib/api";
import { cn } from "@/lib/utils";

type NavItem = { href: string; label: string; icon: LucideIcon };

const NAV: NavItem[] = [
  { href: "/pair", label: "Appairer", icon: QrCode },
  { href: "/devices", label: "Téléphones", icon: Smartphone },
  { href: "/files", label: "Fichiers reçus", icon: Inbox },
  { href: "/send", label: "Envoyer", icon: SendHorizontal },
  { href: "/clipboard", label: "Presse-papier", icon: ClipboardList },
  { href: "/preview", label: "Dev Preview", icon: Globe },
];

/** Ping périodique de l'agent local → état de connexion. */
function useAgentStatus() {
  const [online, setOnline] = useState<boolean | null>(null);
  useEffect(() => {
    let active = true;
    const ping = async () => {
      try {
        const res = await fetch(`${LARAVEL_BASE}/api/health`, {
          cache: "no-store",
        });
        if (active) setOnline(res.ok);
      } catch {
        if (active) setOnline(false);
      }
    };
    ping();
    const id = setInterval(ping, 5000);
    return () => {
      active = false;
      clearInterval(id);
    };
  }, []);
  return online;
}

function Logo() {
  return (
    <Link href="/devices" className="flex items-center gap-2.5">
      <span className="grid size-9 place-items-center rounded-xl bg-zinc-900 text-white">
        <Link2 className="size-5" strokeWidth={2.5} />
      </span>
      <span className="text-lg font-bold tracking-tight text-zinc-900">
        Linkup
      </span>
    </Link>
  );
}

function StatusPill({ online }: { online: boolean | null }) {
  const meta =
    online === null
      ? { dot: "bg-zinc-300", text: "Connexion…", cls: "text-zinc-500" }
      : online
        ? { dot: "bg-emerald-500", text: "Agent connecté", cls: "text-emerald-700" }
        : { dot: "bg-red-500", text: "Agent hors ligne", cls: "text-red-600" };
  return (
    <div className="flex items-center gap-2 rounded-xl border border-zinc-200 bg-white px-3 py-2 text-xs font-medium">
      <span className="relative flex size-2">
        {online && (
          <span className="absolute inline-flex size-2 animate-ping rounded-full bg-emerald-400 opacity-75" />
        )}
        <span className={cn("relative inline-flex size-2 rounded-full", meta.dot)} />
      </span>
      <span className={meta.cls}>{meta.text}</span>
    </div>
  );
}

function NavLinks({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  return (
    <nav className="flex flex-col gap-1">
      {NAV.map((item) => {
        const active = pathname === item.href;
        return (
          <Link
            key={item.href}
            href={item.href}
            onClick={onNavigate}
            className={cn(
              "group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-colors",
              active
                ? "bg-violet-600 text-white shadow-sm shadow-violet-200"
                : "text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900"
            )}
          >
            <item.icon
              className={cn(
                "size-4.5",
                active ? "text-white" : "text-zinc-400 group-hover:text-zinc-600"
              )}
            />
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const online = useAgentStatus();
  const [open, setOpen] = useState(false);

  return (
    <div className="min-h-screen lg:pl-64">
      {/* Sidebar desktop */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-64 flex-col border-r border-zinc-200 bg-white px-4 py-5 lg:flex">
        <div className="px-2">
          <Logo />
        </div>
        <div className="mt-8 flex-1">
          <p className="mb-2 px-3 text-[11px] font-bold uppercase tracking-wider text-zinc-400">
            Outils
          </p>
          <NavLinks />
        </div>
        <StatusPill online={online} />
      </aside>

      {/* Topbar mobile */}
      <header className="sticky top-0 z-30 flex h-14 items-center justify-between border-b border-zinc-200 bg-white/80 px-4 backdrop-blur-xl lg:hidden">
        <Logo />
        <div className="flex items-center gap-2">
          <StatusPill online={online} />
          <button
            onClick={() => setOpen((v) => !v)}
            className="grid size-10 place-items-center rounded-xl border border-zinc-200 text-zinc-600"
            aria-label="Menu"
          >
            {open ? <X className="size-5" /> : <Menu className="size-5" />}
          </button>
        </div>
      </header>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            className="overflow-hidden border-b border-zinc-200 bg-white px-4 py-3 lg:hidden"
          >
            <NavLinks onNavigate={() => setOpen(false)} />
          </motion.div>
        )}
      </AnimatePresence>

      <main className="mx-auto max-w-3xl px-5 py-8 sm:px-8">{children}</main>
    </div>
  );
}
