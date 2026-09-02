import { Button } from "./ui/Button.jsx";
import { Icon, IconBox } from "./ui/Icon.jsx";
import { Headline, SectionLabel } from "./ui/Section.jsx";
import { SOURCES } from "./SiteFooter.jsx";
import { RESULT_GROUPS } from "../lib/constants.js";

/**
 * What the engine does that a search box does not. Each claim here is one the
 * implementation actually makes good on: the parser, the scope split, the skin
 * modifier and the citation on every rule.
 */
const CAPABILITIES = [
  {
    icon: "database",
    title: "Real ingredient lists",
    body: "Search by brand and product, or scan a barcode. Lists come from Open Beauty Facts, FDA DailyMed and brand-published INCI.",
  },
  {
    icon: "refresh",
    title: "Direct and cumulative scope",
    body: "Layering two actives in one routine is a different risk from meeting them twelve hours apart. Both are checked, and each result says which.",
  },
  {
    icon: "user",
    title: "Tuned to your skin",
    body: "A rule carries a base severity, then escalates for reactive skin types and your selected concerns. The same pair can read medium for one person and high for another.",
  },
  {
    icon: "book",
    title: "Every rule cited",
    body: "Each conflict, caution and synergy links to the paper behind it and carries a confidence level. Nothing is asserted without a source.",
  },
];

/** Four bordered cells. A 4px black grid drawn with gaps over a black ground. */
function Capabilities() {
  return (
    <ul className="grid grid-cols-1 gap-1 border-4 border-ink bg-ink md:grid-cols-2 lg:grid-cols-4">
      {CAPABILITIES.map((item, index) => (
        <li key={item.title} className="group flex flex-col gap-6 bg-paper p-8 transition-colors duration-150 hover:bg-cocoa hover:text-paper">
          <div className="flex items-start justify-between">
            <IconBox name={item.icon} className="transition-colors duration-150 group-hover:border-paper group-hover:bg-paper group-hover:text-coral-deep" />
            <Icon
              name="arrowRight"
              size={22}
              strokeWidth={2.5}
              className="-rotate-45 transition-transform duration-150 ease-linear group-hover:rotate-0"
            />
          </div>
          <div className="flex flex-col gap-3">
            <p className="font-sans text-2xs label-caps opacity-60" aria-hidden="true">
              {String(index + 1).padStart(2, "0")}
            </p>
            <h3 className="font-sans text-xl font-black uppercase tracking-tight">{item.title}</h3>
            <p className="font-sans text-sm leading-relaxed opacity-80">{item.body}</p>
          </div>
        </li>
      ))}
    </ul>
  );
}

/** The catalog in numbers. Static figures: the count is the content. */
function Numbers({ items }) {
  return (
    <dl className="grid grid-cols-2 gap-1 border-4 border-ink bg-ink lg:grid-cols-4">
      {items.map((item) => (
        <div key={item.label} className="group flex flex-col gap-4 bg-ink p-6 text-paper transition-colors duration-150 hover:bg-cocoa md:p-8">
          <div className="flex items-start justify-between gap-4">
            <dd className="order-1 origin-left font-sans text-5xl font-black leading-none tracking-tighter transition-transform duration-150 ease-linear group-hover:scale-105 md:text-7xl">
              {typeof item.value === "number" ? item.value.toLocaleString() : "—"}
            </dd>
            <Icon name="plus" size={22} strokeWidth={2.5} className="order-2 shrink-0 transition-transform duration-150 ease-linear group-hover:rotate-90" />
          </div>
          <dt className="font-sans text-2xs label-caps text-paper/70">{item.label}</dt>
        </div>
      ))}
    </dl>
  );
}

