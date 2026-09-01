import { useEffect, useRef, useState } from "react";
import { Panel } from "./ui/Panel.jsx";
import { Button } from "./ui/Button.jsx";
import { ProductRow } from "./ProductRow.jsx";
import { isReadyForAnalysis } from "../lib/products.js";

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
  // user deliberately closed everything. They are not the same state, so a
  // collapsed-all routine does not spring back open on the next render.
  const [openId, setOpenId] = useState(undefined);
  const previousCount = useRef(products.length);

  // Adding a product opens it and folds the rest down: the new row is the one
  // you are about to fill in.
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
      title={routine.title}
      icon={routine.icon}
      description={`${readyCount} of ${products.length} ready to analyze`}
      actions={
        <Button variant="quiet" icon="plus" onClick={onAdd}>
          Add product
        </Button>
      }
      className="routinePanel"
    >
      {/* A routine always holds at least one row: the last one cannot be removed
          (canRemove below) and "Clear all" resets each routine to a single row. */}
      <ul className="routineList">
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
