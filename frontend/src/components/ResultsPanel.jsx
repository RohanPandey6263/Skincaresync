import { Panel } from "./ui/Panel.jsx";
import { Badge, Chip } from "./ui/Badge.jsx";
import { Button } from "./ui/Button.jsx";
import { Icon } from "./ui/Icon.jsx";
import { EmptyState, SkeletonCard } from "./ui/Feedback.jsx";
import { ResultCard } from "./ResultCard.jsx";
import { ScoreSummary } from "./ScoreSummary.jsx";
import { RESULT_GROUPS, SKIN_TYPES } from "../lib/constants.js";
import { pluralize } from "../lib/format.js";

function skinTypeLabel(value) {
  return SKIN_TYPES.find((type) => type.value === value)?.label ?? value;
}

const GROUP_BADGE = { conflicts: "danger", cautions: "warn", synergies: "ok" };

/**
 * Sections in safety order. The group word is the largest type on the page
 * after the verdict; the ingredient pairs inside are deliberately smaller.
 */
function ResultGroup({ group, index, items, skinType }) {
  if (!items.length) return null;

  return (
    <section className="flex flex-col gap-6" aria-labelledby={`group-${group.key}`}>
      <header className="flex flex-col gap-3 border-b-4 border-cocoa pb-5">
        <p className="font-sans text-2xs label-caps text-coral-deep" aria-hidden="true">
          {String(index + 1).padStart(2, "0")}
        </p>
        <div className="flex flex-wrap items-end gap-4">
          <h3 className="font-sans text-section font-black uppercase text-ink" id={`group-${group.key}`}>
            {group.title}
          </h3>
          <Badge tone={GROUP_BADGE[group.key] ?? "neutral"} className="mb-2">
            {items.length}
          </Badge>
        </div>
        <p className="font-sans text-sm text-cocoa">{group.description}</p>
      </header>
      <div className="grid grid-cols-1 gap-6 xl:grid-cols-2">
        {items.map((item, itemIndex) => (
          <ResultCard key={`${group.key}-${item.interaction_id}-${item.scope}-${itemIndex}`} item={item} skinType={skinType} />
        ))}
      </div>
    </section>
  );
}

function Disclosure({ title, meta, children }) {
  return (
    <details className="group border-t-2 border-cocoa">
      <summary className="flex cursor-pointer list-none items-center gap-4 py-5 font-sans text-xs label-caps text-ink [&::-webkit-details-marker]:hidden">
        <Icon name="plus" size={16} strokeWidth={2.5} className="transition-transform duration-150 ease-linear group-open:rotate-45" />
        {title}
        {meta ? <span className="ml-auto font-medium normal-case tracking-normal text-cocoa">{meta}</span> : null}
      </summary>
      <div className="flex flex-col gap-5 pb-8">{children}</div>
    </details>
  );
}

function ParsedProducts({ parsedProducts }) {
  if (!parsedProducts?.length) return null;

  return (
    <Disclosure title="Ingredients matched to the database" meta={pluralize(parsedProducts.length, "product")}>
      <ul className="flex flex-col gap-6">
        {parsedProducts.map((entry, index) => (
          <li key={`${entry.product.label}-${index}`} className="flex flex-col gap-3">
            <p className="font-sans text-sm font-black uppercase tracking-tight text-ink">{entry.product.label}</p>
            {entry.known_ingredients.length ? (
              <div className="flex flex-wrap gap-1.5">
                {entry.known_ingredients.map((ingredient) => (
                  <Chip key={ingredient.id}>{ingredient.inci_name}</Chip>
                ))}
              </div>
            ) : (
              <p className="font-sans text-sm text-cocoa">No known ingredients matched.</p>
            )}
          </li>
        ))}
      </ul>
    </Disclosure>
  );
}

function UnresolvedTokens({ tokens }) {
  if (!tokens?.length) return null;

  return (
    <Disclosure title="Ingredients we could not identify" meta={String(tokens.length)}>
      <p className="max-w-[64ch] font-sans text-sm leading-relaxed text-cocoa">
        These entries are not in the ingredient database yet, so they were excluded from the analysis.
      </p>
      <div className="flex flex-wrap gap-1.5">
        {tokens.map((token, index) => (
          <Chip key={`${token.normalized_token}-${index}`}>{token.raw_token}</Chip>
        ))}
      </div>
    </Disclosure>
  );
}

export function ResultsPanel({ result, loading, skinType, concerns, onGoToBuilder }) {
  const profileSummary = [`${skinTypeLabel(skinType)} skin`, concerns.length ? pluralize(concerns.length, "concern") : null]
    .filter(Boolean)
    .join(" · ");

  return (
    <Panel
      number="01"
      eyebrow="Report"
      title="Compatibility report"
      description={result || loading ? `Evaluated for ${profileSummary}` : undefined}
      as="section"
      footer={
        result ? (
          <p className="max-w-[80ch] font-sans text-xs leading-relaxed text-cocoa">
            This is ingredient-compatibility information drawn from published studies. It is not a diagnosis or
            medical advice. Patch-test new products and consult a dermatologist about persistent irritation.
          </p>
        ) : undefined
      }
    >
      <div aria-live="polite" aria-busy={loading}>
        {loading ? (
          <div className="flex flex-col gap-6">
            <p className="flex items-center gap-3 font-sans text-xs label-caps text-ink">
              <Icon name="beaker" size={14} strokeWidth={2.5} />
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
                <Button variant="primary" iconAfter="arrowRight" onClick={onGoToBuilder}>
                  Go to routine builder
                </Button>
              ) : null
            }
          />
        ) : (
          <div className="flex flex-col gap-12 md:gap-16">
            <ScoreSummary result={result} />

            {RESULT_GROUPS.map((group, index) => (
              <ResultGroup
                key={group.key}
                group={group}
                index={index}
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

            <div className="flex flex-col border-b-2 border-cocoa">
              <ParsedProducts parsedProducts={result.parsed_products} />
              <UnresolvedTokens tokens={result.unresolved_tokens} />
            </div>
          </div>
        )}
      </div>
    </Panel>
  );
}
