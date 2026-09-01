import { Icon } from "./Icon.jsx";

/**
 * A badge is a pill of tinted paper with darkened text of the same hue.
 *
 * Each tone pairs a 100-step wash with a 700-step label, both solved for 4.5:1
 * against Soft Clay rather than against the page — a badge frequently sits on
 * a tinted card, and solving against the page left these at 4.09:1.
 */
const TONES = {
  neutral: "bg-linen text-subtle border-stone",
  ok: "bg-sage-100 text-muted border-sage/40",
  warn: "bg-clay-100 text-clay-700 border-clay/60",
  info: "bg-clay-100 text-clay-700 border-clay/60",
  danger: "bg-terracotta-100 text-terracotta-700 border-terracotta/40",
};

const SIZES = {
  sm: "h-6 gap-1.5 px-3 text-2xs",
  md: "h-7 gap-2 px-3.5 text-xs",
};

export function Badge({ tone = "neutral", size = "md", icon, className = "", children }) {
  return (
    <span
      className={`inline-flex items-center rounded-full border font-sans font-medium
                  ${TONES[tone] ?? TONES.neutral} ${SIZES[size] ?? SIZES.md} ${className}`.trim()}
    >
      {icon ? <Icon name={icon} size={size === "sm" ? 12 : 13} strokeWidth={1.75} /> : null}
      {children}
    </span>
  );
}

export function Chip({ className = "", children, ...rest }) {
  return (
    <span
      className={`inline-flex items-center gap-2 rounded-full border border-stone bg-linen px-3.5 py-1.5
                  font-sans text-2xs text-subtle ${className}`.trim()}
      {...rest}
    >
      {children}
    </span>
  );
}
