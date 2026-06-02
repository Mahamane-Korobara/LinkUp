"use client";
import { motion } from "framer-motion";
import type { LucideIcon } from "lucide-react";

export function PageHeader({
  icon: Icon,
  title,
  subtitle,
  action,
}: {
  icon: LucideIcon;
  title: string;
  subtitle?: string;
  action?: React.ReactNode;
}) {
  return (
    <motion.header
      initial={{ opacity: 0, y: -8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4 }}
      className="mb-6 flex items-start justify-between gap-4"
    >
      <div className="flex items-start gap-3.5">
        <span className="grid size-11 shrink-0 place-items-center rounded-2xl bg-violet-600 text-white shadow-sm shadow-violet-200">
          <Icon className="size-5.5" />
        </span>
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">
            {title}
          </h1>
          {subtitle && (
            <p className="mt-0.5 max-w-xl text-sm text-zinc-500">{subtitle}</p>
          )}
        </div>
      </div>
      {action}
    </motion.header>
  );
}
