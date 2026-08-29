import { Badge } from "./ui/Badge.jsx";
import { formatFunction } from "../lib/format.js";

export function IngredientCard({ ingredient, onOpen }) {
  const functions = (ingredient.functions || []).slice(0, 3);
  const extra = (ingredient.functions || []).length - functions.length;

  return (
    <button type="button" className="ingredientCard" onClick={() => onOpen(ingredient)}>
      <div className="ingredientCard__top">
        <h3 className="ingredientCard__title">{ingredient.display_name || ingredient.inci_name}</h3>
        {ingredient.interaction_count > 0 ? (
          <Badge size="sm" tone="ok">
            {ingredient.interaction_count} rule{ingredient.interaction_count === 1 ? "" : "s"}
          </Badge>
        ) : null}
      </div>
      {functions.length ? (
        <p className="ingredientCard__functions">
          {functions.map(formatFunction).join(" · ")}
          {extra > 0 ? ` +${extra}` : ""}
        </p>
      ) : (
        <p className="ingredientCard__functions">No CosIng function listed</p>
      )}
      {ingredient.restriction ? (
        <p className="ingredientCard__restriction">Restricted under CosIng annexes</p>
      ) : null}
    </button>
  );
}
