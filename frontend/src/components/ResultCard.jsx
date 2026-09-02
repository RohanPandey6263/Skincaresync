import { Badge } from "./ui/Badge.jsx";
import { Icon } from "./ui/Icon.jsx";
import { SCOPE_META, SEVERITY_META } from "../lib/constants.js";
import { citationUrl, sentenceCase } from "../lib/format.js";

/**
 * Every finding states its verdict three ways: a written badge, a symbol, and
 * a surface treatment. Conflicts get the red edge, the only red on the card.
 * Cautions are hatched; synergies carry the dot matrix. Remove any one channel
 * and the other two still carry the meaning.
 */
const SEVERITY_RANK = { low: 1, medium: 2, high: 3 };

const SURFACE = {
  synergy: { edge: "bg-black", card: "swiss-dots" },
  high: { edge: "bg-accent", card: "" },
  medium: { edge: "bg-black", card: "swiss-diagonal" },
  low: { edge: "bg-black", card: "swiss-diagonal" },
};

function SeverityBadge({ item }) {
  if (item.interaction_type === "synergy") {
    return (
      <Badge tone="ok" icon="spark">
        Synergy
      </Badge>
    );
  }
  const meta = SEVERITY_META[item.severity] ?? SEVERITY_META.low;
  const tone = item.interaction_type === "conflict" && item.severity === "high" ? "danger" : item.interaction_type === "conflict" ? "danger" : meta.tone === "danger" ? "warn" : meta.tone;
  return (
    <Badge tone={tone} icon={meta.icon}>
      {item.interaction_type === "redundant" ? "Redundant" : sentenceCase(item.interaction_type)} · {meta.label}
    </Badge>
  );
}

export function ResultCard({ item, skinType }) {
  const scope = SCOPE_META[item.scope] ?? { label: item.scope, icon: "link" };
  const sourceUrl = citationUrl(item.source_citation);
  const escalated = item.skin_modifier_applied && item.base_severity !== item.severity;
  const key = item.interaction_type === "synergy" ? "synergy" : item.interaction_type === "conflict" ? "high" : item.severity;
  const surface = SURFACE[key] ?? SURFACE.low;

  return (
    <article className={`relative flex flex-col gap-6 border-2 border-black bg-white p-6 pl-8 md:p-8 md:pl-10 ${surface.card}`}>
      <span className={`absolute inset-y-0 left-0 w-2 ${surface.edge}`} aria-hidden="true" />

      <header className="flex flex-wrap items-center justify-between gap-3">
        <SeverityBadge item={item} />
        <span className="inline-flex items-center gap-2 font-sans text-2xs label-caps text-black">
          <Icon name={scope.icon} size={14} strokeWidth={2.5} />
          {scope.label}
        </span>
      </header>

      <h4 className="font-sans text-2xl font-black uppercase leading-none tracking-tighter text-black md:text-3xl">
        {item.ingredient_a.inci_name}
        <span className="mx-3 text-accent" aria-hidden="true">
          +
        </span>
        <span className="sr-only">with</span>
        {item.ingredient_b.inci_name}
      </h4>

      {item.description ? <p className="max-w-[64ch] font-sans text-base leading-relaxed text-black">{item.description}</p> : null}

      {item.mechanism && item.mechanism !== item.description ? (
        <div className="flex flex-col gap-2 border-l-4 border-black bg-white/70 py-1 pl-4">
          <p className="font-sans text-2xs label-caps text-black/60">Mechanism</p>
          <p className="font-sans text-sm leading-relaxed text-black">{item.mechanism}</p>
        </div>
      ) : null}

      {escalated ? (
        <p className="flex items-start gap-3 border-l-4 border-accent py-1 pl-4 font-sans text-sm text-black">
          <Icon name="arrowUpRight" size={14} strokeWidth={2.5} className="mt-1 shrink-0 text-accent-text" />
          {SEVERITY_RANK[item.severity] > SEVERITY_RANK[item.base_severity] ? "Raised" : "Lowered"} from {item.base_severity} to{" "}
          {item.severity} for {skinType} skin and your selected concerns.
        </p>
      ) : null}

      <dl className="grid grid-cols-1 gap-x-8 gap-y-4 border-t-2 border-black pt-5 sm:grid-cols-3">
        <div className="flex flex-col gap-1.5">
          <dt className="font-sans text-2xs label-caps text-black/60">Products</dt>
          <dd className="font-sans text-sm text-black">
            {item.product_a.label}
            <span className="px-2 text-accent" aria-hidden="true">
              ·
            </span>
            {item.product_b.label}
          </dd>
        </div>
        {item.confidence ? (
          <div className="flex flex-col gap-1.5">
            <dt className="font-sans text-2xs label-caps text-black/60">Confidence</dt>
            <dd className="font-sans text-sm text-black">{sentenceCase(item.confidence)}</dd>
          </div>
        ) : null}
        <div className="flex flex-col gap-1.5">
          <dt className="font-sans text-2xs label-caps text-black/60">Evidence</dt>
          <dd className="font-sans text-sm text-black">
            {sourceUrl ? (
              <a
                className="inline-flex items-center gap-1.5 font-bold text-accent-text underline decoration-2 underline-offset-4 transition-colors duration-150 hover:text-black"
                href={sourceUrl}
                target="_blank"
                rel="noreferrer noopener"
              >
                {item.source_citation}
                <Icon name="arrowUpRight" size={12} strokeWidth={2.5} />
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
