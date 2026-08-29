import { Icon } from "./Icon.jsx";
import { Spinner } from "./Spinner.jsx";

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
  const iconSize = size === "lg" ? 17 : 15;

  return (
    <button
      className={`btn btn--${variant} btn--${size}${block ? " btn--block" : ""}${
        loading ? " is-loading" : ""
      } ${className}`.trim()}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading ? <Spinner size={iconSize} /> : icon ? <Icon name={icon} size={iconSize} /> : null}
      {children ? <span className="btn__label">{children}</span> : null}
      {iconAfter && !loading ? <Icon name={iconAfter} size={iconSize} /> : null}
    </button>
  );
}

export function IconButton({
  icon,
  label,
  variant = "ghost",
  size = "md",
  className = "",
  ...rest
}) {
  return (
    <button
      className={`btn btn--${variant} btn--icon btn--${size} ${className}`.trim()}
      aria-label={label}
      title={label}
      {...rest}
    >
      <Icon name={icon} size={size === "sm" ? 15 : 17} />
    </button>
  );
}
