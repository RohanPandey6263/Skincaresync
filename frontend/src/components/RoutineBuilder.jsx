import { Panel } from "./ui/Panel.jsx";
import { Button } from "./ui/Button.jsx";
import { ProductRow } from "./ProductRow.jsx";
import { EmptyState } from "./ui/Feedback.jsx";
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
      description={
        products.length
          ? `${readyCount} of ${products.length} ready to analyze`
          : "No products added yet"
      }
      actions={
        <Button variant="quiet" icon="plus" onClick={onAdd}>
          Add product
        </Button>
      }
      className="routinePanel"
    >
      {products.length === 0 ? (
        <EmptyState
          icon={routine.icon}
          compact
          title={`No ${routine.key === "am" ? "morning" : "evening"} products`}
          description="Add a product to include this routine in the analysis."
          action={
            <Button variant="secondary" icon="plus" onClick={onAdd}>
              Add product
            </Button>
          }
        />
      ) : (
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
      )}
    </Panel>
  );
}
