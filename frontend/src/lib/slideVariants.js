/**
 * The transition vocabulary.
 *
 * Each entry is the *starting* state GSAP tweens away from, so a slide item
 * always ends at its natural, untransformed position — which is also the state
 * the page renders in if the deck never initialises.
 *
 * Elements pick one by name: `data-slide-item="wipe"`. An unrecognised or
 * missing name falls back to `rise`, so a typo degrades to the house default
 * rather than to nothing happening.
 *
 * Only transforms, opacity and clip-path appear here. Nothing triggers layout,
 * and nothing needs a filter — blur in particular is expensive enough per frame
 * to be worth doing without.
 */
export const SLIDE_VARIANTS = {
  /** Arrives without drawing attention. Notes, fine print, footers. */
  fade: { opacity: 0 },

  /** The house default: up from below. */
  rise: { opacity: 0, y: 60 },

  /** Down from above — reads as an answer landing on the thing above it. */
  drop: { opacity: 0, y: -48 },

  /** Push, direction-matched to where the element sits in its row. */
  pushRight: { opacity: 0, x: -72 },
  pushLeft: { opacity: 0, x: 72 },

  /** Masked sweep from the left. Section headers. */
  wipe: { opacity: 0, clipPath: "inset(0 100% 0 0)", x: -16 },

  /** Masked sweep upward. Good under a heading that has just wiped in. */
  wipeUp: { opacity: 0, clipPath: "inset(100% 0 0 0)", y: 24 },

  /** Grows into place. Statistics, closing calls to action. */
  zoom: { opacity: 0, scale: 0.9 },

  /** Settles back from too close — the counterpart to zoom. */
  zoomOut: { opacity: 0, scale: 1.1 },

  /** Tilts up into the plane. Cards, where depth reads well. */
  lift: {
    opacity: 0,
    y: 56,
    rotateX: 10,
    transformPerspective: 1000,
    transformOrigin: "50% 100%",
  },

  /** Swings in on its leading edge. Use sparingly — it is the loudest here. */
  flip: {
    opacity: 0,
    rotateY: -24,
    transformPerspective: 1200,
    transformOrigin: "0% 50%",
  },

  /**
   * Unrolls downward from its top edge.
   *
   * Keep this away from body copy: scaling text vertically squashes the glyphs
   * for the length of the transition, which reads as a rendering fault rather
   * than a deliberate move. It suits solid blocks and imagery.
   */
  unfurl: { opacity: 0, scaleY: 0.62, transformOrigin: "50% 0%" },

  /**
   * Word-by-word reveal. Handled specially by the deck: it targets the
   * `.maskWord__inner` spans rather than the element itself.
   */
  mask: { yPercent: 108 },
};

/** Properties that describe distance and so should shrink on small screens. */
const DISTANCE_KEYS = ["x", "y"];

/**
 * A 72px push is a modest gesture on a desktop row and a shove on a phone,
 * where the element may sit a thumb's width from the fold. Rotation and scale
 * are left alone — they read as proportion, not distance.
 */
export function travelScale(width = typeof window === "undefined" ? 1200 : window.innerWidth) {
  if (width < 600) return 0.45;
  if (width < 900) return 0.7;
  return 1;
}

export function resolveVariant(name, scale = 1) {
  const base = SLIDE_VARIANTS[name] ?? SLIDE_VARIANTS.rise;
  if (scale === 1) return { ...base };

  const scaled = { ...base };
  DISTANCE_KEYS.forEach((key) => {
    if (typeof scaled[key] === "number") scaled[key] = scaled[key] * scale;
  });
  return scaled;
}
