import { useEffect } from "react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { prefersReducedMotion } from "../lib/motionPrefs.js";

gsap.registerPlugin(ScrollTrigger);

/** Distance a tile at rate 1 travels over the hero's exit, in px. */
const DRIFT = 220;

/**
 * Drifts the hero ornament apart as the hero scrolls away.
 *
 * Each `[data-parallax]` tile carries its own rate, so the constellation
 * separates into layers on the way out instead of leaving as one block: the
 * core tile is slowest (0.18) and reads as the deepest, the outer tiles lead.
 * The rate lives in the markup next to the tile it belongs to, which is where
 * `Hero.jsx` documents it.
 *
 * Scrubbed, like everything else in the deck, so the state is derived purely
 * from scroll position — refreshing part-way down the page lands on the right
 * frame rather than on a half-played entrance.
 *
 * This tweens the tiles; `useSlideDeck` tweens `.heroStage`, their parent, for
 * its entrance. That keeps the deck's one-tween-per-element rule intact — the
 * two transforms compose rather than fight over the same element.
 */
export function useHeroParallax(containerRef, key) {
  useEffect(() => {
    const root = containerRef.current;
    if (!root) return undefined;

    // Nothing here is load-bearing: the tiles are ornamental and already in
    // place, so reduced motion simply leaves them where CSS put them.
    if (prefersReducedMotion()) return undefined;

    const context = gsap.context((self) => {
      const tiles = self.selector("[data-parallax]");
      if (!tiles.length) return;

      // Below 900px the stage is `display: none`, so there is nothing to drift
      // and no measurable trigger to hang it off.
      const hero = tiles[0].closest("[data-slide]");
      if (!hero) return;

      tiles.forEach((tile) => {
        const rate = Number.parseFloat(tile.dataset.parallax);
        if (!Number.isFinite(rate) || rate === 0) return;

        // `y` only. The core tile is centred with `translateX(-50%)`; GSAP
        // reads that existing transform and carries the x offset through, so
        // touching x here would fight the centring.
        gsap.to(tile, {
          y: -DRIFT * rate,
          ease: "none",
          scrollTrigger: {
            trigger: hero,
            start: "top top",
            end: "bottom top",
            scrub: true,
            invalidateOnRefresh: true,
          },
        });
      });
    }, containerRef);

    return () => context.revert();
  }, [containerRef, key]);
}
