import { createContext, useCallback, useContext, useMemo, useRef, useState } from "react";
import { Icon } from "./Icon.jsx";
import { IconButton } from "./Button.jsx";

const ToastContext = createContext(null);
const DEFAULT_DURATION = 5000;

const TONE_ICON = { ok: "checkCircle", danger: "alertOctagon", warn: "alertTriangle", info: "info" };

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
      setToasts((current) => [...current.slice(-2), { id, tone, title, description }]);
      if (duration) {
        timers.current.set(
          id,
          setTimeout(() => dismiss(id), duration),
        );
      }
      return id;
    },
    [dismiss],
  );

  const value = useMemo(() => ({ notify, dismiss }), [notify, dismiss]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div className="toaster" role="region" aria-label="Notifications">
        {toasts.map((toast) => (
          <div
            key={toast.id}
            className={`toast toast--${toast.tone}`}
            role={toast.tone === "danger" ? "alert" : "status"}
          >
            <Icon name={TONE_ICON[toast.tone]} size={16} className="toast__icon" />
            <div className="toast__content">
              <p className="toast__title">{toast.title}</p>
              {toast.description ? <p className="toast__description">{toast.description}</p> : null}
            </div>
            <IconButton
              icon="close"
              label="Dismiss notification"
              size="sm"
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
