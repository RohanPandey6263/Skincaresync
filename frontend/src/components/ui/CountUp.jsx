import { useEffect, useRef } from "react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { prefersReducedMotion } from "../../lib/motionPrefs.js";

gsap.registerPlugin(ScrollTrigger);

/**
 * Counts from zero to `value` the first time it is reached, once.
 *
 * The final value is rendered by React, so the number is correct before any
 * animation runs, correct if the animation never runs, and correct for a
 * screen reader that reaches it mid-count. GSAP only overwrites `textContent`
 * while counting, then hands the final string back.
 */
export function CountUp({ value, duration = 1.4, className }) {
  const ref = useRef(null);

  useEffect(() => {
    const element = ref.current;
    if (!element || prefersReducedMotion() || value === 0) return undefined;

    const counter = { current: 0 };
    const format = (n) => Math.round(n).toLocaleString();

    const tween = gsap.to(counter, {
      current: value,
      duration,
      ease: "power2.out",
      paused: true,
      onUpdate: () => {
        element.textContent = format(counter.current);
      },
      onComplete: () => {
        element.textContent = format(value);
      },
    });

    const trigger = ScrollTrigger.create({
      trigger: element,
      start: "top 92%",
      once: true,
      onEnter: () => {
        element.textContent = format(0);
        tween.play();
      },
    });

    return () => {
      trigger.kill();
      tween.kill();
      element.textContent = format(value);
    };
  }, [value, duration]);

  return (
    <span ref={ref} className={className}>
      {value.toLocaleString()}
    </span>
  );
}
