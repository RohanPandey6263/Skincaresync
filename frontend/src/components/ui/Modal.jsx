import { useCallback, useEffect, useId, useRef } from "react";
import { createPortal } from "react-dom";
import { IconButton } from "./Button.jsx";

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

/**
 * A dialog is a bordered rectangle on a black field. No blur, no rounding.
 */
export function Modal({ open, onClose, title, description, children, footer, labelledBy, size = "md" }) {
  const panelRef = useRef(null);
  const previouslyFocused = useRef(null);
  const generatedId = useId();
  const titleId = labelledBy ?? `${generatedId}-title`;
  const descriptionId = `${generatedId}-description`;

  const handleKeyDown = useCallback(
    (event) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        onClose();
        return;
      }
      if (event.key !== "Tab") return;
      const focusable = panelRef.current?.querySelectorAll(FOCUSABLE);
      if (!focusable?.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    },
    [onClose],
  );

  useEffect(() => {
    if (!open) return undefined;
    previouslyFocused.current = document.activeElement;
    const { overflow } = document.body.style;
    document.body.style.overflow = "hidden";

    // The Tab trap only constrains keyboard focus; marking the page inert keeps
    // a screen reader's virtual cursor out of the content behind the dialog.
    const appRoot = document.getElementById("root");
    const wasInert = appRoot?.inert;
    if (appRoot) appRoot.inert = true;

    const target = panelRef.current?.querySelector(FOCUSABLE) ?? panelRef.current;
    target?.focus();

    return () => {
      document.body.style.overflow = overflow;
      if (appRoot) appRoot.inert = wasInert ?? false;
      if (previouslyFocused.current instanceof HTMLElement) previouslyFocused.current.focus();
    };
  }, [open]);

  if (!open) return null;

  const width = size === "lg" ? "max-w-3xl" : "max-w-xl";

  // Rendered outside #root so that marking #root inert does not disable the
  // dialog along with the page behind it.
  return createPortal(
    <div
      className="fixed inset-0 z-50 grid place-items-center overflow-y-auto bg-ink/80 p-4 md:p-8"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        className={`flex w-full ${width} max-h-full flex-col border-4 border-ink bg-paper focus:outline-none`}
        role="dialog"
        aria-modal="true"
        aria-labelledby={title ? titleId : undefined}
        aria-describedby={description ? descriptionId : undefined}
        ref={panelRef}
        tabIndex={-1}
        onKeyDown={handleKeyDown}
      >
        <header className="flex items-start justify-between gap-6 border-b-4 border-ink px-6 py-5 md:px-8">
          <div className="flex flex-col gap-2">
            {title ? (
              <h2 className="font-sans text-xl font-black uppercase tracking-tighter text-ink md:text-2xl" id={titleId}>
                {title}
              </h2>
            ) : null}
            {description ? (
              <p className="font-sans text-sm leading-relaxed text-ink/60" id={descriptionId}>
                {description}
              </p>
            ) : null}
          </div>
          <IconButton icon="close" label="Close dialog" variant="secondary" onClick={onClose} />
        </header>
        <div className="min-h-0 overflow-y-auto px-6 py-6 md:px-8">{children}</div>
        {footer ? (
          <footer className="swiss-dots flex flex-wrap justify-end gap-3 border-t-4 border-ink bg-sand px-6 py-4 md:px-8">
            {footer}
          </footer>
        ) : null}
      </div>
    </div>,
    document.body,
  );
}
