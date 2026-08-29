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
