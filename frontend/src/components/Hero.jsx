import { Fragment } from "react";
import { Button } from "./ui/Button.jsx";
import { Icon } from "./ui/Icon.jsx";

/**
 * Decorative constellation above the headline.
 *
 * Ornamental only — `aria-hidden`, and dropped by CSS on narrow screens where
 * it would crowd the copy it introduces. The tiles name things the engine
 * actually reasons about, so the ornament still says something true.
 *
 * `data-parallax` is the rate each tile drifts at as the hero scrolls away;
 * useHeroParallax reads it.
 */
const TILES = [
  { key: "search", icon: "search", tone: "amber", className: "heroTile--a", parallax: 0.55 },
  { key: "database", icon: "database", tone: "sage", className: "heroTile--b", parallax: 0.85 },
  { key: "beaker", icon: "beaker", tone: "accent", className: "heroTile--core", parallax: 0.18 },
  { key: "alert", icon: "alertOctagon", tone: "rust", className: "heroTile--c", parallax: 0.7 },
  { key: "spark", icon: "spark", tone: "lilac", className: "heroTile--d", parallax: 1 },
];

const TITLE = "Find the conflicts hiding in your routine";

function Constellation() {
  return (
    <div className="heroStage" aria-hidden="true" data-slide-item="zoom">
      <svg className="heroStage__wires" viewBox="0 0 1000 200" preserveAspectRatio="none">
        <path d="M120 104 H300 L430 100" />
        <path d="M196 156 L330 148 L430 112" />
        <path d="M570 100 L672 62 L790 66" />
        <path d="M570 112 L700 152 L920 132" />
        <circle cx="300" cy="104" r="4" />
        <circle cx="330" cy="148" r="4" />
        <circle cx="672" cy="62" r="4" />
        <circle cx="700" cy="152" r="4" />
      </svg>

      {TILES.map((tile) => (
        <span
          key={tile.key}
          className={`heroTile heroTile--${tile.tone} ${tile.className}`}
          data-parallax={tile.parallax}
        >
          <Icon name={tile.icon} size={tile.className === "heroTile--core" ? 38 : 22} />
        </span>
      ))}
    </div>
  );
}

/**
 * The headline is split per word so each can rise out of its own clipping box.
 * Split by word rather than by line so the reveal survives any wrap point, and
 * the spaces stay outside the boxes — inside, `overflow: hidden` eats them and
 * the words run together.
 */
function MaskedTitle() {
  const words = TITLE.split(" ");
  return (
    <h1 className="hero__title" id="hero-title" data-slide-item="mask">
      {words.map((word, index) => (
        <Fragment key={`${word}-${index}`}>
          <span className="maskWord">
            <span className="maskWord__inner">{word}</span>
          </span>
          {/* The space must sit OUTSIDE the clipping box: inside it,
              `overflow: hidden` swallows it and the words run together. */}
          {index < words.length - 1 ? " " : null}
        </Fragment>
      ))}
    </h1>
  );
}

export function Hero({ ingredientCount, productCount, interactionCount, onStart }) {
  const facts = [
    ingredientCount
      ? { icon: "database", text: `${ingredientCount.toLocaleString()} ingredients indexed` }
      : null,
    productCount
      ? { icon: "search", text: `${productCount.toLocaleString()} product ingredient lists` }
      : null,
    interactionCount
      ? { icon: "book", text: `${interactionCount.toLocaleString()} cited interaction rules` }
      : null,
    { icon: "link", text: "AM, PM and cumulative exposure" },
  ].filter(Boolean);

  return (
    <section className="hero" aria-labelledby="hero-title" data-slide>
      <Constellation />

      <div className="hero__content">
        <p className="eyebrow" data-slide-item="fade">
          Ingredient interaction engine
        </p>

        <MaskedTitle />

        <p className="hero__lead" data-slide-item="rise">
          SkincareSync parses the real ingredient list behind every product you use, then checks
          each pair against a cited interaction database — within your morning routine, your
          evening routine, and across both.
        </p>

        <div className="hero__actions" data-slide-item="pushRight">
          <Button variant="primary" size="lg" iconAfter="arrowRight" onClick={onStart}>
            Analyze my routine
          </Button>
          <a className="hero__link" href="#catalog">
            Browse the ingredient catalog
            <Icon name="arrowRight" size={14} />
          </a>
        </div>

        <ul className="hero__facts" data-slide-item="wipeUp">
          {facts.map((fact) => (
            <li key={fact.text}>
              <Icon name={fact.icon} size={15} />
              {fact.text}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
