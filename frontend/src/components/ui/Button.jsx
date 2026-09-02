import { Icon } from "./Icon.jsx";
import { Spinner } from "./Spinner.jsx";
import { Link } from "../../lib/router.jsx";

/**
 * Buttons are rectangles with a 2px border and an uppercase, tracked label.
 *
 * Interaction is a full colour inversion, never a fade: primary snaps from
 * black to Swiss Red, secondary from white to black. No scale, no shadow.
 */
const BASE =
  "inline-flex items-center justify-center gap-3 rounded-none border-2 font-sans label-caps " +
  "whitespace-nowrap transition-colors duration-150 ease-linear select-none " +
  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 " +
  "disabled:cursor-not-allowed disabled:opacity-40 aria-busy:cursor-progress";

const VARIANTS = {
  primary: "border-black bg-black text-white hover:not-disabled:border-accent hover:not-disabled:bg-accent",
  secondary: "border-black bg-white text-black hover:not-disabled:bg-black hover:not-disabled:text-white",
  accent: "border-accent bg-accent text-white hover:not-disabled:border-black hover:not-disabled:bg-black",
  ghost: "border-transparent bg-transparent text-black hover:not-disabled:bg-muted",
  inverse: "border-white bg-transparent text-white hover:not-disabled:bg-white hover:not-disabled:text-black",
};

/* 44px is the floor for a touch target. `sm` sits below it and is reserved
   for dense desktop rows, never for a primary action. */
const SIZES = {
  sm: "h-9 px-4 text-[0.6875rem]",
  md: "h-11 px-6 text-xs",
  lg: "h-14 px-8 text-sm md:h-16",
};

const ICON_SIZE = { sm: 14, md: 16, lg: 18 };

function classes({ variant, size, block, className }) {
  return [BASE, VARIANTS[variant] ?? VARIANTS.secondary, SIZES[size] ?? SIZES.md, block ? "w-full" : "", className]
    .filter(Boolean)
    .join(" ");
}

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
      className={classes({ variant, size, block, className })}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading ? <Spinner size={iconSize} /> : icon ? <Icon name={icon} size={iconSize} strokeWidth={2.25} /> : null}
      {children}
      {iconAfter && !loading ? <Icon name={iconAfter} size={iconSize} strokeWidth={2.25} /> : null}
    </button>
  );
}

/** A router link that looks like a button. Use for navigation, never for actions. */
export function ButtonLink({ to, variant = "secondary", size = "md", block = false, className = "", children, ...rest }) {
  return (
    <Link to={to} className={classes({ variant, size, block, className })} {...rest}>
      {children}
    </Link>
  );
}

/** A plain anchor that looks like a button, for external and top-level navigations. */
export function AnchorButton({ href, variant = "secondary", size = "md", block = false, className = "", children, ...rest }) {
  return (
    <a href={href} className={classes({ variant, size, block, className })} {...rest}>
      {children}
    </a>
  );
}

export function IconButton({ icon, label, variant = "ghost", size = "md", className = "", ...rest }) {
  const iconSize = size === "sm" ? 16 : 18;
  return (
    <button
      className={[BASE, VARIANTS[variant] ?? VARIANTS.ghost, size === "sm" ? "h-9 w-9" : "h-11 w-11", "px-0", className]
        .filter(Boolean)
        .join(" ")}
      aria-label={label}
      title={label}
      {...rest}
    >
      <Icon name={icon} size={iconSize} strokeWidth={2.25} />
    </button>
  );
}
