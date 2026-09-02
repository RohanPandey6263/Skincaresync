import { useEffect, useRef, useState } from "react";
import { Icon, Logomark } from "./ui/Icon.jsx";
import { API_BASE } from "../lib/api.js";
import { useAuth } from "../context/AuthContext.jsx";
import { Link, useRouter } from "../lib/router.jsx";
import { ADMIN_TABS, TABS } from "../lib/tabs.js";

const HEALTH_META = {
  checking: { label: "Checking database", dot: "border-2 border-cocoa bg-paper" },
  online: { label: "Database connected", dot: "bg-cocoa" },
  offline: { label: "Database unreachable", dot: "bg-coral" },
};

function HealthIndicator({ status, ingredientCount, className = "" }) {
  const meta = HEALTH_META[status] ?? HEALTH_META.checking;
  const detail =
    status === "online" && typeof ingredientCount === "number"
      ? `${ingredientCount.toLocaleString()} ingredients`
      : meta.label;

  return (
    <p
      className={`inline-flex h-10 items-center gap-3 border-2 border-cocoa px-3 font-sans text-2xs label-caps text-ink ${className}`.trim()}
      title={meta.label}
    >
      <span className={`h-2.5 w-2.5 ${meta.dot}`} aria-hidden="true" />
      {detail}
      <span className="sr-only">{meta.label}</span>
    </p>
  );
}

/**
 * A navigation link whose label slides up and is replaced from below by its
 * red twin. The active tab is a solid black block and does not move.
 */
function NavTab({ active, onClick, children }) {
  return (
    <button
      type="button"
      className={`group relative h-11 overflow-hidden px-4 font-sans text-xs label-caps transition-colors duration-150 ease-linear
                  focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral-deep focus-visible:ring-offset-2 ${
                    active ? "bg-cocoa text-paper" : "text-ink"
                  }`}
      aria-current={active ? "page" : undefined}
      onClick={onClick}
    >
      <span className={`flex h-full items-center justify-center transition-transform duration-150 ease-linear ${active ? "" : "group-hover:-translate-y-full"}`}>
        {children}
      </span>
      {!active ? (
        <span
          className="absolute inset-0 flex translate-y-full items-center justify-center text-coral-deep transition-transform duration-150 ease-linear group-hover:translate-y-0"
          aria-hidden="true"
        >
          {children}
        </span>
      ) : null}
    </button>
  );
}

export function SiteHeader({ healthStatus, ingredientCount, activeTab, onSelectTab }) {
  const { isAdmin } = useAuth();
  const tabs = isAdmin ? [...TABS, ...ADMIN_TABS] : TABS;
  const [menuOpen, setMenuOpen] = useState(false);
  const triggerRef = useRef(null);

  /* The overlay covers the page, so the page behind it must not scroll.
     Focus moves to the panel via a callback ref; returning focus to the
     trigger belongs to the close paths, not to this cleanup, which React's
     StrictMode double-invokes in development. */
  useEffect(() => {
    if (!menuOpen) return undefined;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const onKeyDown = (event) => {
      if (event.key === "Escape") closeMenu();
    };
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previous;
    };
  }, [menuOpen]);

  const closeMenu = () => {
    setMenuOpen(false);
    triggerRef.current?.focus();
  };

  const select = (key) => {
    onSelectTab(key);
    closeMenu();
  };

  return (
    <header className="sticky top-0 z-30 w-full border-b-4 border-cocoa bg-paper">
      <div className="mx-auto flex h-20 w-full max-w-7xl items-stretch gap-6 px-6 md:px-10">
        <a
          className="group flex shrink-0 items-center gap-3 self-center no-underline focus-visible:outline-none
                     focus-visible:ring-2 focus-visible:ring-coral-deep focus-visible:ring-offset-4"
          href="#top"
        >
          <span className="text-ink transition-colors duration-150 group-hover:text-coral-deep">
            <Logomark size={36} />
          </span>
          <span className="hidden font-sans text-lg font-black uppercase tracking-tighter text-ink sm:block">
            SkincareSync
          </span>
        </a>

        {/* Sections, not documents: `aria-current="page"` marks the open one. */}
        <nav className="hidden items-center md:flex" aria-label="Sections">
          <ul className="flex items-center gap-1">
            {tabs.map((tab) => (
              <li key={tab.key}>
                <NavTab active={tab.key === activeTab} onClick={() => onSelectTab(tab.key)}>
                  {tab.label}
                </NavTab>
              </li>
            ))}
          </ul>
        </nav>

        <div className="ml-auto flex items-center gap-3">
          <HealthIndicator status={healthStatus} ingredientCount={ingredientCount} className="hidden lg:inline-flex" />
          <div className="hidden md:block">
            <AccountControl />
          </div>
          {/* The interactive API docs exist only outside production. */}
          {import.meta.env.DEV ? (
            <a
              className="hidden h-10 items-center gap-1.5 px-2 font-sans text-2xs label-caps text-ink transition-colors duration-150 hover:text-coral-deep lg:inline-flex"
              href={`${API_BASE}/docs`}
              target="_blank"
              rel="noreferrer noopener"
            >
              API
              <Icon name="arrowUpRight" size={12} strokeWidth={2.5} />
            </a>
          ) : null}

          <button
            type="button"
            ref={triggerRef}
            className="grid h-11 w-11 place-items-center border-2 border-cocoa bg-paper text-ink transition-colors
                       duration-150 hover:bg-cocoa hover:text-paper focus-visible:outline-none focus-visible:ring-2
                       focus-visible:ring-coral-deep focus-visible:ring-offset-2 md:hidden"
            aria-expanded={menuOpen}
            aria-controls="mobile-menu"
            aria-label={menuOpen ? "Close menu" : "Open menu"}
            onClick={() => setMenuOpen((open) => !open)}
          >
            <Icon name={menuOpen ? "close" : "menu"} size={20} strokeWidth={2.5} />
          </button>
        </div>
      </div>

      {menuOpen ? (
        <div className="fixed inset-x-0 bottom-0 top-20 z-40 md:hidden" id="mobile-menu">
          <nav
            className="swiss-grid-pattern flex h-full flex-col overflow-y-auto bg-paper focus:outline-none"
            aria-label="Sections"
            tabIndex={-1}
            ref={(node) => node?.focus()}
          >
            {tabs.map((tab, index) => (
              <button
                key={tab.key}
                type="button"
                className={`flex items-baseline gap-4 border-b-2 border-cocoa px-6 py-6 text-left font-sans text-4xl font-black uppercase
                            tracking-tighter transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2
                            focus-visible:ring-inset focus-visible:ring-coral-deep ${
                              tab.key === activeTab ? "bg-cocoa text-paper" : "text-ink hover:bg-cocoa hover:text-paper"
                            }`}
                aria-current={tab.key === activeTab ? "page" : undefined}
                onClick={() => select(tab.key)}
              >
                <span className="font-sans text-xs label-caps text-coral-deep" aria-hidden="true">
                  {String(index + 1).padStart(2, "0")}
                </span>
                {tab.label}
              </button>
            ))}

            <div className="mt-auto flex flex-col gap-4 border-t-4 border-cocoa bg-paper px-6 py-6">
              <Link
                to="/ios"
                className="inline-flex h-11 items-center justify-between gap-2 border-2 border-cocoa px-3 font-sans text-2xs label-caps text-ink transition-colors duration-150 hover:bg-cocoa hover:text-paper focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral-deep focus-visible:ring-offset-2"
                onClick={closeMenu}
              >
                Get the iPhone app
                <Icon name="arrowRight" size={14} strokeWidth={2.5} />
              </Link>
              <HealthIndicator status={healthStatus} ingredientCount={ingredientCount} />
              <AccountControl onNavigate={closeMenu} />
            </div>
          </nav>
        </div>
      ) : null}
    </header>
  );
}

