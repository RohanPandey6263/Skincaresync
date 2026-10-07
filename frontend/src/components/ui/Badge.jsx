import { Icon } from "./Icon.jsx";

/**
 * A badge is a rectangle with a word in it. Tone is carried by fill and by the
 * word itself, never by hue alone: danger is red, ok is black, warn is white
 * with diagonal hatching, neutral is muted gray.
 */
const TONES = {
  neutral: "border-cocoa bg-sand text-ink",
  ok: "border-cocoa bg-mint text-ink",
  warn: "border-cocoa bg-paper text-ink swiss-diagonal",
  info: "border-cocoa bg-paper text-ink",
  danger: "border-coral bg-coral text-ink",
};

const SIZES = {
  sm: "h-6 gap-1.5 px-2 text-[0.625rem]",
  md: "h-7 gap-2 px-2.5 text-2xs",
};

export function Badge({ tone = "neutral", size = "md", icon, className = "", children }) {
  return (
    <span
      className={`inline-flex items-center rounded-none border-2 font-sans label-caps
                  ${TONES[tone] ?? TONES.neutral} ${SIZES[size] ?? SIZES.md} ${className}`.trim()}
    >
      {icon ? <Icon name={icon} size={size === "sm" ? 11 : 13} strokeWidth={2.5} /> : null}
      {children}
    </span>
  );
}

/** A labelled item in a set (ingredient names, tokens). Bordered, never filled. */
export function Chip({ className = "", children, ...rest }) {
  return (
    <span
      className={`inline-flex items-center gap-2 rounded-none border border-cocoa bg-paper px-2.5 py-1
                  font-sans text-xs font-medium text-ink ${className}`.trim()}
      {...rest}
    >
      {children}
    </span>
  );
}
