import { Badge } from "./ui/Badge.jsx";
import { Icon } from "./ui/Icon.jsx";
import { SCOPE_META, SEVERITY_META } from "../lib/constants.js";
import { citationUrl, sentenceCase } from "../lib/format.js";

/**
 * Severity styling.
 *
 * The palette carries six hues and sage does double duty as both the brand
 * accent and the positive signal, so colour alone cannot be trusted to say
 * what a card means. Sage and terracotta sit at 1.12:1 to each other — nearly
 * identical in lightness — which is invisible under red-green colour
 * blindness. Every card therefore states its verdict three ways: a written
 * badge, an icon, and the edge colour. Remove any one and the other two still
 * carry it.
 *
 * The wash is a 40% tint so Deep Forest body copy sits on near-alabaster and
 * clears 4.5:1 comfortably; full-strength hue is reserved for the 4px edge,
 * where no text sits on it.
 */
const TONE = {
  synergy: { edge: "border-l-sage", wash: "bg-sage-100/40" },
  high: { edge: "border-l-terracotta", wash: "bg-terracotta-100/50" },
  medium: { edge: "border-l-clay-600", wash: "bg-clay-100/60" },
  low: { edge: "border-l-clay", wash: "bg-linen/60" },
};

function SeverityBadge({ item }) {
  if (item.interaction_type === "synergy") {
    return (
      <Badge tone="ok" size="sm" icon="spark">
        Synergy
      </Badge>
    );
  }
  const meta = SEVERITY_META[item.severity] ?? SEVERITY_META.low;
  return (
    <Badge tone={meta.tone} size="sm" icon={meta.icon}>
      {meta.label}
    </Badge>
  );
}

export function ResultCard({ item, skinType }) {
  const scope = SCOPE_META[item.scope] ?? { label: item.scope, icon: "link" };
  const sourceUrl = citationUrl(item.source_citation);
  const escalated = item.skin_modifier_applied && item.base_severity !== item.severity;
  const tone = TONE[item.interaction_type === "synergy" ? "synergy" : item.severity] ?? TONE.low;

  return (
    <article
      className={`flex flex-col gap-5 rounded-card border border-stone border-l-4 ${tone.edge} ${tone.wash}
                  p-6 shadow-soft transition-[transform,box-shadow] duration-500 ease-organic
                  hover:-translate-y-1 hover:shadow-lift md:p-8`}
    >
      <header className="flex flex-wrap items-center justify-between gap-3">
        <SeverityBadge item={item} />
        <span className="inline-flex items-center gap-2 font-sans text-2xs uppercase tracking-label text-muted">
          <Icon name={scope.icon} size={13} strokeWidth={1.5} />
          {scope.label}
        </span>
      </header>

      <h4 className="flex flex-wrap items-baseline gap-x-3 font-display text-2xl font-semibold tracking-tight text-forest">
        {item.ingredient_a.inci_name}
        <span className="font-sans text-lg font-normal text-sage" aria-hidden="true">
          +
        </span>
        {item.ingredient_b.inci_name}
      </h4>

      {item.description ? (
        <p className="font-sans text-md leading-relaxed text-subtle">{item.description}</p>
      ) : null}

      {item.mechanism && item.mechanism !== item.description ? (
        <p className="rounded-lg bg-white/70 p-5 font-sans text-sm leading-relaxed text-subtle">
          <span className="mb-1.5 block font-sans text-2xs uppercase tracking-label text-muted">
            Mechanism
          </span>
          {item.mechanism}
        </p>
      ) : null}

      {escalated ? (
        <p className="inline-flex items-start gap-2 rounded-lg bg-clay/40 px-4 py-3 font-sans text-sm text-subtle">
          <Icon name="arrowRight" size={13} strokeWidth={1.5} className="mt-1 shrink-0 text-clay-700" />
          Raised from {item.base_severity} to {item.severity} for {skinType} skin and your selected
          concerns.
        </p>
      ) : null}

      <dl className="grid grid-cols-1 gap-x-8 gap-y-4 border-t border-stone pt-5 sm:grid-cols-3">
        <div className="flex flex-col gap-1.5">
          <dt className="font-sans text-2xs uppercase tracking-label text-muted">Products</dt>
          <dd className="font-sans text-sm text-subtle">
            {item.product_a.label}
            <span className="px-2 text-sage" aria-hidden="true">
              ·
            </span>
            {item.product_b.label}
          </dd>
        </div>
        {item.confidence ? (
          <div className="flex flex-col gap-1.5">
            <dt className="font-sans text-2xs uppercase tracking-label text-muted">Confidence</dt>
            <dd className="font-sans text-sm text-subtle">{sentenceCase(item.confidence)}</dd>
          </div>
        ) : null}
        <div className="flex flex-col gap-1.5">
          <dt className="font-sans text-2xs uppercase tracking-label text-muted">Evidence</dt>
          <dd className="font-sans text-sm text-subtle">
            {sourceUrl ? (
              <a
                className="inline-flex items-center gap-1.5 text-terracotta-700 underline underline-offset-4
                           transition-colors duration-300 hover:text-terracotta focus-visible:outline-none
                           focus-visible:ring-2 focus-visible:ring-sage focus-visible:ring-offset-2"
                href={sourceUrl}
                target="_blank"
                rel="noreferrer noopener"
              >
                {item.source_citation}
                <Icon name="external" size={12} strokeWidth={1.5} />
              </a>
            ) : (
              item.source_citation || "Not cited"
            )}
          </dd>
        </div>
      </dl>
    </article>
  );
}
