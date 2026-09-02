import { Button, IconButton } from "./ui/Button.jsx";
import { Badge } from "./ui/Badge.jsx";
import { TextInput } from "./ui/Field.jsx";
import { Icon } from "./ui/Icon.jsx";
import { Spinner } from "./ui/Spinner.jsx";
import { countIngredients } from "../lib/products.js";
import { safeExternalUrl } from "../lib/format.js";

/* Status is a word, a symbol and an edge colour. Error is the only red. */
const STATUS_TONE = {
  idle: { icon: "info", edge: "bg-ink/20", text: "text-ink/60" },
  loading: { icon: null, edge: "bg-ink", text: "text-ink" },
  success: { icon: "check", edge: "bg-ink", text: "text-ink" },
  error: { icon: "alertTriangle", edge: "bg-coral", text: "text-coral-deep" },
};

function LookupStatus({ product, missingRequired }) {
  const hasList = Boolean(product.raw_ingredient_list);
  const state = missingRequired && !hasList ? "error" : product.lookupState;
  const { icon, edge, text } = STATUS_TONE[state] ?? STATUS_TONE.idle;

  const message =
    missingRequired && !hasList
      ? "An ingredient list is required before analysis."
      : product.lookupMessage || (hasList ? "Ingredient list loaded." : "Look up this product to load its ingredient list.");

  return (
    <p className={`relative flex items-center gap-3 py-1 pl-5 font-sans text-sm font-medium ${text}`} role="status">
      <span className={`absolute inset-y-0 left-0 w-1 ${edge}`} aria-hidden="true" />
      {state === "loading" ? <Spinner size={14} /> : icon ? <Icon name={icon} size={14} strokeWidth={2.5} /> : null}
      <span>{message}</span>
    </p>
  );
}

/**
 * One product in a routine. Rows collapse: only the one being worked on is
 * open, the rest fold down to a summary line.
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
  const subtitle = hasList ? `${ingredientCount} ingredients parsed` : product.brand?.trim() || "No ingredient list yet";

  return (
    <article className={`relative ${needsAttention ? "bg-paper" : "bg-paper"}`}>
      {needsAttention ? <span className="absolute inset-y-0 left-0 w-2 bg-coral" aria-hidden="true" /> : null}
      <header className="flex items-center gap-2 pr-4 md:pr-6">
        {/* The whole identity block is the toggle, so the hit target is the width of the row. */}
        <button
          type="button"
          className="group flex min-w-0 grow items-center gap-5 px-6 py-5 text-left transition-colors duration-150 hover:bg-sand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-coral-deep md:px-8"
          aria-expanded={expanded}
          onClick={onToggle}
        >
          {imageUrl ? (
            <img className="h-12 w-12 shrink-0 border-2 border-ink object-cover" src={imageUrl} alt="" width="48" height="48" loading="lazy" />
          ) : (
            <span className="w-12 shrink-0 font-sans text-4xl font-black leading-none tracking-tighter text-ink/20 group-hover:text-coral-deep" aria-hidden="true">
              {String(position).padStart(2, "0")}
            </span>
          )}
          <span className="flex min-w-0 flex-col gap-1">
            <span className="truncate font-sans text-base font-black uppercase tracking-tight text-ink">{title}</span>
            <span className={`truncate font-sans text-xs ${hasList ? "text-ink" : "text-ink/60"}`}>{subtitle}</span>
          </span>
          <Icon
            name="chevronDown"
            size={18}
            strokeWidth={2.5}
            className={`ml-auto shrink-0 transition-transform duration-150 ease-linear ${expanded ? "rotate-180" : ""}`}
          />
        </button>

        <div className="flex shrink-0 items-center gap-2">
          {product.isExample ? <Badge size="sm">Example</Badge> : null}
          {typeof product.matchScore === "number" ? (
            <Badge size="sm" tone="ok">
              {product.matchScore}% match
            </Badge>
          ) : null}
          {canRemove ? <IconButton icon="trash" label={`Remove ${title}`} size="sm" variant="ghost" onClick={onRemove} /> : null}
        </div>
      </header>

      {expanded ? (
        <div className="swiss-grid-pattern flex flex-col gap-6 border-t-2 border-ink bg-sand px-6 py-6 md:px-8 md:py-8">
          <div className="grid grid-cols-1 gap-6 md:grid-cols-2 md:gap-8">
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

          <div className="flex flex-col gap-5">
            <Button
              variant="primary"
              icon="search"
              onClick={onSearch}
              disabled={searchDisabled || isBusy}
              loading={isBusy === "search"}
              block
            >
              Find ingredients by name
            </Button>

            <div className="flex items-center gap-4" role="presentation">
              <span className="h-0.5 grow bg-ink" />
              <span className="font-sans text-2xs label-caps text-ink">Or use a product code</span>
              <span className="h-0.5 grow bg-ink" />
            </div>

            <div className="grid grid-cols-1 gap-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-end">
              <TextInput
                label="Barcode or QR code"
                value={product.code ?? ""}
                placeholder="Scan or paste a product code"
                inputMode="numeric"
                autoComplete="off"
                onChange={(event) => onFieldChange("code", event.target.value)}
              />
              <div className="flex gap-2">
                <Button variant="secondary" onClick={onLookupCode} disabled={!product.code?.trim() || isBusy} loading={isBusy === "code"}>
                  Look up
                </Button>
                <Button
                  variant="secondary"
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
            <details className="group border-t-2 border-ink pt-4">
              <summary className="flex cursor-pointer list-none items-center gap-3 font-sans text-xs label-caps text-ink [&::-webkit-details-marker]:hidden">
                <Icon name="plus" size={14} strokeWidth={2.5} className="transition-transform duration-150 ease-linear group-open:rotate-45" />
                View parsed ingredient list
              </summary>
              <p className="mt-4 font-sans text-sm leading-relaxed text-ink">{product.raw_ingredient_list}</p>
              {sourceUrl ? (
                <a
                  className="mt-4 inline-flex items-center gap-2 font-sans text-xs font-bold uppercase tracking-widest text-coral-deep underline decoration-2 underline-offset-4 hover:text-ink"
                  href={sourceUrl}
                  target="_blank"
                  rel="noreferrer noopener"
                >
                  Open source record
                  <Icon name="arrowUpRight" size={12} strokeWidth={2.5} />
                </a>
              ) : null}
            </details>
          ) : null}
        </div>
      ) : null}
    </article>
  );
}
