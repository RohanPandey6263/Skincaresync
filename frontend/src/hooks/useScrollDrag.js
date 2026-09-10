import { useEffect } from "react";
import { getSmoothScroll } from "../lib/smoothScroll.js";
import { prefersReducedMotion } from "../lib/motionPrefs.js";

/** Viewport position where the deck starts assembling an approaching slide. */
const ARRIVAL_START = 0.88;

/** How much scrolling a slide lingers for, as a fraction of the viewport. */
const DRAG_SPAN = 0.68;

/** Wheel input is scaled to this inside a zone. Slow, but never zero. */
const SLOWEST = 0.08;

/** Distance over which the slowdown fades in and out, in px of scroll. */
const RAMP = 200;

/** Smoothstep: no discontinuity in velocity at either edge of a zone. */
const smooth = (t) => t * t * (3 - 2 * t);

/**
 * Slows scrolling to a crawl as each slide settles, instead of stopping it.
 *
 * This replaces the pinning that used to hold a section at the top of the
 * viewport. A pin absorbs scroll: the wheel keeps turning and the page stops
 * answering, which reads as the browser having hung. Scaling Lenis's wheel
 * input instead keeps every gesture connected to the page — it just travels
 * less far for the length of a slide's arrival, which is what the pause was
 * supposed to feel like in the first place.
 *
 * Nothing here animates an element. It changes how much scroll a gesture is
 * worth, so no element gains a second tween and nothing can be caught mid-way
 * between two competing transforms.
 *
 * The lead slide is excluded (it is already on screen at load) and so is the
 * last (its neighbour is the footer, which should arrive at full speed).
 */
export function useScrollDrag(containerRef, key) {
  useEffect(() => {
    const root = containerRef.current;
    if (!root || prefersReducedMotion()) return undefined;

    const lenis = getSmoothScroll();
    if (!lenis) return undefined;

    const baseWheel = lenis.options.wheelMultiplier ?? 1;
    const baseTouch = lenis.options.touchMultiplier ?? 1;

    let zones = [];

    const measure = () => {
      const slides = Array.from(root.querySelectorAll("[data-slide]"));
      const span = Math.round(window.innerHeight * DRAG_SPAN);
      zones = slides.slice(1, -1).map((slide) => {
        // Match the deck's `start: "top 88%"` so the resistance is felt while
        // the lower elements are rising, rather than after the slide has landed.
        const start =
          slide.getBoundingClientRect().top + window.scrollY - window.innerHeight * ARRIVAL_START;
        return { start, end: start + span };
      });
    };

    const factorAt = (scroll) => {
      let factor = 1;
      for (const zone of zones) {
        if (scroll <= zone.start - RAMP || scroll >= zone.end + RAMP) continue;
        let t = 1;
        if (scroll < zone.start) t = (scroll - (zone.start - RAMP)) / RAMP;
        else if (scroll > zone.end) t = (zone.end + RAMP - scroll) / RAMP;
        factor = Math.min(factor, 1 - (1 - SLOWEST) * smooth(Math.max(0, Math.min(1, t))));
      }
      return factor;
    };

    const apply = ({ scroll }) => {
      const factor = factorAt(scroll);
      lenis.options.wheelMultiplier = baseWheel * factor;
      lenis.options.touchMultiplier = baseTouch * factor;
    };

    measure();
    apply({ scroll: window.scrollY });

    lenis.on("scroll", apply);
    window.addEventListener("resize", measure);
    // Fonts settle after first paint and move every slide down the page.
    if (document.fonts?.ready) document.fonts.ready.then(measure).catch(() => {});

    return () => {
      lenis.off("scroll", apply);
      window.removeEventListener("resize", measure);
      lenis.options.wheelMultiplier = baseWheel;
      lenis.options.touchMultiplier = baseTouch;
    };
  }, [containerRef, key]);
}
