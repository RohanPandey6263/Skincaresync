import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { Icon } from "./Icon.jsx";
import { IconButton } from "./Button.jsx";

const ToastContext = createContext(null);
const DEFAULT_DURATION = 5000;

const TONE_ICON = { ok: "checkCircle", danger: "alertOctagon", warn: "alertTriangle", info: "info" };

const TONE_EDGE = { ok: "bg-ink", danger: "bg-coral", warn: "bg-ink", info: "bg-ink" };
const TONE_SURFACE = {
  ok: "bg-mint text-ink",
  danger: "bg-paper text-ink",
  warn: "swiss-diagonal bg-paper text-ink",
  info: "bg-sand text-ink",
};

export function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([]);
  const timers = useRef(new Map());
  const nextId = useRef(0);

  const dismiss = useCallback((id) => {
    const timer = timers.current.get(id);
    if (timer) {
      clearTimeout(timer);
      timers.current.delete(id);
    }
    setToasts((current) => current.filter((toast) => toast.id !== id));
  }, []);

  const notify = useCallback(
    ({ tone = "info", title, description, duration = DEFAULT_DURATION }) => {
      const id = nextId.current++;
      setToasts((current) => {
        const next = [...current.slice(-2), { id, tone, title, description }];
        // Toasts pushed off the end by the cap still had a live timeout.
        const kept = new Set(next.map((toast) => toast.id));
        for (const [timerId, timer] of timers.current) {
          if (!kept.has(timerId)) {
            clearTimeout(timer);
            timers.current.delete(timerId);
          }
        }
        return next;
      });
      if (duration) timers.current.set(id, setTimeout(() => dismiss(id), duration));
      return id;
    },
    [dismiss],
  );

  useEffect(() => {
    const pending = timers.current;
    return () => {
      for (const timer of pending.values()) clearTimeout(timer);
      pending.clear();
    };
  }, []);

  const value = useMemo(() => ({ notify, dismiss }), [notify, dismiss]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div
        className="pointer-events-none fixed inset-x-4 bottom-4 z-[60] flex flex-col gap-3 md:inset-x-auto md:right-6 md:bottom-6 md:w-96"
        role="region"
        aria-label="Notifications"
      >
        {toasts.map((toast) => (
          <div
            key={toast.id}
            className={`pointer-events-auto relative flex items-start gap-4 border-2 border-ink py-3 pl-6 pr-3 ${
              TONE_SURFACE[toast.tone] ?? TONE_SURFACE.info
            }`}
            role={toast.tone === "danger" ? "alert" : "status"}
          >
            <span className={`absolute inset-y-0 left-0 w-2 ${TONE_EDGE[toast.tone] ?? "bg-ink"}`} aria-hidden="true" />
            <Icon name={TONE_ICON[toast.tone]} size={18} strokeWidth={2.25} className="mt-0.5 shrink-0" />
            <div className="flex min-w-0 grow flex-col gap-1">
              <p className="font-sans text-xs label-caps">{toast.title}</p>
              {toast.description ? <p className="font-sans text-sm leading-snug">{toast.description}</p> : null}
            </div>
            <IconButton
              icon="close"
              label="Dismiss notification"
              size="sm"
              variant="ghost"
              onClick={() => dismiss(toast.id)}
            />
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  const context = useContext(ToastContext);
  if (!context) throw new Error("useToast must be used inside a ToastProvider");
  return context;
}
