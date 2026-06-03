"use client";
import { motion } from "framer-motion";
import { Sparkles, ChevronDown } from "lucide-react";
import { FAQ } from "@/lib/faq";

/**
 * Section FAQ — accordéon natif <details> (accessible, contenu toujours dans le
 * DOM donc lisible par Google ET les IA). Le schema FAQPage est dans layout.jsx,
 * alimenté par la même source (@/lib/faq) pour garantir la correspondance.
 */
export default function Faq() {
  return (
    <section id="faq" className="bg-white py-24 sm:py-32">
      <div className="mx-auto max-w-3xl px-4 sm:px-6 lg:px-8">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="mb-12 text-center"
        >
          <span className="mb-5 inline-flex items-center gap-2 rounded-full border border-violet-200 bg-violet-50 px-3 py-1.5 text-[11px] font-bold uppercase tracking-[0.2em] text-violet-600">
            <Sparkles className="size-3" />
            FAQ
          </span>
          <h2 className="font-heading text-3xl font-black tracking-tight text-zinc-900 sm:text-4xl">
            Questions fréquentes
          </h2>
          <p className="mx-auto mt-4 max-w-lg text-base text-zinc-500">
            Tout ce qu’on se demande avant d’installer Linkup.
          </p>
        </motion.div>

        <div className="divide-y divide-zinc-100 rounded-2xl border border-zinc-100 bg-zinc-50/40 px-5 sm:px-7">
          {FAQ.map((item) => (
            <details key={item.q} className="group py-5">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 [&::-webkit-details-marker]:hidden">
                <span className="font-semibold text-zinc-900">{item.q}</span>
                <ChevronDown className="size-5 shrink-0 text-zinc-400 transition-transform duration-300 group-open:rotate-180" />
              </summary>
              <p className="mt-3 pr-8 text-[15px] leading-relaxed text-zinc-600">
                {item.a}
              </p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
