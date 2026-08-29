import { Icon } from "./Icon.jsx";

export function EmptyState({ icon = "beaker", title, description, action, compact = false }) {
  return (
    <div className={`emptyState${compact ? " emptyState--compact" : ""}`}>
      {icon ? (
        <span className="emptyState__icon" aria-hidden="true">
          <Icon name={icon} size={compact ? 18 : 22} />
        </span>
      ) : null}
      <div className="emptyState__text">
        <p className="emptyState__title">{title}</p>
        {description ? <p className="emptyState__description">{description}</p> : null}
      </div>
      {action ? <div className="emptyState__action">{action}</div> : null}
    </div>
  );
}

export function Skeleton({ width, height = 12, radius = "var(--radius-sm)", className = "" }) {
  return (
    <span
      className={`skeleton ${className}`.trim()}
      style={{ width, height, borderRadius: radius }}
      aria-hidden="true"
    />
  );
}

export function SkeletonCard() {
  return (
    <div className="skeletonCard" aria-hidden="true">
      <div className="skeletonCard__row">
        <Skeleton width="88px" height={20} radius="var(--radius-full)" />
        <Skeleton width="64px" height={20} radius="var(--radius-full)" />
      </div>
      <Skeleton width="72%" height={17} />
      <Skeleton width="100%" height={12} />
      <Skeleton width="86%" height={12} />
      <div className="skeletonCard__meta">
        <Skeleton width="40%" height={10} />
        <Skeleton width="30%" height={10} />
      </div>
    </div>
  );
}

export function Callout({ tone = "info", icon, title, children, className = "" }) {
  const fallbackIcon =
    icon ?? { info: "info", warn: "alertTriangle", danger: "alertOctagon", ok: "checkCircle" }[tone];

  return (
    <div className={`callout callout--${tone} ${className}`.trim()}>
      <Icon name={fallbackIcon} size={15} className="callout__icon" />
      <div className="callout__content">
        {title ? <p className="callout__title">{title}</p> : null}
        {children ? <div className="callout__body">{children}</div> : null}
      </div>
    </div>
  );
}
