import { Modal } from "./ui/Modal.jsx";
import { Badge, Chip } from "./ui/Badge.jsx";
import { Callout } from "./ui/Feedback.jsx";
import { Icon } from "./ui/Icon.jsx";
import { Spinner } from "./ui/Spinner.jsx";
import { citationUrl, firstIdentifier, formatFunction, sentenceCase } from "../lib/format.js";

const SEVERITY_TONE = { high: "danger", medium: "warn", low: "info" };

const H = "font-sans text-2xs label-caps text-ink";

function Section({ title, children }) {
  return (
    <section className="flex flex-col gap-3 border-t-2 border-cocoa pt-5">
      <h3 className={H}>{title}</h3>
      {children}
    </section>
  );
}

export function IngredientDetail({ ingredient, loading, error, onClose, onOpenRelated }) {
  const title = ingredient?.display_name || ingredient?.inci_name || "Ingredient";
  const cas = firstIdentifier(ingredient?.cas_number);
  const wiki = ingredient?.wikidata_id;
  const obfSlug = ingredient?.obf_id?.replace(/^en:/, "");

  const meta = ingredient
    ? [
        ["INCI name", ingredient.inci_name],
        ["CAS", cas],
        ["CosIng", ingredient.cosing_ref],
        ["INN", ingredient.inn_name],
        ["Comedogenic", typeof ingredient.comodogenic === "number" ? `${ingredient.comodogenic} of 5` : null],
        [
          "Effective pH",
          typeof ingredient.ph_min === "number" && typeof ingredient.ph_max === "number" ? `${ingredient.ph_min} – ${ingredient.ph_max}` : null,
        ],
      ].filter(([, value]) => value)
    : [];

  const links = [
    cas ? { label: "PubChem", href: `https://pubchem.ncbi.nlm.nih.gov/#query=${encodeURIComponent(cas)}` } : null,
    wiki ? { label: "Wikidata", href: `https://www.wikidata.org/wiki/${encodeURIComponent(wiki)}` } : null,
    obfSlug ? { label: "Open Beauty Facts", href: `https://world.openbeautyfacts.org/ingredient/${encodeURIComponent(obfSlug)}` } : null,
  ].filter(Boolean);

  return (
    <Modal
      open
      onClose={onClose}
      size="lg"
      title={title}
      description={ingredient?.functions?.length ? ingredient.functions.map(formatFunction).join(" · ") : undefined}
    >
      {loading ? (
        <p className="flex items-center gap-3 font-sans text-xs label-caps text-ink" role="status">
          <Spinner size={16} /> Loading ingredient…
        </p>
      ) : error ? (
        <Callout tone="danger">{error}</Callout>
      ) : ingredient ? (
        <div className="flex flex-col gap-6">
          <div className="flex flex-wrap gap-2">
            {ingredient.source === "curated" ? <Badge>Curated</Badge> : null}
            {ingredient.interaction_count > 0 ? (
              <Badge tone="ok" icon="link">
                In compatibility engine
              </Badge>
            ) : null}
            {ingredient.restriction ? (
              <Badge tone="warn" icon="alertTriangle">
                Restricted
              </Badge>
            ) : null}
          </div>

          {ingredient.description ? <p className="max-w-[64ch] font-sans text-base leading-relaxed text-ink">{ingredient.description}</p> : null}

          {ingredient.restriction ? (
            <Callout tone="warn" title="CosIng restriction">
              {ingredient.restriction}
            </Callout>
          ) : null}

          <dl className="grid grid-cols-1 gap-x-8 gap-y-4 border-t-2 border-cocoa pt-5 sm:grid-cols-2">
            {meta.map(([label, value]) => (
              <div key={label} className="flex flex-col gap-1">
                <dt className={H}>{label}</dt>
                <dd className="font-sans text-sm text-ink">{value}</dd>
              </div>
            ))}
          </dl>

          {[...(ingredient.synonyms || []), ...(ingredient.alt_names || [])].length ? (
            <Section title="Also known as">
              <div className="flex flex-wrap gap-1.5">
                {[...new Set([...(ingredient.synonyms || []), ...(ingredient.alt_names || [])])].slice(0, 24).map((name) => (
                  <Chip key={name}>{name}</Chip>
                ))}
              </div>
            </Section>
          ) : null}

          {ingredient.functions?.length ? (
            <Section title="Functions">
              <div className="flex flex-wrap gap-1.5">
                {ingredient.functions.map((fn) => (
                  <Chip key={fn}>{formatFunction(fn)}</Chip>
                ))}
              </div>
            </Section>
          ) : null}

          {ingredient.interactions?.length ? (
            <Section title={`Known interactions (${ingredient.interactions.length})`}>
              <ul className="flex flex-col divide-y-2 divide-cocoa border-y-2 border-cocoa">
                {ingredient.interactions.map((item) => (
                  <li key={item.interaction_id} className="flex flex-col gap-3 py-4">
                    <div className="flex flex-wrap items-center gap-3">
                      <Badge size="sm" tone={item.interaction_type === "synergy" ? "ok" : (SEVERITY_TONE[item.severity] ?? "neutral")}>
                        {sentenceCase(item.interaction_type)} · {item.severity}
                      </Badge>
                      <button
                        type="button"
                        className="font-sans text-sm font-black uppercase tracking-tight text-ink underline decoration-2 underline-offset-4 transition-colors duration-150 hover:text-coral-deep"
                        onClick={() => onOpenRelated(item.partner_id)}
                      >
                        {ingredient.display_name} + {item.partner_display_name}
                      </button>
                    </div>
                    {item.description ? <p className="font-sans text-sm leading-relaxed text-cocoa">{item.description}</p> : null}
                    {item.source_citation && citationUrl(item.source_citation) ? (
                      <a
                        className="inline-flex items-center gap-1.5 font-sans text-xs font-bold text-coral-deep underline decoration-2 underline-offset-4 hover:text-ink"
                        href={citationUrl(item.source_citation)}
                        target="_blank"
                        rel="noreferrer noopener"
                      >
                        {item.source_citation}
                        <Icon name="arrowUpRight" size={11} strokeWidth={2.5} />
                      </a>
                    ) : null}
                  </li>
                ))}
              </ul>
            </Section>
          ) : null}

          {ingredient.related?.length ? (
            <Section title="Related ingredients">
              <ul className="flex flex-wrap gap-2">
                {ingredient.related.map((item) => (
                  <li key={item.id}>
                    <button
                      type="button"
                      className="inline-flex h-10 items-center border-2 border-cocoa px-3 font-sans text-2xs label-caps text-ink transition-colors duration-150 hover:bg-cocoa hover:text-paper"
                      onClick={() => onOpenRelated(item.id)}
                    >
                      {item.display_name}
                    </button>
                  </li>
                ))}
              </ul>
            </Section>
          ) : null}

          {links.length ? (
            <Section title="External references">
              <ul className="flex flex-wrap gap-x-6 gap-y-2">
                {links.map((link) => (
                  <li key={link.href}>
                    <a
                      href={link.href}
                      target="_blank"
                      rel="noreferrer noopener"
                      className="inline-flex items-center gap-1.5 font-sans text-sm font-bold text-ink underline decoration-2 underline-offset-4 transition-colors duration-150 hover:text-coral-deep"
                    >
                      {link.label}
                      <Icon name="arrowUpRight" size={12} strokeWidth={2.5} />
                    </a>
                  </li>
                ))}
              </ul>
            </Section>
          ) : null}
        </div>
      ) : null}
    </Modal>
  );
}
