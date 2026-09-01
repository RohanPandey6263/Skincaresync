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

/** One per step, so the row assembles from three directions. */
const STEP_MOTION = ["pushRight", "lift", "pushLeft"];

export function HowItWorks() {
  return (
    <section className="howItWorks" id="how-it-works" aria-labelledby="how-it-works-title" data-slide>
      <div className="howItWorks__intro" data-slide-item="wipe">
        <p className="eyebrow">How it works</p>
        <h2 id="how-it-works-title">Three deterministic steps, no guesswork</h2>
      </div>
      <ol className="howItWorks__steps">
        {STEPS.map((step, index) => (
          <li key={step.title} className="step" data-slide-item={STEP_MOTION[index]}>
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
