import { useEffect, useRef, useState } from "react";
import { Panel } from "./ui/Panel.jsx";
import { Button } from "./ui/Button.jsx";
import { ProductRow } from "./ProductRow.jsx";
import { isReadyForAnalysis } from "../lib/products.js";

const NUMBER = { am: "02", pm: "03" };

export function RoutineBuilder({
  routine,
  products,
  busy,
  missingRequired,
  scanSupported,
  onAdd,
  onRemove,
  onFieldChange,
  onLookupCode,
  onSearch,
  onScan,
}) {
  const readyCount = products.filter(isReadyForAnalysis).length;

  // `undefined` means "nothing chosen yet, follow the routine"; `null` means the
  // user deliberately closed everything. They are not the same state.
  const [openId, setOpenId] = useState(undefined);
  const previousCount = useRef(products.length);

  // Adding a product opens it and folds the rest down.
  useEffect(() => {
    if (products.length > previousCount.current) {
      setOpenId(products[products.length - 1].id);
    }
    previousCount.current = products.length;
  }, [products]);

  const firstUnfinished = products.find((product) => !isReadyForAnalysis(product));
  const expandedId = openId === undefined ? (firstUnfinished?.id ?? null) : openId;

  return (
    <Panel
      number={NUMBER[routine.key]}
      eyebrow={routine.key === "am" ? "Morning" : "Evening"}
      title={routine.title}
      description={`${readyCount} of ${products.length} ready to analyze`}
      actions={
        <Button variant="secondary" icon="plus" onClick={onAdd}>
          Add product
        </Button>
      }
      padding="none"
    >
      {/* A routine always holds at least one row: the last one cannot be removed. */}
      <ul className="flex flex-col divide-y-2 divide-black">
        {products.map((product, index) => (
          <li key={product.id}>
            <ProductRow
              product={product}
              position={index + 1}
              canRemove={products.length > 1}
              missingRequired={missingRequired}
              isBusy={busy[product.id] ?? false}
              scanSupported={scanSupported}
              expanded={product.id === expandedId}
              onToggle={() => setOpenId(product.id === expandedId ? null : product.id)}
              onFieldChange={(field, value) => onFieldChange(product.id, field, value)}
              onRemove={() => onRemove(product.id)}
              onLookupCode={() => onLookupCode(product.id)}
              onSearch={() => onSearch(product.id)}
              onScan={() => onScan(product.id)}
            />
          </li>
        ))}
      </ul>
    </Panel>
  );
}
