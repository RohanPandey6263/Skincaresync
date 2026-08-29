import { Badge } from "./ui/Badge.jsx";
import { Icon } from "./ui/Icon.jsx";
import { SCOPE_META, SEVERITY_META } from "../lib/constants.js";
import { citationUrl, sentenceCase } from "../lib/format.js";

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

  return (
    <article
      className={`resultCard resultCard--${
        item.interaction_type === "synergy" ? "synergy" : item.severity
      }`}
    >
      <header className="resultCard__header">
        <SeverityBadge item={item} />
        <span className="resultCard__scope">
          <Icon name={scope.icon} size={13} />
          {scope.label}
        </span>
      </header>

      <h4 className="resultCard__title">
        {item.ingredient_a.inci_name}
        <span className="resultCard__plus" aria-hidden="true">
          +
        </span>
        {item.ingredient_b.inci_name}
      </h4>

      {item.description ? <p className="resultCard__body">{item.description}</p> : null}

      {item.mechanism && item.mechanism !== item.description ? (
        <p className="resultCard__mechanism">
          <span className="resultCard__mechanismLabel">Mechanism</span>
          {item.mechanism}
        </p>
      ) : null}

      {escalated ? (
        <p className="resultCard__escalation">
          <Icon name="arrowRight" size={13} />
          Raised from {item.base_severity} to {item.severity} for {skinType} skin and your selected
          concerns.
        </p>
      ) : null}

      <dl className="resultCard__meta">
        <div>
          <dt>Products</dt>
          <dd>
            {item.product_a.label}
            <span className="resultCard__metaSep" aria-hidden="true">
              ·
            </span>
            {item.product_b.label}
          </dd>
        </div>
        {item.confidence ? (
          <div>
            <dt>Confidence</dt>
            <dd>{sentenceCase(item.confidence)}</dd>
          </div>
        ) : null}
        <div>
          <dt>Evidence</dt>
          <dd>
            {sourceUrl ? (
              <a href={sourceUrl} target="_blank" rel="noreferrer noopener">
                {item.source_citation}
                <Icon name="external" size={12} />
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
