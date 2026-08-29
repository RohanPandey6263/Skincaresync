import { Button } from "./ui/Button.jsx";
import { Icon } from "./ui/Icon.jsx";

export function Hero({ ingredientCount, onStart }) {
  const facts = [
    ingredientCount
      ? { icon: "database", text: `${ingredientCount.toLocaleString()} ingredients indexed` }
      : null,
    { icon: "link", text: "AM, PM and cumulative exposure" },
    { icon: "beaker", text: "Every rule cited to literature" },
  ].filter(Boolean);

  return (
    <section className="hero" aria-labelledby="hero-title">
      <div className="hero__content">
        <p className="eyebrow">Ingredient interaction engine</p>
        <h1 className="hero__title" id="hero-title">
          Find the conflicts hiding in your skincare routine
        </h1>
        <p className="hero__lead">
          SkincareSync parses the real ingredient list behind every product you use, then checks
          each pair against a cited interaction database — within your morning routine, your evening
          routine, and across both.
        </p>
        <div className="hero__actions">
          <Button variant="primary" size="lg" iconAfter="arrowRight" onClick={onStart}>
            Analyze my routine
          </Button>
          <a className="hero__link" href="#catalog">
            Browse the ingredient catalog
            <Icon name="arrowRight" size={14} />
          </a>
        </div>
      </div>

      <ul className="hero__facts">
        {facts.map((fact) => (
          <li key={fact.text}>
            <Icon name={fact.icon} size={15} />
            {fact.text}
          </li>
        ))}
      </ul>
    </section>
  );
}
