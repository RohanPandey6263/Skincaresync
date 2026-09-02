/**
 * Structural typography shared by every page: the numbered section label, the
 * page container and the massive uppercase heading. Kept together so the
 * numbering system ("01. System", "02. Method") has one implementation.
 */

export function Container({ className = "", children, as: Tag = "div" }) {
  return <Tag className={`mx-auto w-full max-w-7xl px-6 md:px-10 ${className}`.trim()}>{children}</Tag>;
}

export function SectionLabel({ number, className = "", children }) {
  if (!number && !children) return null;
  return (
    <p className={`flex items-center gap-3 font-sans text-xs label-caps text-black ${className}`.trim()}>
      {number ? <span className="text-accent-text">{number}.</span> : null}
      {children}
    </p>
  );
}

/** The display heading: uppercase, black weight, negative tracking. */
export function Headline({ as: Tag = "h2", size = "section", className = "", id, children }) {
  const sizes = {
    hero: "text-hero",
    display: "text-display",
    section: "text-section",
    feature: "text-feature",
  };
  return (
    <Tag className={`font-sans font-black uppercase text-black ${sizes[size] ?? sizes.section} ${className}`.trim()} id={id}>
      {children}
    </Tag>
  );
}

/** A horizontal rule with real weight. */
export function Rule({ className = "", thick = false }) {
  return <hr className={`m-0 border-0 bg-black ${thick ? "h-1" : "h-0.5"} ${className}`.trim()} aria-hidden="true" />;
}
