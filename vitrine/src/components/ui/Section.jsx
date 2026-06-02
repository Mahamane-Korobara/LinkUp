import Reveal from "./Reveal";

/** En-tête de section réutilisable : pastille + titre + sous-titre. */
export function SectionHeading({ eyebrow, title, subtitle, center = true }) {
  return (
    <Reveal>
      <div className={center ? "mx-auto max-w-2xl text-center" : "max-w-2xl"}>
        {eyebrow && (
          <span className="inline-flex items-center gap-2 rounded-full border border-[color:var(--border)] bg-white px-3 py-1 text-xs font-semibold tracking-wide text-[color:var(--primary)] uppercase">
            {eyebrow}
          </span>
        )}
        <h2 className="mt-4 text-3xl font-extrabold tracking-tight text-balance sm:text-4xl md:text-[2.6rem] md:leading-[1.1]">
          {title}
        </h2>
        {subtitle && (
          <p className="mt-4 text-base text-[color:var(--muted-foreground)] text-pretty sm:text-lg">
            {subtitle}
          </p>
        )}
      </div>
    </Reveal>
  );
}
