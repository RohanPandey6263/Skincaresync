import { Button, IconButton } from "./ui/Button.jsx";
import { Badge } from "./ui/Badge.jsx";
import { TextInput } from "./ui/Field.jsx";
import { Icon } from "./ui/Icon.jsx";
import { Spinner } from "./ui/Spinner.jsx";
import { countIngredients } from "../lib/products.js";

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
}) {
  const ingredientCount = countIngredients(product.raw_ingredient_list);
  const hasList = ingredientCount > 0;
  const searchDisabled = !product.brand?.trim() && !product.name?.trim();

  return (
    <article className={`productRow${hasList ? " is-resolved" : ""}`}>
      <header className="productRow__header">
        <div className="productRow__identity">
          {product.image_url ? (
            <img
              className="productRow__thumb"
              src={product.image_url}
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
          <div className="productRow__titles">
            <p className="productRow__title">
              {product.name?.trim() || `Product ${position}`}
            </p>
            <p className="productRow__subtitle">
              {hasList
                ? `${ingredientCount} ingredients parsed`
                : product.brand?.trim() || "No ingredient list yet"}
            </p>
          </div>
        </div>
        <div className="productRow__headerActions">
          {product.isExample ? <Badge size="sm">Example</Badge> : null}
          {typeof product.matchScore === "number" ? (
            <Badge size="sm" tone="info">{product.matchScore}% match</Badge>
          ) : null}
          {canRemove ? (
            <IconButton
              icon="trash"
              label={`Remove ${product.name?.trim() || `product ${position}`}`}
              size="sm"
              variant="danger-ghost"
              onClick={onRemove}
            />
          ) : null}
        </div>
      </header>

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
              title={scanSupported ? "Scan with camera" : "Camera scanning is unavailable in this browser"}
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
          {product.product_url ? (
            <a
              className="productRow__source"
              href={product.product_url}
              target="_blank"
              rel="noreferrer noopener"
            >
              Open source record
              <Icon name="external" size={12} />
            </a>
          ) : null}
        </details>
      ) : null}
    </article>
  );
}
