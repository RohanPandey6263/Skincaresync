import Lenis from "lenis";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { prefersReducedMotion } from "./motionPrefs.js";

gsap.registerPlugin(ScrollTrigger);

/**
 * Smooth scrolling, and the ScrollTrigger wiring that has to go with it.
 *
 * Lenis is used rather than GSAP's own ScrollSmoother for one concrete reason:
 * ScrollSmoother works by transforming a wrapper element, which breaks
 * `position: sticky` and `position: fixed` inside it. This app depends on both
 * — the site header is sticky, and the analyser's action bar is sticky at the
 * bottom of the builder. Lenis animates the real `scrollTop`, so native
 * positioning keeps working and the browser's own scrollbar stays honest.
 *
 * Lenis is driven from `gsap.ticker` instead of its own rAF loop so the two
 * libraries share a single frame callback and can never disagree about the
 * current scroll position mid-frame.
 */

let instance = null;

export function startSmoothScroll() {
  if (instance || prefersReducedMotion()) return () => {};

  const lenis = new Lenis({
    duration: 1.05,
    // Long, flat ease-out: carries momentum without feeling slippery.
    easing: (t) => 1 - Math.pow(1 - t, 3),
    smoothWheel: true,
    // Touch devices already scroll smoothly, and overriding it there fights the
    // platform and costs battery.
    smoothTouch: false,
  });

  instance = lenis;
  lenis.on("scroll", ScrollTrigger.update);

  const tick = (time) => lenis.raf(time * 1000);
  gsap.ticker.add(tick);
  // Lenis owns the frame budget; GSAP's lag smoothing would fight its easing.
  gsap.ticker.lagSmoothing(0);

  return () => {
    gsap.ticker.remove(tick);
    gsap.ticker.lagSmoothing(500, 33);
    lenis.destroy();
    instance = null;
  };
}

/** The live Lenis instance, or null when smoothing is off (reduced motion). */
export function getSmoothScroll() {
  return instance;
}

/**
 * Jump to the top without Lenis animating the whole page past the user.
 *
 * Used on tab switches, where the old content is gone and gliding through it
 * would be nonsense. Falls back to native scroll when smoothing is off.
 */
export function scrollToTop() {
  if (instance) {
    instance.scrollTo(0, { immediate: true });
    return;
  }
  window.scrollTo(0, 0);
}
