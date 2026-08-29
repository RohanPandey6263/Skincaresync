import { Modal } from "./ui/Modal.jsx";
import { Badge, Chip } from "./ui/Badge.jsx";
import { Icon } from "./ui/Icon.jsx";
import { Spinner } from "./ui/Spinner.jsx";
import { citationUrl, firstIdentifier, formatFunction, sentenceCase } from "../lib/format.js";

const SEVERITY_TONE = { high: "danger", medium: "warn", low: "info" };

export function IngredientDetail({ ingredient, loading, error, onClose, onOpenRelated }) {
  const title = ingredient?.display_name || ingredient?.inci_name || "Ingredient";
  const cas = firstIdentifier(ingredient?.cas_number);
  const wiki = ingredient?.wikidata_id;
  const obfSlug = ingredient?.obf_id?.replace(/^en:/, "");

  return (
    <Modal
      open
      onClose={onClose}
      title={title}
      description={ingredient?.functions?.length ? ingredient.functions.map(formatFunction).join(" · ") : undefined}
    >
      {loading ? (
        <p className="ingredientDetail__status">
          <Spinner size={16} /> Loading ingredient…
        </p>
      ) : error ? (
        <p className="ingredientDetail__status ingredientDetail__status--error">{error}</p>
      ) : ingredient ? (
        <div className="ingredientDetail">
          <div className="ingredientDetail__flags">
            {ingredient.source === "curated" ? <Badge size="sm">Curated</Badge> : null}
            {ingredient.interaction_count > 0 ? (
              <Badge size="sm" tone="ok">
                In compatibility engine
              </Badge>
            ) : null}
            {ingredient.restriction ? (
              <Badge size="sm" tone="warn">
                Restricted
              </Badge>
            ) : null}
          </div>

          {ingredient.description ? (
            <p className="ingredientDetail__description">{ingredient.description}</p>
          ) : null}

          {ingredient.restriction ? (
            <p className="ingredientDetail__restriction">{ingredient.restriction}</p>
          ) : null}

          <dl className="ingredientDetail__meta">
            <div>
              <dt>INCI name</dt>
              <dd>{ingredient.inci_name}</dd>
            </div>
            {cas ? (
              <div>
                <dt>CAS</dt>
                <dd className="mono">{cas}</dd>
              </div>
            ) : null}
            {ingredient.cosing_ref ? (
              <div>
                <dt>CosIng</dt>
                <dd className="mono">{ingredient.cosing_ref}</dd>
              </div>
            ) : null}
            {ingredient.inn_name ? (
              <div>
                <dt>INN</dt>
                <dd>{ingredient.inn_name}</dd>
              </div>
            ) : null}
            {typeof ingredient.comodogenic === "number" ? (
              <div>
                <dt>Comedogenic</dt>
                <dd>{ingredient.comodogenic}</dd>
              </div>
            ) : null}
          </dl>

          {[...(ingredient.synonyms || []), ...(ingredient.alt_names || [])].length ? (
            <section>
              <h3 className="ingredientDetail__heading">Also known as</h3>
              <div className="chipRow">
                {[...new Set([...(ingredient.synonyms || []), ...(ingredient.alt_names || [])])]
                  .slice(0, 24)
                  .map((name) => (
                    <Chip key={name}>{name}</Chip>
                  ))}
              </div>
            </section>
          ) : null}

          {ingredient.functions?.length ? (
            <section>
              <h3 className="ingredientDetail__heading">Functions</h3>
              <div className="chipRow">
                {ingredient.functions.map((fn) => (
                  <Chip key={fn}>{formatFunction(fn)}</Chip>
                ))}
              </div>
            </section>
          ) : null}

          {ingredient.interactions?.length ? (
            <section>
              <h3 className="ingredientDetail__heading">Known interactions</h3>
              <ul className="ingredientDetail__interactions">
                {ingredient.interactions.map((item) => (
                  <li key={item.interaction_id}>
                    <Badge size="sm" tone={SEVERITY_TONE[item.severity] ?? "neutral"}>
                      {sentenceCase(item.interaction_type)} · {item.severity}
                    </Badge>
                    <span>
                      {ingredient.display_name} + {item.partner_display_name}
                    </span>
                    {item.source_citation && citationUrl(item.source_citation) ? (
                      <a
                        href={citationUrl(item.source_citation)}
                        target="_blank"
                        rel="noreferrer noopener"
                      >
                        {item.source_citation}
                        <Icon name="external" size={11} />
                      </a>
                    ) : null}
                  </li>
                ))}
              </ul>
            </section>
          ) : null}

          {ingredient.related?.length ? (
            <section>
              <h3 className="ingredientDetail__heading">Related ingredients</h3>
              <ul className="ingredientDetail__related">
                {ingredient.related.map((item) => (
                  <li key={item.id}>
                    <button type="button" className="linkAction" onClick={() => onOpenRelated(item.id)}>
                      {item.display_name}
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          ) : null}

          <p className="ingredientDetail__links">
            {cas ? (
              <a
                href={`https://pubchem.ncbi.nlm.nih.gov/#query=${encodeURIComponent(cas)}`}
                target="_blank"
                rel="noreferrer noopener"
              >
                PubChem
                <Icon name="external" size={12} />
              </a>
            ) : null}
            {wiki ? (
              <a
                href={`https://www.wikidata.org/wiki/${encodeURIComponent(wiki)}`}
                target="_blank"
                rel="noreferrer noopener"
              >
                Wikidata
                <Icon name="external" size={12} />
              </a>
            ) : null}
            {obfSlug ? (
              <a
                href={`https://world.openbeautyfacts.org/ingredient/${encodeURIComponent(obfSlug)}`}
                target="_blank"
                rel="noreferrer noopener"
              >
                Open Beauty Facts
                <Icon name="external" size={12} />
              </a>
            ) : null}
          </p>
        </div>
      ) : null}
    </Modal>
  );
}
