import { useEffect, useRef, useState } from "react";
import { Icon, Logomark } from "./ui/Icon.jsx";
import { API_BASE } from "../lib/api.js";
import { useAuth } from "../context/AuthContext.jsx";
import { Link, useRouter } from "../lib/router.jsx";
import { ADMIN_TABS, TABS } from "../lib/tabs.js";
import { getSmoothScroll } from "../lib/smoothScroll.js";

const HEALTH_META = {
  checking: { label: "Checking database", tone: "bg-clay" },
  online: { label: "Database connected", tone: "bg-sage" },
  offline: { label: "Database unreachable", tone: "bg-terracotta" },
};

function HealthIndicator({ status, ingredientCount, className = "" }) {
  const meta = HEALTH_META[status] ?? HEALTH_META.checking;
  const detail =
    status === "online" && typeof ingredientCount === "number"
      ? `${ingredientCount.toLocaleString()} ingredients indexed`
      : meta.label;

  return (
    <p
      className={`inline-flex items-center gap-2.5 rounded-full border border-stone bg-linen px-4 py-2
                  font-sans text-2xs text-subtle ${className}`.trim()}
      title={meta.label}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${meta.tone}`} aria-hidden="true" />
      {detail}
      <span className="sr-only">{meta.label}</span>
    </p>
  );
}

const TAB_BASE =
  "rounded-full px-4 py-2 font-sans text-xs uppercase tracking-label transition-colors duration-300 " +
  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sage focus-visible:ring-offset-2 " +
  "focus-visible:ring-offset-alabaster";

export function SiteHeader({ healthStatus, ingredientCount, activeTab, onSelectTab }) {
  const { isAdmin } = useAuth();
  const tabs = isAdmin ? [...TABS, ...ADMIN_TABS] : TABS;
  const [menuOpen, setMenuOpen] = useState(false);
  const panelRef = useRef(null);
  const triggerRef = useRef(null);

  /* The overlay covers the page, so the page behind it must not scroll. Lenis
     drives scrolling here, and setting `overflow: hidden` alone does not stop
     it — its RAF loop keeps applying transforms — so the instance is paused
     explicitly and resumed on close.
     
     Focus moves to the panel via a callback ref rather than from this effect:
     the ref fires exactly when the node attaches, so it does not depend on a
     frame having been painted first. Returning focus to the trigger is
     deliberately NOT done in this cleanup: cleanup runs on every re-run of the
     effect, and React's StrictMode double-invokes effects in development, so
     doing it here yanked focus straight back out of the panel. Restoring focus
     belongs to the close paths, which is where the intent actually is. */
  useEffect(() => {
    if (!menuOpen) return undefined;
    const lenis = getSmoothScroll();
    lenis?.stop();
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    const onKeyDown = (event) => {
      if (event.key === "Escape") closeMenu();
    };
    document.addEventListener("keydown", onKeyDown);

    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previous;
      lenis?.start();
    };
  }, [menuOpen]);

  const closeMenu = () => {
    setMenuOpen(false);
    // The keyboard user's place is the control that opened the overlay.
    triggerRef.current?.focus();
  };

  const select = (key) => {
    onSelectTab(key);
    closeMenu();
  };

  return (
    <header
      className="sticky top-0 z-30 w-full border-b border-stone bg-alabaster/85 shadow-soft
                 backdrop-blur-md backdrop-saturate-150"
    >
      <div className="mx-auto flex h-20 w-full max-w-7xl items-center gap-6 px-6 md:px-10">
        <a
          className="group flex shrink-0 items-center gap-3 no-underline focus-visible:outline-none
                     focus-visible:ring-2 focus-visible:ring-sage focus-visible:ring-offset-4
                     focus-visible:ring-offset-alabaster"
          href="#top"
        >
          <span className="text-forest transition-colors duration-300 group-hover:text-terracotta">
            <Logomark size={40} />
          </span>
          <span className="hidden font-display text-xl font-semibold tracking-tight text-forest sm:block">
            SkincareSync
          </span>
        </a>

        {/* Sections, not documents: `aria-current="page"` marks the open one.
            A tablist would promise arrow-key roving these do not implement. */}
        <nav className="hidden md:block" aria-label="Sections">
          <ul className="flex items-center gap-1">
            {tabs.map((tab) => (
              <li key={tab.key}>
                <button
                  type="button"
                  className={`${TAB_BASE} ${
                    tab.key === activeTab
                      ? "bg-forest text-alabaster"
                      : "text-subtle hover:bg-sage-100 hover:text-forest"
                  }`}
                  aria-current={tab.key === activeTab ? "page" : undefined}
                  onClick={() => onSelectTab(tab.key)}
                >
                  {tab.label}
                </button>
              </li>
            ))}
          </ul>
        </nav>

        <div className="ml-auto flex items-center gap-3">
          <HealthIndicator
            status={healthStatus}
            ingredientCount={ingredientCount}
            className="hidden lg:inline-flex"
          />
          <div className="hidden md:block">
            <AccountControl />
          </div>
          {/* The interactive API docs are a development affordance. The server
              serves them only outside production, so linking to them from a
              production build would be a dead link advertising an endpoint. */}
          {import.meta.env.DEV ? (
            <a
              className="hidden items-center gap-1.5 font-sans text-2xs uppercase tracking-label
                         text-muted transition-colors duration-300 hover:text-terracotta lg:inline-flex"
              href={`${API_BASE}/docs`}
              target="_blank"
              rel="noreferrer noopener"
            >
              API
              <Icon name="external" size={12} strokeWidth={1.5} />
            </a>
          ) : null}

          <button
            type="button"
            ref={triggerRef}
            className="grid h-11 w-11 place-items-center rounded-full border border-stone bg-white
                       text-forest transition-colors duration-300 hover:border-sage hover:bg-sage-100
                       focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sage
                       focus-visible:ring-offset-2 focus-visible:ring-offset-alabaster md:hidden"
            aria-expanded={menuOpen}
            aria-controls="mobile-menu"
            aria-label={menuOpen ? "Close menu" : "Open menu"}
            onClick={() => setMenuOpen((open) => !open)}
          >
            <Icon name={menuOpen ? "close" : "menu"} size={18} strokeWidth={1.5} />
          </button>
        </div>
      </div>

      {/* Full-screen overlay, sliding down from under the bar. Kept mounted-on-
          demand rather than hidden with CSS so its links leave the tab order
          entirely when closed. */}
      {menuOpen ? (
        <div
          className="fixed inset-x-0 bottom-0 top-20 z-40 md:hidden"
          id="mobile-menu"
          ref={panelRef}
        >
          <div
            className="absolute inset-0 bg-forest/20 backdrop-blur-sm"
            aria-hidden="true"
            onClick={closeMenu}
          />
          {/* The panel takes focus itself rather than its first link: landing on
              "Home" would imply that item is chosen, and a container is the
              standard place to put focus when a dialog-like surface opens. */}
          <nav
            className="relative flex h-full flex-col gap-2 overflow-y-auto border-t border-stone
                       bg-alabaster px-6 py-8 focus:outline-none"
            aria-label="Sections"
            tabIndex={-1}
            ref={(node) => node?.focus()}
          >
            {tabs.map((tab) => (
              <button
                key={tab.key}
                type="button"
                className={`w-full rounded-card px-5 py-4 text-left font-display text-feature
                            font-semibold tracking-tight transition-colors duration-300
                            focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sage ${
                              tab.key === activeTab
                                ? "bg-forest text-alabaster"
                                : "text-forest hover:bg-sage-100"
                            }`}
                aria-current={tab.key === activeTab ? "page" : undefined}
                onClick={() => select(tab.key)}
              >
                {tab.label}
              </button>
            ))}

            <div className="mt-auto flex flex-col gap-5 border-t border-stone pt-6">
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
 * Sign-in link, or an account menu when signed in.
 *
 * The menu only hides controls; every route behind it is enforced on the server.
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
    "inline-flex h-10 items-center gap-2 rounded-full border border-stone bg-white px-4 " +
    "font-sans text-2xs uppercase tracking-label text-subtle transition-colors duration-300 " +
    "hover:border-sage hover:bg-sage-100 hover:text-forest focus-visible:outline-none " +
    "focus-visible:ring-2 focus-visible:ring-sage focus-visible:ring-offset-2 focus-visible:ring-offset-alabaster";

  // Render nothing rather than a sign-in link while the session is resolving,
  // so a signed-in user never sees "Sign in" flash on load.
  if (isLoading) return null;

  if (!isAuthenticated) {
    return (
      <Link to="/signin" className={TRIGGER} onClick={onNavigate}>
        Sign in
      </Link>
    );
  }

  return (
    <div className="relative" ref={menuRef}>
      <button
        type="button"
        className={TRIGGER}
        onClick={() => setOpen((current) => !current)}
        aria-expanded={open}
        aria-haspopup="menu"
      >
        <Icon name="user" size={15} strokeWidth={1.5} />
        <span className="max-w-[16ch] truncate normal-case tracking-normal">
          {user.display_name || user.email}
        </span>
        <Icon name="chevronDown" size={13} strokeWidth={1.5} />
      </button>

      {open ? (
        <div
          className="absolute right-0 top-[calc(100%+0.5rem)] z-50 flex min-w-56 flex-col
                     overflow-hidden rounded-card border border-stone bg-white shadow-bloom"
          role="menu"
        >
          <Link
            to="/account/security"
            className="px-5 py-3.5 text-left font-sans text-sm text-subtle transition-colors
                       duration-300 hover:bg-sage-100 hover:text-forest"
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
            className="border-t border-stone px-5 py-3.5 text-left font-sans text-sm text-subtle
                       transition-colors duration-300 hover:bg-sage-100 hover:text-forest"
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
