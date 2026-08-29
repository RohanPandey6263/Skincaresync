import { useId } from "react";
import { Icon } from "./Icon.jsx";

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
      className={`panel panel--pad-${padding} ${className}`.trim()}
      aria-labelledby={title ? headingId : undefined}
    >
      {hasHeader ? (
        <header className="panel__header">
          <div className="panel__heading">
            {eyebrow ? <p className="eyebrow">{eyebrow}</p> : null}
            {title ? (
              <h2 className="panel__title" id={headingId}>
                {icon ? <Icon name={icon} size={17} className="panel__titleIcon" /> : null}
                {title}
              </h2>
            ) : null}
            {description ? <p className="panel__description">{description}</p> : null}
          </div>
          {actions ? <div className="panel__actions">{actions}</div> : null}
        </header>
      ) : null}
      <div className="panel__body">{children}</div>
      {footer ? <footer className="panel__footer">{footer}</footer> : null}
    </Tag>
  );
}
