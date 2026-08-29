import { Icon } from "./ui/Icon.jsx";

const STEPS = [
  {
    icon: "search",
    title: "Identify each product",
    body: "Search by brand and product name, or scan a barcode. Ingredient lists are pulled from Open Beauty Facts — nothing is typed by hand.",
  },
  {
    icon: "database",
    title: "Normalize the ingredients",
    body: "The INCI parser cleans each list and resolves synonyms against the ingredient database, so the same active is recognised under any label.",
  },
  {
    icon: "beaker",
    title: "Apply cited rules",
    body: "Every ingredient pair is checked within each routine and across AM/PM, then severity is adjusted for your skin type. Each result links to its source.",
  },
];

export function HowItWorks() {
  return (
    <section className="howItWorks" id="how-it-works" aria-labelledby="how-it-works-title">
      <div className="howItWorks__intro">
        <p className="eyebrow">How it works</p>
        <h2 id="how-it-works-title">Three deterministic steps, no guesswork</h2>
      </div>
      <ol className="howItWorks__steps">
        {STEPS.map((step, index) => (
          <li key={step.title} className="step">
            <span className="step__icon" aria-hidden="true">
              <Icon name={step.icon} size={17} />
            </span>
            <p className="step__index" aria-hidden="true">
              Step {index + 1}
            </p>
            <h3 className="step__title">{step.title}</h3>
            <p className="step__body">{step.body}</p>
          </li>
        ))}
      </ol>
    </section>
  );
}
