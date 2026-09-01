import { Button, IconButton } from "./ui/Button.jsx";
import { Badge } from "./ui/Badge.jsx";
import { TextInput } from "./ui/Field.jsx";
import { Icon } from "./ui/Icon.jsx";
import { Spinner } from "./ui/Spinner.jsx";
import { countIngredients } from "../lib/products.js";
import { safeExternalUrl } from "../lib/format.js";

const STATUS_TONE = {
  idle: { icon: "info", className: "lookup--idle" },
  loading: { icon: null, className: "lookup--loading" },
  success: { icon: "checkCircle", className: "lookup--success" },
  error: { icon: "alertTriangle", className: "lookup--error" },
};

function LookupStatus({ product, missingRequired }) {
  const hasList = Boolean(product.raw_ingredient_list);
  const state = missingRequired && !hasList ? "error" : product.lookupState;
  const { icon, className } = STATUS_TONE[state] ?? STATUS_TONE.idle;

  const message =
    missingRequired && !hasList
      ? "An ingredient list is required before analysis."
      : product.lookupMessage ||
        (hasList ? "Ingredient list loaded." : "Look up this product to load its ingredient list.");

  return (
    <p className={`lookup ${className}`} role="status">
      {state === "loading" ? <Spinner size={13} /> : icon ? <Icon name={icon} size={13} /> : null}
      <span>{message}</span>
    </p>
  );
}

/**
 * One product in a routine.
 *
 * Rows collapse: only the one being worked on is open, the rest fold down to a
 * summary line. Three full lookup forms stacked was the single biggest source
 * of scrolling in the builder, and a product whose ingredients are already
 * loaded has nothing left to fill in.
 */
export function ProductRow({
  product,
  position,
  canRemove,
  missingRequired,
  isBusy,
  onFieldChange,
  onRemove,
  onLookupCode,
  onSearch,
  onScan,
  scanSupported,
  expanded,
  onToggle,
}) {
  const ingredientCount = countIngredients(product.raw_ingredient_list);
  const hasList = ingredientCount > 0;
  const searchDisabled = !product.brand?.trim() && !product.name?.trim();
  const imageUrl = safeExternalUrl(product.image_url);
  const sourceUrl = safeExternalUrl(product.product_url);
  const needsAttention = missingRequired && !hasList;

  const title = product.name?.trim() || `Product ${position}`;
  const subtitle = hasList
    ? `${ingredientCount} ingredients parsed`
    : product.brand?.trim() || "No ingredient list yet";

  return (
    <article
      className={[
        "productRow",
        hasList ? "is-resolved" : "",
        expanded ? "is-open" : "",
        needsAttention ? "is-missing" : "",
      ]
        .filter(Boolean)
        .join(" ")}
    >
      <header className="productRow__header">
        {/* The whole identity block is the toggle, so the hit target is the
            width of the row rather than a chevron. */}
        <button
          type="button"
          className="productRow__toggle"
          aria-expanded={expanded}
          onClick={onToggle}
        >
          {imageUrl ? (
            <img
              className="productRow__thumb"
              src={imageUrl}
              alt=""
              width="40"
              height="40"
              loading="lazy"
            />
          ) : (
            <span className="productRow__index" aria-hidden="true">
              {position}
            </span>
          )}
          <span className="productRow__titles">
            <span className="productRow__title">{title}</span>
            <span className="productRow__subtitle">{subtitle}</span>
          </span>
          <Icon name="chevronDown" size={16} className="productRow__chevron" />
        </button>

        <div className="productRow__headerActions">
          {product.isExample ? <Badge size="sm">Example</Badge> : null}
          {typeof product.matchScore === "number" ? (
            <Badge size="sm" tone="info">
              {product.matchScore}% match
            </Badge>
          ) : null}
          {canRemove ? (
            <IconButton
              icon="trash"
              label={`Remove ${title}`}
              size="sm"
              variant="danger-ghost"
              onClick={onRemove}
            />
          ) : null}
        </div>
      </header>

      {expanded ? (
        <div className="productRow__body">
          <div className="productRow__grid">
            <TextInput
              label="Brand"
              value={product.brand}
              placeholder="The Ordinary"
              autoComplete="off"
              onChange={(event) => onFieldChange("brand", event.target.value)}
            />
            <TextInput
              label="Product name"
              value={product.name}
              placeholder="Glycolic Acid 7% Toning Solution"
              autoComplete="off"
              onChange={(event) => onFieldChange("name", event.target.value)}
            />
          </div>

          <div className="productRow__lookup">
            <Button
              variant="secondary"
              icon="search"
              onClick={onSearch}
              disabled={searchDisabled || isBusy}
              loading={isBusy === "search"}
              block
            >
              Find ingredients by name
            </Button>

            <div className="productRow__divider" role="presentation">
              <span>or use a product code</span>
            </div>

            <div className="productRow__codeRow">
              <TextInput
                label="Barcode or QR code"
                className="productRow__codeField"
                value={product.code ?? ""}
                placeholder="Scan or paste a product code"
                inputMode="numeric"
                autoComplete="off"
                onChange={(event) => onFieldChange("code", event.target.value)}
              />
              <div className="productRow__codeActions">
                <Button
                  variant="quiet"
                  onClick={onLookupCode}
                  disabled={!product.code?.trim() || isBusy}
                  loading={isBusy === "code"}
                >
                  Look up
                </Button>
                <Button
                  variant="quiet"
                  icon="camera"
                  onClick={onScan}
                  disabled={isBusy}
                  title={
                    scanSupported
                      ? "Scan with camera"
                      : "Camera scanning is unavailable in this browser"
                  }
                >
                  Scan
                </Button>
              </div>
            </div>
          </div>

          <LookupStatus product={product} missingRequired={missingRequired} />

          {hasList ? (
            <details className="productRow__details">
              <summary>
                <Icon name="chevronDown" size={14} />
                View parsed ingredient list
              </summary>
              <p className="productRow__ingredients">{product.raw_ingredient_list}</p>
              {sourceUrl ? (
                <a
                  className="productRow__source"
                  href={sourceUrl}
                  target="_blank"
                  rel="noreferrer noopener"
                >
                  Open source record
                  <Icon name="external" size={12} />
                </a>
              ) : null}
            </details>
          ) : null}
        </div>
      ) : null}
    </article>
  );
}
