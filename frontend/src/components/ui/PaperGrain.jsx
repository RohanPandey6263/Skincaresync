/**
 * Paper grain.
 *
 * A fixed fractal-noise wash over the whole viewport at 1.5% opacity. It is
 * what stops large flat areas of alabaster reading as a screen rather than a
 * surface — the warmth of the palette does not survive without some tooth
 * under it.
 *
 * This is not the 32px rule grid that used to sit on `body`: there are no
 * lines and no repeating figure, only noise below the threshold of pattern.
 *
 * `aria-hidden` and `pointer-events-none` — it must never take a click or
 * announce itself. The SVG is inline as a data URI so it costs no request and
 * cannot flash in after paint.
 */
const NOISE =
  "url(\"data:image/svg+xml,%3Csvg viewBox='0 0 400 400' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")";

export function PaperGrain() {
  return (
    <div
      aria-hidden="true"
      className="pointer-events-none fixed inset-0 z-50 opacity-[0.015]"
      style={{ backgroundImage: NOISE, backgroundRepeat: "repeat" }}
    />
  );
}
