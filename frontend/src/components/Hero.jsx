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
 * useHeroParallax reads it. `data-slide-item` is read by useSlideDeck. Both
 * attributes are load-bearing — the motion breaks without them.
 */
/**
 * The constellation is one coordinate system.
 *
 * Previously the wires lived in a fixed 1000x200 viewBox while the tiles were
 * positioned with independent CSS percentages, so the two only lined up at one
 * viewport width — at any other size the lines stopped short of the tiles they
 * were supposed to connect. Node positions now drive both the tile placement
 * and the curve endpoints, so a wire cannot miss its tile.
 *
 * The SVG stretches with `preserveAspectRatio="none"` so a node at x=210 and a
 * tile at 21% land on the same pixel at every width. Stretching would also
 * distort the strokes, so the paths carry `vector-effect="non-scaling-stroke"`
 * and the node dots are drawn in HTML, where a circle stays a circle.
 */
const VIEW = { w: 1000, h: 240 };

const CORE = { x: 500, y: 98 };

const NODES = [
  { key: "search", icon: "search", x: 96, y: 92, tint: "bg-clay/50", parallax: 0.55 },
  { key: "database", icon: "database", x: 214, y: 168, tint: "bg-sage-100", parallax: 0.85 },
  { key: "alert", icon: "alertOctagon", x: 786, y: 74, tint: "bg-terracotta-100", parallax: 0.7 },
  { key: "spark", icon: "spark", x: 908, y: 150, tint: "bg-linen", parallax: 1 },
];

const pct = (value, axis) => `${(value / VIEW[axis]) * 100}%`;

/**
 * A vine rather than a wire: the system asks for lines that meander. The
 * control points bow each curve away from the straight run between node and
 * core, and the bow flips with the direction of travel so the four strands
 * splay outward instead of stacking into a bundle.
 */
function vine(node) {
  const dx = CORE.x - node.x;
  const bow = node.y < CORE.y ? -26 : 26;
  return `M ${node.x} ${node.y} C ${node.x + dx * 0.42} ${node.y + bow}, ${
    CORE.x - dx * 0.3
  } ${CORE.y - bow * 0.6}, ${CORE.x} ${CORE.y}`;
}

const TITLE = ["Find", "the", "conflicts", "hiding", "in", "your", "routine"];

/* The system asks for italic emphasis on a single word. "conflicts" is the
   noun the whole product turns on, so it takes the italic. */
const EMPHASIS = "conflicts";

function Constellation() {
  return (
    <div
      className="relative hidden w-full max-w-[1000px] md:block"
      style={{ aspectRatio: `${VIEW.w} / ${VIEW.h}` }}
      aria-hidden="true"
      data-slide-item="zoom"
    >
      <svg
        className="absolute inset-0 h-full w-full overflow-visible"
        viewBox={`0 0 ${VIEW.w} ${VIEW.h}`}
        preserveAspectRatio="none"
        focusable="false"
      >
        {NODES.map((node) => (
          <path
            key={node.key}
            d={vine(node)}
            className="fill-none stroke-clay"
            strokeWidth="1.25"
            vectorEffect="non-scaling-stroke"
          />
        ))}
      </svg>

      {/* Midpoint beads, in HTML so the stretch cannot turn them into ellipses. */}
      {NODES.map((node) => (
        <span
          key={`bead-${node.key}`}
          className="absolute h-[7px] w-[7px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-clay"
          style={{
            left: pct((node.x + CORE.x) / 2, "w"),
            top: pct((node.y + CORE.y) / 2 + (node.y < CORE.y ? -9 : 9), "h"),
          }}
        />
      ))}

      {/* The core is an arch — the system's signature shape, at ornament scale. */}
      <span
        className="absolute grid h-[116px] w-[116px] -translate-x-1/2 -translate-y-1/2 place-items-center
                   rounded-t-full rounded-b-[40px] bg-forest text-alabaster shadow-bloom"
        style={{ left: pct(CORE.x, "w"), top: pct(CORE.y, "h") }}
        data-parallax="0.18"
      >
        <Icon name="beaker" size={38} strokeWidth={1.5} />
      </span>

      {NODES.map((node) => (
        <span
          key={node.key}
          className={`absolute grid h-[62px] w-[62px] -translate-x-1/2 -translate-y-1/2 place-items-center
                      rounded-[20px] text-forest shadow-soft ${node.tint}`}
          style={{ left: pct(node.x, "w"), top: pct(node.y, "h") }}
          data-parallax={node.parallax}
        >
          <Icon name={node.icon} size={22} strokeWidth={1.5} />
        </span>
      ))}
    </div>
  );
}

/**
 * The headline carries the system's italic emphasis on a single word:
 * "conflicts" is the noun the whole product turns on.
 */
function Headline() {
  return (
    <h1
      className="max-w-[16ch] font-display text-hero font-semibold tracking-tight text-forest text-balance"
      id="hero-title"
    >
      Find the <em className="italic">conflicts</em> hiding in your routine
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
    <section
      className="flex flex-col items-center gap-8 py-16 md:gap-10 md:py-32"
      aria-labelledby="hero-title"
      data-slide
    >
      <Constellation />

      <div className="flex flex-col items-center gap-8 text-center">
        <Headline />

        {/* Lead and facts share one measure, so the hairline rule lines up with
            the paragraph edges above it. The actions sit outside that measure —
            constraining them to the text column wrapped the two controls onto
            separate lines. */}
        <p className="max-w-[60ch] font-sans text-lg leading-relaxed text-subtle text-pretty">
            SkincareSync parses the real ingredient list behind every product you use, then checks
          each pair against a cited interaction database — within your morning routine, your
          evening routine, and across both.
        </p>

        <div className="flex flex-wrap items-center justify-center gap-6">
          <span className="group inline-flex">
            <Button variant="primary" size="lg" iconAfter="arrowRight" onClick={onStart}>
              Analyze my routine
            </Button>
          </span>
          <a
              className="group inline-flex items-center gap-2 font-sans text-xs uppercase tracking-label
                         text-muted underline-offset-8 transition-colors duration-300
                         hover:text-terracotta hover:underline focus-visible:outline-none
                         focus-visible:ring-2 focus-visible:ring-sage focus-visible:ring-offset-4
                         focus-visible:ring-offset-alabaster"
              href="#catalog"
            >
            Browse the ingredient catalog
            <Icon
              name="arrowRight"
              size={14}
              className="transition-transform duration-300 ease-organic group-hover:translate-x-1"
            />
          </a>
        </div>

          {/* A grid rather than flex-wrap: two aligned columns instead of four
              items centring themselves independently on each row. */}
        <ul className="grid w-full max-w-[60ch] grid-cols-1 gap-x-10 gap-y-3 border-t border-stone pt-8 sm:grid-cols-2">
          {facts.map((fact) => (
            <li key={fact.text} className="inline-flex items-center gap-2.5 font-sans text-sm text-muted">
              <Icon name={fact.icon} size={15} strokeWidth={1.5} className="shrink-0 text-sage" />
              {fact.text}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
