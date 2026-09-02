import { Icon } from "./ui/Icon.jsx";
import { formatFunction } from "../lib/format.js";

/** A cell in the catalog grid. Hover inverts the whole cell to black. */
export function IngredientCard({ ingredient, onOpen }) {
  const functions = (ingredient.functions || []).slice(0, 3);
  const extra = (ingredient.functions || []).length - functions.length;

  return (
    <button
      type="button"
      className="group flex h-full min-h-40 flex-col gap-4 bg-white p-5 text-left transition-colors duration-150 ease-linear
                 hover:bg-black hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-accent"
      onClick={() => onOpen(ingredient)}
    >
      <div className="flex items-start justify-between gap-4">
        <h3 className="font-sans text-base font-black uppercase leading-tight tracking-tight">
          {ingredient.display_name || ingredient.inci_name}
        </h3>
        <Icon name="arrowRight" size={18} strokeWidth={2.5} className="shrink-0 -rotate-45 transition-transform duration-150 ease-linear group-hover:rotate-0" />
      </div>
      <p className="font-sans text-xs leading-relaxed opacity-70">
        {functions.length ? `${functions.map(formatFunction).join(" · ")}${extra > 0 ? ` +${extra}` : ""}` : "No CosIng function listed"}
      </p>
      <div className="mt-auto flex flex-wrap gap-2 font-sans text-2xs label-caps">
        {ingredient.interaction_count > 0 ? (
          <span className="inline-flex items-center gap-1.5">
            <span className="h-2 w-2 bg-current" aria-hidden="true" />
            {ingredient.interaction_count} rule{ingredient.interaction_count === 1 ? "" : "s"}
          </span>
        ) : null}
        {ingredient.restriction ? (
          <span className="inline-flex items-center gap-1.5 text-accent-text group-hover:text-accent">
            <Icon name="alertTriangle" size={11} strokeWidth={2.5} />
            Restricted
          </span>
        ) : null}
      </div>
    </button>
  );
}
