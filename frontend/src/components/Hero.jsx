import { AnchorButton, Button } from "./ui/Button.jsx";
import { Headline, SectionLabel } from "./ui/Section.jsx";

/**
 * Abstract composition: a black rectangle, a red circle, rules. It stands in
 * for the routine itself -- two masses that overlap -- and is ornament only.
 */
function Composition() {
  return (
    <div
      className="relative min-h-[280px] flex-1 overflow-hidden border-b-4 border-black lg:min-h-[420px]"
      aria-hidden="true"
    >
      <span className="absolute left-[8%] top-[10%] h-[56%] w-[42%] bg-black" />
      <span className="absolute left-[19%] top-[26%] h-[18%] w-[18%] bg-white" />
      <span className="absolute right-[12%] top-[20%] aspect-square h-[40%] rounded-full bg-accent shadow-ring-accent" />
      <span className="absolute inset-x-0 top-[72%] h-1 bg-black" />
      <span className="absolute inset-x-0 top-[80%] h-0.5 bg-black" />
      <span className="absolute bottom-[6%] right-[8%] h-[10%] w-[10%] bg-black" />
      <span className="absolute bottom-[6%] left-[8%] font-sans text-2xs label-caps text-black">AM · PM · Cumulative</span>
    </div>
  );
}

/** Numbered facts, set as a bordered list rather than an icon row. */
function Facts({ items }) {
  return (
    <ol className="flex flex-col">
      {items.map((fact, index) => (
        <li
          key={fact}
          className="flex items-baseline gap-5 border-b-2 border-black px-6 py-4 font-sans text-sm font-medium text-black last:border-b-0 md:px-8"
        >
          <span className="font-sans text-2xs label-caps text-accent-text" aria-hidden="true">
            {String(index + 1).padStart(2, "0")}
          </span>
          {fact}
        </li>
      ))}
    </ol>
  );
}

export function Hero({ ingredientCount, productCount, interactionCount, onStart }) {
  const facts = [
    ingredientCount ? `${ingredientCount.toLocaleString()} ingredients indexed` : null,
    productCount ? `${productCount.toLocaleString()} product ingredient lists` : null,
    interactionCount ? `${interactionCount.toLocaleString()} cited interaction rules` : null,
    "Checked within AM, within PM and across both",
  ].filter(Boolean);

  return (
    <section className="grid grid-cols-1 border-b-4 border-black lg:grid-cols-12" aria-labelledby="hero-title">
      {/* 7:5. The headline owns the wide column; the composition balances it. */}
      <div className="flex flex-col gap-8 py-12 md:py-20 lg:col-span-7 lg:border-r-4 lg:border-black lg:pr-12">
        <SectionLabel number="01">Ingredient interaction engine</SectionLabel>
        <Headline as="h1" size="hero" id="hero-title">
          Find the <span className="text-accent">conflicts</span> hiding in your routine.
        </Headline>
        <p className="max-w-[52ch] font-sans text-lg leading-relaxed text-black/70">
          SkincareSync parses the real ingredient list behind every product you use, then checks each pair against a
          cited interaction database: within your morning routine, your evening routine, and across both.
        </p>
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center">
          <Button variant="primary" size="lg" iconAfter="arrowRight" onClick={onStart}>
            Analyze my routine
          </Button>
          <AnchorButton href="#catalog" variant="secondary" size="lg">
            Browse the catalog
          </AnchorButton>
        </div>
      </div>

      <div className="swiss-grid-pattern flex flex-col bg-muted lg:col-span-5">
        <Composition />
        <Facts items={facts} />
      </div>
    </section>
  );
}
