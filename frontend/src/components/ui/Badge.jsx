import { Icon } from "./Icon.jsx";

export function Badge({ tone = "neutral", size = "md", icon, className = "", children }) {
  return (
    <span className={`badge badge--${tone} badge--${size} ${className}`.trim()}>
      {icon ? <Icon name={icon} size={size === "sm" ? 12 : 13} /> : null}
      {children}
    </span>
  );
}

export function Chip({ className = "", children, ...rest }) {
  return (
    <span className={`chip ${className}`.trim()} {...rest}>
      {children}
    </span>
  );
}
