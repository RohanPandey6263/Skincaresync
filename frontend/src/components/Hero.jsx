import { AnchorButton, Button } from "./ui/Button.jsx";
import { Headline, SectionLabel } from "./ui/Section.jsx";

/**
 * A still life of skincare packaging drawn as line art: a jar of cream, a
 * spray bottle, a pump bottle, a small jar and a dropper bottle on one rule,
 * with two pastel discs behind them. Ornament only, hence aria-hidden. The
 * rounded bottle silhouettes are the illustration's own vocabulary and do not
 * leak into the interface, which stays rectangular.
 */
function Composition() {
  const stroke = { fill: "none", stroke: "currentColor", strokeWidth: 3, strokeLinejoin: "round", strokeLinecap: "round" };
  return (
    <div className="flex min-h-[280px] flex-1 items-end justify-center border-b-4 border-cocoa px-8 pt-10 text-ink lg:min-h-[420px]" aria-hidden="true">
      <svg viewBox="0 0 400 300" className="h-auto w-full max-w-[440px]" focusable="false">
        {/* Pastel discs behind the bottles. */}
        <circle cx="276" cy="168" r="42" className="fill-mint" />
        <circle cx="200" cy="228" r="30" className="fill-coral" />

        {/* Pump bottle, centre back. */}
        <path d="M250 60 V46 Q250 40 256 40 H272 Q278 40 278 46 V54" {...stroke} />
        <rect x="243" y="58" width="14" height="30" rx="3" className="fill-paper" {...stroke} />
        <rect x="236" y="88" width="28" height="22" rx="4" className="fill-paper" {...stroke} />
        <rect x="212" y="110" width="76" height="180" rx="10" className="fill-paper" {...stroke} />

        {/* Spray bottle, middle left. */}
        <rect x="171" y="118" width="18" height="30" rx="4" className="fill-paper" {...stroke} />
        <path d="M171 128 H160 V136 H171" {...stroke} />
        <rect x="167" y="148" width="26" height="22" rx="4" className="fill-paper" {...stroke} />
        <rect x="148" y="170" width="64" height="120" rx="10" className="fill-paper" {...stroke} />

        {/* Dropper bottle, right. */}
        <rect x="343" y="176" width="22" height="24" rx="6" className="fill-paper" {...stroke} />
        <rect x="328" y="200" width="52" height="90" rx="10" className="fill-paper" {...stroke} />
        <rect x="338" y="226" width="32" height="46" rx="6" className="fill-coral" />

        {/* Jar of cream, front left. */}
        <path d="M66 232 C74 206 92 216 100 214 C108 196 126 200 132 212 C140 202 154 208 154 232" className="fill-paper" {...stroke} />
        <rect x="58" y="232" width="104" height="58" rx="10" className="fill-coral" {...stroke} />
        <ellipse cx="110" cy="261" rx="34" ry="12" className="fill-paper" />
        <path d="M58 244 H162" {...stroke} />

        {/* Small jar, front centre right. */}
        <rect x="238" y="236" width="74" height="16" rx="5" className="fill-paper" {...stroke} />
        <rect x="228" y="252" width="94" height="38" rx="10" className="fill-mint" {...stroke} />
        <ellipse cx="275" cy="271" rx="26" ry="9" className="fill-paper" />

        {/* The shelf they stand on. */}
        <path d="M40 290 H380" stroke="currentColor" strokeWidth="5" strokeLinecap="square" />
      </svg>
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
          className="flex items-baseline gap-5 border-b-2 border-cocoa px-6 py-4 font-sans text-sm font-medium text-ink last:border-b-0 md:px-8"
        >
          <span className="font-sans text-2xs label-caps text-coral-deep" aria-hidden="true">
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
    <section className="grid grid-cols-1 border-b-4 border-cocoa lg:grid-cols-12" aria-labelledby="hero-title">
      {/* 7:5. The headline owns the wide column; the composition balances it. */}
      <div className="flex flex-col gap-8 py-12 md:py-20 lg:col-span-7 lg:border-r-4 lg:border-cocoa lg:pr-12">
        <SectionLabel number="01">Ingredient interaction engine</SectionLabel>
        <Headline as="h1" size="hero" id="hero-title">
          Find the <span className="text-coral-deep">conflicts</span> hiding in your routine.
        </Headline>
        <p className="max-w-[52ch] font-sans text-lg leading-relaxed text-cocoa">
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

      <div className="swiss-grid-pattern flex flex-col bg-sand lg:col-span-5">
        <Composition />
        <Facts items={facts} />
      </div>
    </section>
  );
}
