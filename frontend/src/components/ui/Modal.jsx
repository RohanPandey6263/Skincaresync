import { useCallback, useEffect, useId, useRef } from "react";
import { createPortal } from "react-dom";
import { IconButton } from "./Button.jsx";

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function Modal({ open, onClose, title, description, children, footer, labelledBy }) {
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

    // The Tab trap below only constrains keyboard focus. Without also marking
    // the page behind the dialog inert, a screen reader's virtual cursor could
    // read and activate everything under the overlay, so `aria-modal` was a
    // promise the markup did not keep.
    const appRoot = document.getElementById("root");
    const wasInert = appRoot?.inert;
    if (appRoot) appRoot.inert = true;

    const target = panelRef.current?.querySelector(FOCUSABLE) ?? panelRef.current;
    target?.focus();

    return () => {
      document.body.style.overflow = overflow;
      if (appRoot) appRoot.inert = wasInert ?? false;
      if (previouslyFocused.current instanceof HTMLElement) {
        previouslyFocused.current.focus();
      }
    };
  }, [open]);

  if (!open) return null;

  // Rendered outside #root so that marking #root inert does not disable the
  // dialog along with the page behind it.
  return createPortal(
    <div
      className="overlay"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        className="dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby={title ? titleId : undefined}
        aria-describedby={description ? descriptionId : undefined}
        ref={panelRef}
        tabIndex={-1}
        onKeyDown={handleKeyDown}
      >
        <header className="dialog__header">
          <div>
            {title ? (
              <h2 className="dialog__title" id={titleId}>
                {title}
              </h2>
            ) : null}
            {description ? (
              <p className="dialog__description" id={descriptionId}>
                {description}
              </p>
            ) : null}
          </div>
          <IconButton icon="close" label="Close dialog" onClick={onClose} />
        </header>
        <div className="dialog__body">{children}</div>
        {footer ? <footer className="dialog__footer">{footer}</footer> : null}
      </div>
    </div>,
    document.body,
  );
}
