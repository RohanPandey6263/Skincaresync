import { Icon } from "./ui/Icon.jsx";

const STEPS = [
  {
    icon: "search",
    title: "Identify each product",
    body: "Search by brand and product name, or scan a barcode. Ingredient lists are pulled from trusted databases.",
  },
  {
    icon: "database",
    title: "Find the ingredients",
    body: "Our parser finds each ingredient in every list and makes sure the same active is recognised under any label.",
  },
  {
    icon: "beaker",
    title: "Apply cited rules",
    body: "Every ingredient pair is checked within each routine and across AM/PM, then severity is adjusted for your skin type. Each result links to its source.",
  },
];

export function HowItWorks() {
  return (
    <section
      className="flex flex-col items-center gap-12 overflow-x-clip py-16 md:gap-16 md:py-32"
      id="how-it-works"
      aria-labelledby="how-it-works-title"
    >
      <h2
        className="max-w-[20ch] text-center font-display text-section font-semibold tracking-tight text-forest text-balance"
        id="how-it-works-title"
      >
        Three deterministic steps, <em className="italic">no guesswork</em>
      </h2>

      {/* Staggered: the middle card drops so the row reads as grown rather than
          laid out. Only from md up — on a phone the cards stack, and an offset
          there is just a gap. */}
      <ol className="grid w-full max-w-7xl grid-cols-1 gap-8 md:grid-cols-3 md:gap-12">
        {STEPS.map((step, index) => (
          /* The offset lives on the <li> and the deck's hook on the inner
             element: GSAP writes an inline `transform`, which would overwrite
             a Tailwind translate class on the same node and silently flatten
             the stagger the moment the section animates. */
          <li key={step.title} className={index % 2 === 1 ? "md:translate-y-12" : ""}>
            <div
              className="group flex h-full flex-col gap-5 rounded-card border border-stone bg-white p-8
                         shadow-soft transition-[transform,box-shadow] duration-500 ease-organic
                         hover:-translate-y-2 hover:shadow-bloom"
            >
            {/* Icons float in pale circles rather than heavy boxes. */}
            <span
              className="grid h-14 w-14 place-items-center rounded-full bg-sage-100 text-forest
                         transition-colors duration-500 group-hover:bg-clay"
              aria-hidden="true"
            >
              <Icon name={step.icon} size={22} strokeWidth={1.5} />
            </span>

            <p className="font-sans text-2xs uppercase tracking-label text-muted" aria-hidden="true">
              Step {index + 1}
            </p>

            <h3 className="font-display text-feature font-semibold tracking-tight text-forest">
              {step.title}
            </h3>

            <p className="font-sans text-md leading-relaxed text-subtle">{step.body}</p>
            </div>
          </li>
        ))}
      </ol>
    </section>
  );
}
