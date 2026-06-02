"use client";
import { motion } from "framer-motion";
import { TriangleAlert, type LucideIcon } from "lucide-react";

export function ErrorBanner({ message, base }: { message: string; base?: string }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: -6 }}
      animate={{ opacity: 1, y: 0 }}
      className="mb-4 flex items-start gap-3 rounded-xl border border-red-200 bg-red-50 p-3.5 text-sm text-red-700"
    >
      <TriangleAlert className="mt-0.5 size-4.5 shrink-0" />
      <div>
        <p className="font-medium">{message}</p>
        {base && (
          <p className="mt-0.5 text-xs text-red-500">
            L’agent Laravel doit tourner sur <code className="font-mono">{base}</code>.
          </p>
        )}
      </div>
    </motion.div>
  );
}

export function EmptyState({
  icon: Icon,
  children,
}: {
  icon: LucideIcon;
  children: React.ReactNode;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.98 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.4 }}
      className="flex flex-col items-center justify-center gap-3 rounded-2xl border border-dashed border-zinc-300 bg-white/60 px-6 py-16 text-center"
    >
      <span className="grid size-12 place-items-center rounded-2xl bg-zinc-100 text-zinc-400">
        <Icon className="size-6" />
      </span>
      <p className="max-w-sm text-sm text-zinc-500">{children}</p>
    </motion.div>
  );
}
