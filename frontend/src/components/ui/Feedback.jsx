import { Icon, IconBox } from "./Icon.jsx";

/**
 * Empty, loading and notice states. All are rectangles; tone is fill plus a
 * written label, never colour alone.
 */
export function EmptyState({ icon = "beaker", title, description, action, compact = false }) {
  return (
    <div
      className={`swiss-grid-pattern flex flex-col gap-5 border-2 border-black bg-muted ${
        compact ? "p-6" : "p-8 md:p-12"
      }`}
    >
      {icon ? <IconBox name={icon} size={compact ? "sm" : "md"} /> : null}
      <div className="flex flex-col gap-2">
        <p className="font-sans text-lg font-black uppercase tracking-tight text-black md:text-xl">{title}</p>
        {description ? <p className="max-w-[56ch] font-sans text-sm leading-relaxed text-black/60">{description}</p> : null}
      </div>
      {action ? <div>{action}</div> : null}
    </div>
  );
}

export function Skeleton({ width, height = 12, className = "" }) {
  return (
    <span
      className={`block animate-pulse bg-black/10 ${className}`.trim()}
      style={{ width, height }}
      aria-hidden="true"
    />
  );
}

export function SkeletonCard() {
  return (
    <div className="flex flex-col gap-4 border-2 border-black p-6" aria-hidden="true">
      <div className="flex gap-3">
        <Skeleton width="88px" height={22} />
        <Skeleton width="64px" height={22} />
      </div>
      <Skeleton width="72%" height={20} />
      <Skeleton width="100%" height={12} />
      <Skeleton width="86%" height={12} />
      <div className="flex gap-6 pt-2">
        <Skeleton width="40%" height={10} />
        <Skeleton width="30%" height={10} />
      </div>
    </div>
  );
}

const CALLOUT_TONES = {
  info: "border-black bg-muted text-black",
  warn: "swiss-diagonal border-black bg-white text-black",
  danger: "border-accent bg-white text-black",
  ok: "border-black bg-black text-white",
};

const CALLOUT_EDGE = {
  info: "bg-black",
  warn: "bg-black",
  danger: "bg-accent",
  ok: "bg-white",
};

export function Callout({ tone = "info", icon, title, children, className = "" }) {
  const fallbackIcon =
    icon ?? { info: "info", warn: "alertTriangle", danger: "alertOctagon", ok: "checkCircle" }[tone];

  return (
    <div className={`relative flex gap-4 border-2 py-4 pl-7 pr-5 ${CALLOUT_TONES[tone] ?? CALLOUT_TONES.info} ${className}`.trim()}>
      <span className={`absolute inset-y-0 left-0 w-2 ${CALLOUT_EDGE[tone] ?? CALLOUT_EDGE.info}`} aria-hidden="true" />
      <Icon name={fallbackIcon} size={18} strokeWidth={2.25} className="mt-0.5 shrink-0" />
      <div className="flex min-w-0 flex-col gap-2">
        {title ? <p className="font-sans text-xs label-caps">{title}</p> : null}
        {children ? <div className="font-sans text-sm leading-relaxed [&_p]:mt-2">{children}</div> : null}
      </div>
    </div>
  );
}
