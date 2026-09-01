import { Panel } from "./ui/Panel.jsx";
import { Badge, Chip } from "./ui/Badge.jsx";
import { Icon } from "./ui/Icon.jsx";
import { EmptyState, SkeletonCard } from "./ui/Feedback.jsx";
import { ResultCard } from "./ResultCard.jsx";
import { ScoreSummary } from "./ScoreSummary.jsx";
import { RESULT_GROUPS, SKIN_TYPES } from "../lib/constants.js";
import { pluralize } from "../lib/format.js";

function skinTypeLabel(value) {
  return SKIN_TYPES.find((type) => type.value === value)?.label ?? value;
}

function ResultGroup({ group, items, skinType }) {
  if (!items.length) return null;

  return (
    <section className="resultGroup" aria-labelledby={`group-${group.key}`}>
      <header className="resultGroup__header">
        <h3 className="resultGroup__title" id={`group-${group.key}`}>
          <Icon name={group.icon} size={15} />
          {group.title}
          <Badge tone={group.tone} size="sm">
            {items.length}
          </Badge>
        </h3>
        <p className="resultGroup__description">{group.description}</p>
      </header>
      <div className="resultGroup__items">
        {items.map((item, index) => (
          <ResultCard
            key={`${group.key}-${item.interaction_id}-${item.scope}-${index}`}
            item={item}
            skinType={skinType}
          />
        ))}
      </div>
    </section>
  );
}

function ParsedProducts({ parsedProducts }) {
  if (!parsedProducts?.length) return null;

  return (
    <details className="disclosure">
      <summary>
        <Icon name="chevronDown" size={14} />
        Ingredients matched to the database
        <span className="disclosure__meta">{pluralize(parsedProducts.length, "product")}</span>
      </summary>
      <ul className="parsedList">
        {/* Two products can share a label (both seeded examples are branded
            "Example"), so the label alone is not a stable key. */}
        {parsedProducts.map((entry, index) => (
          <li key={`${entry.product.label}-${index}`} className="parsedList__item">
            <p className="parsedList__title">{entry.product.label}</p>
            {entry.known_ingredients.length ? (
              <div className="chipRow">
                {entry.known_ingredients.map((ingredient) => (
                  <Chip key={ingredient.id}>{ingredient.inci_name}</Chip>
                ))}
              </div>
            ) : (
              <p className="parsedList__empty">No known ingredients matched.</p>
            )}
          </li>
        ))}
      </ul>
    </details>
  );
}

function UnresolvedTokens({ tokens }) {
  if (!tokens?.length) return null;

  return (
    <details className="disclosure">
      <summary>
        <Icon name="chevronDown" size={14} />
        Ingredients we could not identify
        <span className="disclosure__meta">{tokens.length}</span>
      </summary>
      <p className="disclosure__note">
        These entries are not in the ingredient database yet, so they were excluded from the
        analysis.
      </p>
      <div className="chipRow">
        {tokens.map((token, index) => (
          <Chip key={`${token.normalized_token}-${index}`}>{token.raw_token}</Chip>
        ))}
      </div>
    </details>
  );
}

export function ResultsPanel({ result, loading, skinType, concerns, onGoToBuilder }) {
  const profileSummary = [
    `${skinTypeLabel(skinType)} skin`,
    concerns.length ? pluralize(concerns.length, "concern") : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <Panel
      title="Compatibility report"
      icon="beaker"
      description={result || loading ? `Evaluated for ${profileSummary}` : undefined}
      className="resultsPanel"
      as="section"
    >
      <div aria-live="polite" aria-busy={loading}>
        {loading ? (
          <div className="resultsLoading">
            <p className="resultsLoading__label">
              <Icon name="beaker" size={14} />
              Checking every ingredient pair against the interaction database…
            </p>
            <SkeletonCard />
            <SkeletonCard />
          </div>
        ) : !result ? (
          <EmptyState
            icon="beaker"
            title="No analysis yet"
            description="Add at least two products with ingredient lists, then run the compatibility check to see conflicts, cautions and synergies."
            action={
              onGoToBuilder ? (
                <button type="button" className="linkAction" onClick={onGoToBuilder}>
                  Go to routine builder
                  <Icon name="arrowRight" size={13} />
                </button>
              ) : null
            }
          />
        ) : (
          <div className="results">
            <ScoreSummary result={result} />

            {RESULT_GROUPS.map((group) => (
              <ResultGroup
                key={group.key}
                group={group}
                items={result[group.key] ?? []}
                skinType={skinTypeLabel(skinType).toLowerCase()}
              />
            ))}

            {result.overall_score.status === "clean" && !result.synergies.length ? (
              <EmptyState
                icon="checkCircle"
                compact
                title="Nothing flagged"
                description="No interaction rules matched the ingredients in these routines."
              />
            ) : null}

            <div className="results__disclosures">
              <ParsedProducts parsedProducts={result.parsed_products} />
              <UnresolvedTokens tokens={result.unresolved_tokens} />
            </div>
          </div>
        )}
      </div>
    </Panel>
  );
}