/**
 * Sign-in link, or an account menu when signed in. The menu only hides
 * controls; every route behind it is enforced on the server.
 */
function AccountControl({ onNavigate }) {
  const { isAuthenticated, isLoading, user, signOut } = useAuth();
  const { navigate } = useRouter();
  const [open, setOpen] = useState(false);
  const menuRef = useRef(null);

  useEffect(() => {
    if (!open) return undefined;
    const onPointerDown = (event) => {
      if (!menuRef.current?.contains(event.target)) setOpen(false);
    };
    const onKeyDown = (event) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  const TRIGGER =
    "inline-flex h-10 items-center gap-2 border-2 border-cocoa bg-paper px-3 font-sans text-2xs label-caps " +
    "text-ink transition-colors duration-150 ease-linear hover:bg-cocoa hover:text-paper " +
    "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral-deep focus-visible:ring-offset-2";

  // Render nothing while the session resolves, so a signed-in user never sees
  // "Sign in" flash on load.
  if (isLoading) return null;

  if (!isAuthenticated) {
    return (
      <Link to="/signin" className={TRIGGER} onClick={onNavigate}>
        Sign in
      </Link>
    );
  }

  const ITEM =
    "block w-full px-4 py-3 text-left font-sans text-xs label-caps text-ink transition-colors duration-150 " +
    "hover:bg-cocoa hover:text-paper focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-coral-deep";

  return (
    <div className="relative" ref={menuRef}>
      <button type="button" className={TRIGGER} onClick={() => setOpen((current) => !current)} aria-expanded={open} aria-haspopup="menu">
        <Icon name="user" size={14} strokeWidth={2.5} />
        <span className="max-w-[16ch] truncate normal-case tracking-normal">{user.display_name || user.email}</span>
        <Icon
          name="chevronDown"
          size={13}
          strokeWidth={2.5}
          className={`transition-transform duration-150 ${open ? "rotate-180" : ""}`}
        />
      </button>

      {open ? (
        <div className="absolute right-0 top-[calc(100%+0.5rem)] z-50 flex min-w-56 flex-col border-4 border-cocoa bg-paper" role="menu">
          <Link
            to="/account/security"
            className={ITEM}
            role="menuitem"
            onClick={() => {
              setOpen(false);
              onNavigate?.();
            }}
          >
            Account &amp; security
          </Link>
          <button
            type="button"
            className={`${ITEM} border-t-2 border-cocoa`}
            role="menuitem"
            onClick={async () => {
              setOpen(false);
              onNavigate?.();
              await signOut();
              navigate("/", { replace: true });
            }}
          >
            Sign out
          </button>
        </div>
      ) : null}
    </div>
  );
}
