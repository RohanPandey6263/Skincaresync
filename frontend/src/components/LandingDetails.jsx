import { Button } from "./ui/Button.jsx";
import { Icon } from "./ui/Icon.jsx";
import { CountUp } from "./ui/CountUp.jsx";

/**
 * What the engine does that a search box does not. Each claim here is one the
 * implementation actually makes good on — the parser, the scope split, the skin
 * modifier and the citation on every rule.
 */
const CAPABILITIES = [
  {
    icon: "database",
    title: "Real ingredient lists",
    body: "Search by brand and product, or scan a barcode. Lists come from Open Beauty Facts, FDA DailyMed and brand-published INCI, never typed from memory.",
  },
  {
    icon: "refresh",
    title: "Direct and cumulative scope",
    body: "Layering two actives in one routine is a different risk from meeting them twelve hours apart. Both are checked, and each result says which one it is.",
  },
  {
    icon: "user",
    title: "Tuned to your skin",
    body: "A rule carries a base severity, then escalates for reactive skin types and your selected concerns. The same pairing can read medium for one person and high for another.",
  },
  {
    icon: "book",
    title: "Every rule cited",
    body: "Each conflict, caution and synergy links to the paper behind it and carries a confidence level. Nothing is asserted without an accessible source.",
  },
];

export function LandingDetails({ catalogStats, onStart }) {
  const numbers = [
    { value: catalogStats?.ingredientCount, label: "INCI names indexed" },
    { value: catalogStats?.productCount, label: "Product ingredient lists" },
    { value: catalogStats?.interactionCount, label: "Cited interaction rules" },
    { value: 3, label: "Verdicts: conflict, caution, synergy" },
  ];

  return (
    <>
      {/* A plain section, so it takes no inner inset: its heading has to line up
          with the header, the hero and the steps above it. Only filled panels
          (the band below, the reviews) pad inward. */}
      <section
        className="flex flex-col items-center gap-12 overflow-x-clip py-16 md:gap-16 md:py-32"
        aria-labelledby="capabilities-title"
      >
        <div className="flex max-w-[62ch] flex-col items-center gap-5 text-center" data-slide-item="wipe">
          <h2 className="font-display text-section font-semibold tracking-tight text-forest text-balance">
            A rules engine, <em className="italic">not</em> a recommendation feed
          </h2>
          <p className="font-sans text-lg leading-relaxed text-subtle">
            Most routine advice is someone&rsquo;s opinion about products. This is a deterministic
            check over the ingredients those products actually contain.
          </p>
        </div>

        <ul className="grid w-full max-w-7xl grid-cols-1 gap-8 md:grid-cols-2 md:gap-12 lg:grid-cols-4">
          {CAPABILITIES.map((item, index) => (
            <li key={item.title} className={index % 2 === 1 ? "md:translate-y-12" : ""}>
              <div
                className="group flex h-full flex-col gap-4 rounded-card border border-stone bg-white p-8
                           shadow-soft transition-[transform,box-shadow] duration-500 ease-organic
                           hover:-translate-y-2 hover:shadow-bloom"
              >
                <span
                  className="grid h-14 w-14 place-items-center rounded-full bg-sage-100 text-forest
                             transition-colors duration-500 group-hover:bg-clay"
                  aria-hidden="true"
                >
                  <Icon name={item.icon} size={22} strokeWidth={1.5} />
                </span>
                <h3 className="font-display text-xl font-semibold tracking-tight text-forest">
                  {item.title}
                </h3>
                <p className="font-sans text-sm leading-relaxed text-subtle">{item.body}</p>
              </div>
            </li>
          ))}
        </ul>

        <dl
          className="grid w-full max-w-7xl grid-cols-2 gap-8 border-t border-stone pt-12 md:grid-cols-4 md:gap-12"
        >
          {numbers.map((item) => (
            <div key={item.label} className="flex flex-col gap-2">
              <dt className="font-display text-4xl font-semibold tracking-tight text-forest">
                {typeof item.value === "number" ? <CountUp value={item.value} /> : "—"}
              </dt>
              <dd className="font-sans text-sm leading-relaxed text-muted">{item.label}</dd>
            </div>
          ))}
        </dl>
      </section>

      {/* A filled panel: it bleeds to the container edge and insets its own
          content, which is why its text does not align with the plain sections. */}
      <section
        className="my-16 flex flex-col items-center gap-6 rounded-[40px] border border-sage/30
                   bg-gradient-to-br from-sage-100 via-linen to-clay/40 px-6 py-16 text-center
                   shadow-bloom md:my-32 md:px-12 md:py-24"
        aria-labelledby="cta-title"
      >
        <h2
          className="max-w-[18ch] font-display text-section font-semibold tracking-tight text-forest text-balance"
          id="cta-title"
        >
          Two products is <em className="italic">enough</em> to start
        </h2>
        <p
          className="max-w-[56ch] font-sans text-lg leading-relaxed text-subtle"
        >
          Add what you already use. The analysis runs in the browser against a cited database — no
          account needed to see your first report.
        </p>
        <span className="group inline-flex" data-slide-item="zoom">
          <Button variant="primary" size="lg" iconAfter="arrowRight" onClick={onStart}>
            Analyze my routine
          </Button>
        </span>
      </section>
    </>
  );
}
