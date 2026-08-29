import { Icon, Logomark } from "./ui/Icon.jsx";
import { API_BASE } from "../lib/api.js";

const NAV_LINKS = [
  { href: "#workspace", label: "Analyzer" },
  { href: "#catalog", label: "Ingredient catalog" },
  { href: "#how-it-works", label: "How it works" },
  { href: "#backlog", label: "Research backlog" },
];

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

export function SiteHeader({ healthStatus, ingredientCount }) {
  return (
    <header className="siteHeader">
      <div className="siteHeader__inner">
        <a className="brand" href="#top">
          <span className="brand__mark">
            <Logomark size={26} />
          </span>
          <span className="brand__text">
            SkincareSync
            <span className="brand__tag">Beta</span>
          </span>
        </a>

        <nav className="siteNav" aria-label="Sections">
          <ul>
            {NAV_LINKS.map((link) => (
              <li key={link.href}>
                <a href={link.href}>{link.label}</a>
              </li>
            ))}
          </ul>
        </nav>

        <div className="siteHeader__meta">
          <HealthIndicator status={healthStatus} ingredientCount={ingredientCount} />
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
