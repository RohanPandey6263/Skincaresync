/**
 * One place to ask whether motion is wanted.
 *
 * Read live rather than cached: a viewer can flip the OS setting while the page
 * is open, and the next slide built should honour it.
 */
export function prefersReducedMotion() {
  if (typeof window === "undefined" || !window.matchMedia) return false;
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}
