import { useEffect, useRef, useState } from "react";
import { Icon, Logomark } from "./ui/Icon.jsx";
import { API_BASE } from "../lib/api.js";
import { useAuth } from "../context/AuthContext.jsx";
import { Link, useRouter } from "../lib/router.jsx";
import { ADMIN_TABS, TABS } from "../lib/tabs.js";

const HEALTH_META = {
  checking: { label: "Checking database", tone: "checking" },
  online: { label: "Database connected", tone: "online" },
  offline: { label: "Database unreachable", tone: "offline" },
};

function HealthIndicator({ status, ingredientCount }) {
  const meta = HEALTH_META[status] ?? HEALTH_META.checking;
  const detail =
    status === "online" && typeof ingredientCount === "number"
      ? `${ingredientCount.toLocaleString()} ingredients indexed`
      : meta.label;

  return (
    <p className={`health health--${meta.tone}`} title={meta.label}>
      <span className="health__dot" aria-hidden="true" />
      <span className="health__label">{detail}</span>
      <span className="visuallyHidden">{meta.label}</span>
    </p>
  );
}

export function SiteHeader({ healthStatus, ingredientCount, activeTab, onSelectTab }) {
  const { isAdmin } = useAuth();
  const tabs = isAdmin ? [...TABS, ...ADMIN_TABS] : TABS;

  return (
    <header className="siteHeader">
      <div className="siteHeader__inner">
        <a className="brand" href="#top">
          <span className="brand__mark">
            <Logomark size={30} />
          </span>
          <span className="brand__text">SkincareSync</span>
        </a>

        {/* Sections, not documents: `aria-current="page"` marks the open one.
            A tablist would promise arrow-key roving these do not implement. */}
        <nav className="siteNav" aria-label="Sections">
          <ul>
            {tabs.map((tab) => (
              <li key={tab.key}>
                <button
                  type="button"
                  className={`siteNav__tab${tab.key === activeTab ? " is-active" : ""}`}
                  aria-current={tab.key === activeTab ? "page" : undefined}
                  onClick={() => onSelectTab(tab.key)}
                >
                  {tab.label}
                </button>
              </li>
            ))}
          </ul>
        </nav>

        <div className="siteHeader__meta">
          <HealthIndicator status={healthStatus} ingredientCount={ingredientCount} />
          <AccountControl />
          {/* The interactive API docs are a development affordance. The server
              serves them only outside production, so linking to them from a
              production build would be a dead link advertising an endpoint. */}
          {import.meta.env.DEV ? (
            <a
              className="siteHeader__docs"
              href={`${API_BASE}/docs`}
              target="_blank"
              rel="noreferrer noopener"
            >
              API
              <Icon name="external" size={12} />
            </a>
          ) : null}
        </div>
      </div>
    </header>
  );
}


/**
 * Sign-in link, or an account menu when signed in.
 *
 * The menu only hides controls; every route behind it is enforced on the server.
 */
function AccountControl() {
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

  // Render nothing rather than a sign-in link while the session is resolving,
  // so a signed-in user never sees "Sign in" flash on load.
  if (isLoading) return null;

  if (!isAuthenticated) {
    return (
      <Link to="/signin" className="btn btn--quiet btn--sm">
        Sign in
      </Link>
    );
  }

  return (
    <div className="accountMenu" ref={menuRef}>
      <button
        type="button"
        className="btn btn--quiet btn--sm accountMenu__trigger"
        onClick={() => setOpen((current) => !current)}
        aria-expanded={open}
        aria-haspopup="menu"
      >
        <Icon name="user" size={15} />
        <span className="accountMenu__email">{user.display_name || user.email}</span>
        <Icon name="chevronDown" size={13} />
      </button>

      {open ? (
        <div className="accountMenu__panel" role="menu">
          <Link
            to="/account/security"
            className="accountMenu__item"
            role="menuitem"
            onClick={() => setOpen(false)}
          >
            Account &amp; security
          </Link>
          <button
            type="button"
            className="accountMenu__item"
            role="menuitem"
            onClick={async () => {
              setOpen(false);
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