export function LandingDetails({ catalogStats, onStart }) {
  const numbers = [
    { value: catalogStats?.ingredientCount, label: "INCI names indexed" },
    { value: catalogStats?.productCount, label: "Product ingredient lists" },
    { value: catalogStats?.interactionCount, label: "Cited interaction rules" },
    { value: 3, label: "Verdicts: conflict, caution, synergy" },
  ];

  return (
    <>
      <section className="flex flex-col gap-12 border-b-4 border-ink py-16 md:py-24" aria-labelledby="capabilities-title">
        <div className="grid grid-cols-1 gap-8 lg:grid-cols-12">
          <div className="flex flex-col gap-6 lg:col-span-7">
            <SectionLabel number="03">Advantages</SectionLabel>
            <Headline id="capabilities-title">A rules engine, not a recommendation feed.</Headline>
          </div>
          <p className="max-w-[44ch] self-end font-sans text-base leading-relaxed text-ink/70 lg:col-span-5">
            Most routine advice is someone&rsquo;s opinion about products. This is a deterministic check over the
            ingredients those products actually contain.
          </p>
        </div>

        <Capabilities />
        <Numbers items={numbers} />
      </section>

      {/* The one black band on the page. Black takes no pattern; the type is the texture. */}
      <section className="grid grid-cols-1 gap-8 border-b-4 border-ink bg-ink px-8 py-16 text-paper md:px-12 md:py-24 lg:grid-cols-12" aria-labelledby="cta-title">
        <div className="flex flex-col gap-6 lg:col-span-8">
          <SectionLabel number="04" className="text-paper [&>span]:text-coral-deep">
            Start
          </SectionLabel>
          <Headline as="h2" size="display" id="cta-title" className="text-paper">
            Two products is enough to start.
          </Headline>
        </div>
        <div className="flex flex-col justify-end gap-6 lg:col-span-4">
          <p className="font-sans text-base leading-relaxed text-paper/70">
            Add what you already use. The analysis runs against a cited database. No account is needed to see your
            first report.
          </p>
          <Button variant="accent" size="lg" iconAfter="arrowRight" onClick={onStart}>
            Analyze my routine
          </Button>
        </div>
      </section>
    </>
  );
}

const VERDICT_SWATCH = {
  conflicts: "bg-coral",
  cautions: "swiss-diagonal border-2 border-ink bg-paper",
  synergies: "swiss-dots border-2 border-ink bg-mint",
};

/**
 * What a report can say, and where its facts come from. Objective content in
 * place of testimonials: the legend the report uses, and the databases it reads.
 */
export function Evidence() {
  return (
    <section className="grid grid-cols-1 gap-12 py-16 md:py-24 lg:grid-cols-12 lg:gap-16" aria-labelledby="evidence-title">
      <div className="flex flex-col gap-8 lg:col-span-5">
        <div className="flex flex-col gap-6">
          <SectionLabel number="05">Evidence</SectionLabel>
          <Headline id="evidence-title">Three verdicts. Four sources.</Headline>
        </div>
        <ul className="flex flex-col border-t-4 border-ink">
          {RESULT_GROUPS.map((group) => (
            <li key={group.key} className="grid grid-cols-[2.5rem_1fr] items-start gap-5 border-b-2 border-ink py-5">
              <span className={`mt-1 h-8 w-8 ${VERDICT_SWATCH[group.key]}`} aria-hidden="true" />
              <div className="flex flex-col gap-1">
                <p className="font-sans text-base font-black uppercase tracking-tight text-ink">{group.title}</p>
                <p className="font-sans text-sm leading-relaxed text-ink/70">{group.description}</p>
              </div>
            </li>
          ))}
        </ul>
      </div>

      <div className="swiss-grid-pattern flex flex-col border-4 border-ink bg-sand lg:col-span-7">
        <p className="border-b-2 border-ink px-6 py-4 font-sans text-2xs label-caps text-ink md:px-8">Data sources</p>
        <ul className="flex flex-col">
          {SOURCES.map((source, index) => (
            <li key={source.href} className="border-b-2 border-ink last:border-b-0">
              <a
                className="group grid grid-cols-[3rem_1fr_auto] items-center gap-4 px-6 py-5 no-underline transition-colors duration-150 hover:bg-ink hover:text-paper md:px-8"
                href={source.href}
                target="_blank"
                rel="noreferrer noopener"
              >
                <span className="font-sans text-2xs label-caps text-coral-deep group-hover:text-coral-deep" aria-hidden="true">
                  {String(index + 1).padStart(2, "0")}
                </span>
                <span className="flex flex-col gap-1">
                  <span className="font-sans text-base font-black uppercase tracking-tight">{source.label}</span>
                  <span className="font-sans text-xs opacity-70">{source.role}</span>
                </span>
                <Icon name="arrowUpRight" size={20} strokeWidth={2.5} />
              </a>
            </li>
          ))}
        </ul>
        <p className="mt-auto px-6 py-4 font-sans text-xs leading-relaxed text-ink/60 md:px-8">
          Ingredient records are used under the Open Database License. Packaging remains the source of truth for any
          product.
        </p>
      </div>
    </section>
  );
}
