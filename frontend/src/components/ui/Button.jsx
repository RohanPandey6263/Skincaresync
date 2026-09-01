import { Icon } from "./Icon.jsx";
import { Spinner } from "./Spinner.jsx";

/**
 * Buttons are pills with uppercase, widely-tracked labels — the system treats
 * them as small typographic marks rather than filled boxes.
 *
 * Primary is Deep Forest carrying white text at 11.9:1, and shifts to
 * Terracotta on hover. It is deliberately not Sage: white on sage is 2.97:1,
 * which cannot carry a label. Secondary uses sage darkened to 4.48:1 for the
 * same reason, keeping the hue while staying legible.
 */
const BASE =
  "inline-flex items-center justify-center gap-2.5 rounded-full font-sans " +
  "uppercase tracking-label whitespace-nowrap " +
  "transition-[background-color,color,border-color,box-shadow,transform] duration-300 ease-organic " +
  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sage " +
  "focus-visible:ring-offset-2 focus-visible:ring-offset-alabaster " +
  "disabled:cursor-not-allowed disabled:opacity-50 aria-busy:cursor-progress";

const VARIANTS = {
  primary:
    "bg-forest text-alabaster border border-forest shadow-soft " +
    "hover:not-disabled:bg-terracotta hover:not-disabled:border-terracotta " +
    "hover:not-disabled:shadow-lift active:not-disabled:translate-y-px",
  secondary:
    "bg-transparent text-muted border border-sage " +
    "hover:not-disabled:border-terracotta hover:not-disabled:text-terracotta " +
    "hover:not-disabled:bg-terracotta/5",
  ghost:
    "bg-transparent text-forest border border-transparent " +
    "hover:not-disabled:bg-forest/5 hover:not-disabled:text-forest",
  danger:
    "bg-terracotta-700 text-alabaster border border-terracotta-700 shadow-soft " +
    "hover:not-disabled:bg-terracotta hover:not-disabled:border-terracotta",
  quiet:
    "bg-linen text-forest border border-stone " +
    "hover:not-disabled:bg-clay hover:not-disabled:border-clay",
};

/* 44px is the floor for a comfortable touch target; `sm` sits below it and is
   reserved for dense desktop rows (a product line's remove control), never for
   a primary action. */
const SIZES = {
  sm: "h-9 px-4 text-[0.6875rem]",
  md: "h-11 px-6 text-xs",
  lg: "h-14 px-8 text-sm",
};

const ICON_SIZE = { sm: 14, md: 15, lg: 17 };

export function Button({
  variant = "secondary",
  size = "md",
  loading = false,
  icon,
  iconAfter,
  block = false,
  disabled = false,
  className = "",
  children,
  ...rest
}) {
  const iconSize = ICON_SIZE[size] ?? ICON_SIZE.md;

  return (
    <button
      className={[BASE, VARIANTS[variant] ?? VARIANTS.secondary, SIZES[size] ?? SIZES.md, block ? "w-full" : "", className]
        .filter(Boolean)
        .join(" ")}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading ? <Spinner size={iconSize} /> : icon ? <Icon name={icon} size={iconSize} /> : null}
      {children ? <span className="translate-y-px">{children}</span> : null}
      {/* The trailing arrow steps forward on hover — the system's one
          consistent directional cue. */}
      {iconAfter && !loading ? (
        <Icon
          name={iconAfter}
          size={iconSize}
          className="transition-transform duration-300 ease-organic group-hover:translate-x-1"
        />
      ) : null}
    </button>
  );
}

export function IconButton({ icon, label, variant = "ghost", size = "md", className = "", ...rest }) {
  const iconSize = size === "sm" ? 15 : 17;
  return (
    <button
      className={[
        BASE,
        VARIANTS[variant] ?? VARIANTS.ghost,
        size === "sm" ? "h-9 w-9" : "h-11 w-11",
        "px-0",
        className,
      ]
        .filter(Boolean)
        .join(" ")}
      aria-label={label}
      title={label}
      {...rest}
    >
      <Icon name={icon} size={iconSize} />
    </button>
  );
}
