import * as React from "react";
import { cn } from "@/lib/utils";

export function Card({
  className,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        // Hairline quasi invisible (zinc-100) + ombre diffuse : c'est l'ombre
        // qui détache la carte du fond, pas une bordure 1px sèche (effet
        // wireframe). Aligné sur l'AppCard mobile.
        "rounded-2xl border border-zinc-100 bg-white shadow-card",
        className
      )}
      {...props}
    />
  );
}
