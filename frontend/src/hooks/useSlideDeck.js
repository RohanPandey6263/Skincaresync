import { useEffect } from "react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { prefersReducedMotion } from "../lib/motionPrefs.js";
import { resolveVariant, travelScale } from "../lib/slideVariants.js";

gsap.registerPlugin(ScrollTrigger);

/** Spacing between one item's entrance and the next, in timeline seconds. */
const STAGGER = 0.09;

const EASE = "power2.out";

/**
 * Reads an item's chosen transition.
 *
 * `data-slide-item="wipe"` picks a variant; a bare `data-slide-item` takes the
 * house default. Keeping the choice in the markup means a section's motion is
 * legible where its content is, instead of in a lookup table somewhere else.
 */
function variantName(element) {
  return element.dataset.slideItem || "rise";
}

/**
 * Builds one slide's entrance as a timeline.
 *
 * A single `gsap.from(items, ...)` cannot do this: every element would have to
 * share one starting state. Adding each item to a timeline at its own offset
 * keeps the stagger while letting each element arrive its own way.
 */
function buildEntrance(timeline, items, scale) {
  items.forEach((item, index) => {
    const name = variantName(item);
    const at = index * STAGGER;

    if (name === "mask") {
      // The mask variant animates the word boxes inside the heading, not the
      // heading itself — the clipping is per word.
      const words = item.querySelectorAll(".maskWord__inner");
      if (words.length) {
        timeline.from(
          words,
          { yPercent: 108, duration: 0.9, ease: EASE, stagger: 0.055 },
          at,
        );
        return;
      }
    }

    timeline.from(item, { ...resolveVariant(name, scale), duration: 0.9, ease: EASE }, at);
  });
}

/**
 * Turns the landing page into a deck.
 *
 * Each `[data-slide]` section assembles its contents on the way in, scrubbed
 * against scroll position, and finishes before it settles at the top. A slide
 * lands finished.
 *
 * NOTHING IS PINNED. Sections were previously held at the top of the viewport
 * for about half a screen. The hold reads as a stall rather than a beat:
 * because ScrollTrigger's pin spacer absorbs the scroll, the section above
 * stays frozen on screen while the wheel keeps turning and nothing responds.
 * Scrolling should never stop answering the input it is given.
 *
 * The pause itself was worth keeping, so it moved to `useScrollDrag`, which
 * slows the wheel to a crawl over the same stretch instead of swallowing it.
 *
 * EXACTLY ONE TWEEN TOUCHES ANY ELEMENT. An earlier version also faded and
 * scaled each whole section as the next arrived, so every item carried its own
 * entrance *and* inherited a second, opposing animation from its parent. The
 * two compounded, and content could be caught dimming while still arriving.
 *
 * Everything is scrubbed, which means every visual state is derived from scroll
 * position. Flicking, dragging the scrollbar or refreshing part-way down all
 * land on the correct state; there is no enter-once trigger that can be missed
 * and leave a section stranded invisible.
 */
export function useSlideDeck(containerRef, key) {
  useEffect(() => {
    const root = containerRef.current;
    if (!root) return undefined;

    // Reduced motion: no pinning, no transforms, nothing to clean up. The
    // markup is already visible, so this is a complete, static experience.
    if (prefersReducedMotion()) return undefined;

    const context = gsap.context((self) => {
      const slides = self.selector("[data-slide]");
      const scale = travelScale();

      slides.forEach((slide, index) => {
        const items = Array.from(slide.querySelectorAll("[data-slide-item]"));
        if (!items.length) return;

        const isLead = index === 0;

        if (isLead) {
          // Already on screen at load, so it plays on arrival rather than on
          // scroll -- there is no approach to scrub against.
          buildEntrance(gsap.timeline(), items, scale);
        } else {
          buildEntrance(
            gsap.timeline({
              scrollTrigger: {
                trigger: slide,
                start: "top 88%",
                end: "top 42%",
                scrub: 0.6,
                invalidateOnRefresh: true,
              },
            }),
            items,
            scale,
          );

        }
      });

    }, containerRef);

    // Pinning changes document height, so measurements taken before fonts and
    // images settle are wrong. Refresh once layout has stabilised.
    const refresh = () => ScrollTrigger.refresh();
    const timer = window.setTimeout(refresh, 250);
    if (document.fonts?.ready) document.fonts.ready.then(refresh).catch(() => {});

    return () => {
      window.clearTimeout(timer);
      context.revert();
    };
  }, [containerRef, key]);
}
