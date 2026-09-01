import { useId } from "react";
import { Icon } from "./Icon.jsx";

/**
 * The surface every working view is built from.
 *
 * One title size, deliberately. Report headers were 28px while Analyze and
 * Catalog sat at 17px, so moving between tabs changed the apparent importance
 * of the page. Normalising upward rather than down keeps the report title
 * large and sets the scale for the whole app: panel 28 > card 24 > group
 * label 20.
 */
const PADDING = {
  none: "",
  sm: "p-5",
  md: "p-6 md:p-8",
  lg: "p-8 md:p-12",
};

const TITLE = "text-[clamp(1.375rem,1.1rem+1vw,1.75rem)]";

export function Panel({
  title,
  description,
  eyebrow,
  icon,
  actions,
  children,
  footer,
  as: Tag = "section",
  padding = "md",
  className = "",
}) {
  const headingId = useId();
  const hasHeader = Boolean(title || actions || eyebrow);

  return (
    <Tag
      className={`flex flex-col overflow-hidden rounded-card border border-stone bg-white
                  shadow-soft ${className}`.trim()}
      aria-labelledby={title ? headingId : undefined}
    >
      {hasHeader ? (
        <header className="flex flex-wrap items-start justify-between gap-4 border-b border-stone px-6 py-5 md:px-8 md:py-6">
          <div className="flex flex-col gap-1.5">
            {eyebrow ? (
              <p className="font-sans text-2xs uppercase tracking-label text-muted">{eyebrow}</p>
            ) : null}
            {title ? (
              <h2
                className={`flex items-center gap-3 font-display font-semibold tracking-tight text-forest ${TITLE}`}
                id={headingId}
              >
                {icon ? (
                  <Icon
                    name={icon}
                    size={23}
                    strokeWidth={1.5}
                    className="shrink-0 text-sage"
                  />
                ) : null}
                {title}
              </h2>
            ) : null}
            {description ? (
              <p className="font-sans text-sm leading-relaxed text-muted">{description}</p>
            ) : null}
          </div>
          {actions ? <div className="flex flex-wrap items-center gap-3">{actions}</div> : null}
        </header>
      ) : null}

      <div className={PADDING[padding] ?? PADDING.md}>{children}</div>

      {footer ? (
        <footer className="border-t border-stone bg-linen/60 px-6 py-5 md:px-8">{footer}</footer>
      ) : null}
    </Tag>
  );
}
