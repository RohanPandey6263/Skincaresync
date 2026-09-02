import { Headline, SectionLabel } from "./ui/Section.jsx";

const STEPS = [
  {
    title: "Identify each product",
    body: "Search by brand and product name, or scan a barcode. Ingredient lists are pulled from trusted databases, never typed from memory.",
  },
  {
    title: "Find the ingredients",
    body: "The parser resolves every INCI name and synonym in each list, so the same active is recognised under any label.",
  },
  {
    title: "Apply cited rules",
    body: "Every ingredient pair is checked within each routine and across AM/PM, then severity is adjusted for your skin type. Each result links to its source.",
  },
];

/**
 * 4:8. The heading stays put on the left while the numbered method scrolls
 * past it on the right. Each step is a rule, a numeral and a sentence.
 */
export function HowItWorks() {
  return (
    <section className="grid grid-cols-1 gap-10 border-b-4 border-black py-16 md:py-24 lg:grid-cols-12 lg:gap-12" id="how-it-works" aria-labelledby="how-it-works-title">
      <div className="flex flex-col gap-6 lg:col-span-4 lg:self-start lg:sticky lg:top-28">
        <SectionLabel number="02">Method</SectionLabel>
        <Headline id="how-it-works-title">
          Three steps. <br />
          No guesswork.
        </Headline>
        <p className="max-w-[36ch] font-sans text-base leading-relaxed text-black/70">
          The engine is deterministic: the same routine and the same skin profile always produce the same report.
        </p>
      </div>

      <ol className="flex flex-col border-t-4 border-black lg:col-span-8">
        {STEPS.map((step, index) => (
          <li
            key={step.title}
            className="group grid grid-cols-[4.5rem_1fr] gap-6 border-b-2 border-black py-8 transition-colors duration-150 md:grid-cols-[8rem_1fr] md:gap-10 md:py-10"
          >
            <span
              className="font-sans text-5xl font-black leading-none tracking-tighter text-black/15 transition-colors duration-150 group-hover:text-accent md:text-7xl"
              aria-hidden="true"
            >
              {String(index + 1).padStart(2, "0")}
            </span>
            <div className="flex flex-col gap-3">
              <h3 className="font-sans text-feature font-black uppercase text-black">
                <span className="sr-only">Step {index + 1}: </span>
                {step.title}
              </h3>
              <p className="max-w-[56ch] font-sans text-base leading-relaxed text-black/70">{step.body}</p>
            </div>
          </li>
        ))}
      </ol>
    </section>
  );
}
