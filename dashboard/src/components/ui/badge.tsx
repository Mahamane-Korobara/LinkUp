import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-semibold",
  {
    variants: {
      tone: {
        amber: "bg-amber-100 text-amber-800",
        green: "bg-emerald-100 text-emerald-700",
        red: "bg-red-100 text-red-700",
        violet: "bg-violet-100 text-violet-700",
        zinc: "bg-zinc-100 text-zinc-600",
      },
    },
    defaultVariants: { tone: "zinc" },
  }
);

export function Badge({
  className,
  tone,
  ...props
}: React.HTMLAttributes<HTMLSpanElement> & VariantProps<typeof badgeVariants>) {
  return <span className={cn(badgeVariants({ tone }), className)} {...props} />;
}
