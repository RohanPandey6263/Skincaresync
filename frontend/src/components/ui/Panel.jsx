import { useId } from "react";
import { SectionLabel } from "./Section.jsx";

/**
 * The surface every working view is built from: a rectangle with a thick black
 * border. Its header is a numbered label plus an uppercase title; its footer is
 * a muted strip with a dot matrix.
 *
 * One title size, deliberately: moving between tabs must not change the
 * apparent importance of the page.
 */
const PADDING = {
  none: "",
  sm: "p-5",
  md: "p-6 md:p-8",
  lg: "p-8 md:p-12",
};

export function Panel({
  number,
  title,
  description,
  eyebrow,
  actions,
  children,
  footer,
  as: Tag = "section",
  padding = "md",
  className = "",
}) {
  const headingId = useId();
  const hasHeader = Boolean(title || actions || eyebrow || number);

  return (
    <Tag
      className={`flex flex-col rounded-none border-2 border-black bg-white md:border-4 ${className}`.trim()}
      aria-labelledby={title ? headingId : undefined}
    >
      {hasHeader ? (
        <header className="flex flex-wrap items-end justify-between gap-x-8 gap-y-4 border-b-2 border-black px-6 py-5 md:border-b-4 md:px-8 md:py-6">
          <div className="flex flex-col gap-3">
            {eyebrow || number ? <SectionLabel number={number}>{eyebrow}</SectionLabel> : null}
            {title ? (
              <h2 className="font-sans text-2xl font-black uppercase tracking-tighter text-black md:text-3xl" id={headingId}>
                {title}
              </h2>
            ) : null}
            {description ? <p className="max-w-[60ch] font-sans text-sm leading-relaxed text-black/60">{description}</p> : null}
          </div>
          {actions ? <div className="flex flex-wrap items-center gap-3">{actions}</div> : null}
        </header>
      ) : null}

      <div className={PADDING[padding] ?? PADDING.md}>{children}</div>

      {footer ? (
        <footer className="swiss-dots border-t-2 border-black bg-muted px-6 py-5 md:border-t-4 md:px-8">{footer}</footer>
      ) : null}
    </Tag>
  );
}
