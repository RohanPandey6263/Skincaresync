import { Icon, Logomark } from "./ui/Icon.jsx";
import { Link } from "../lib/router.jsx";
import { TABS } from "../lib/tabs.js";

const COL_TITLE = "font-sans text-2xs uppercase tracking-label text-muted";
const COL_LINK =
  "group inline-flex items-center gap-1.5 font-sans text-sm text-subtle transition-colors " +
  "duration-300 hover:text-terracotta focus-visible:outline-none focus-visible:ring-2 " +
  "focus-visible:ring-sage focus-visible:ring-offset-4 focus-visible:ring-offset-linen";

function Column({ id, title, children }) {
  return (
    <nav className="flex flex-col gap-4" aria-labelledby={id}>
      <h2 className={COL_TITLE} id={id}>
        {title}
      </h2>
      <ul className="flex flex-col gap-3">{children}</ul>
    </nav>
  );
}

/**
 * Sections link by hash rather than through a callback: `App` already treats the
 * hash as the source of truth for the open tab, so a plain anchor here is a real
 * link — middle-clickable, copyable — and needs no prop drilled down.
 */
function SectionLinks() {
  return (
    <Column id="footer-sections" title="Sections">
      {TABS.map((tab) => (
        <li key={tab.key}>
          <a className={COL_LINK} href={tab.hash}>
            {tab.label}
          </a>
        </li>
      ))}
    </Column>
  );
}

function AccountLinks() {
  return (
    <Column id="footer-account" title="Account">
      <li>
        <Link to="/signin" className={COL_LINK}>
          Sign in
        </Link>
      </li>
      <li>
        <Link to="/register" className={COL_LINK}>
          Create an account
        </Link>
      </li>
      <li>
        <Link to="/account/security" className={COL_LINK}>
          Account &amp; security
        </Link>
      </li>
    </Column>
  );
}

// Every source the catalog and the rules engine actually draw on. Attribution is
// an ODbL obligation, not decoration -- see ATTRIBUTION.md.
const SOURCES = [
  { href: "https://world.openbeautyfacts.org/", label: "Open Beauty Facts" },
  { href: "https://ec.europa.eu/growth/tools-databases/cosing/", label: "EU CosIng" },
  { href: "https://dailymed.nlm.nih.gov/", label: "FDA DailyMed" },
  { href: "https://pubmed.ncbi.nlm.nih.gov/", label: "PubMed" },
];

function SourceLinks() {
  return (
    <Column id="footer-sources" title="Data sources">
      {SOURCES.map((source) => (
        <li key={source.href}>
          <a className={COL_LINK} href={source.href} target="_blank" rel="noreferrer noopener">
            {source.label}
            <Icon
              name="external"
              size={12}
              strokeWidth={1.5}
              className="text-sage transition-transform duration-300 group-hover:-translate-y-px group-hover:translate-x-px"
            />
          </a>
        </li>
      ))}
    </Column>
  );
}

export function SiteFooter() {
  return (
    <footer className="mt-16 border-t border-stone bg-linen md:mt-32">
      <div className="mx-auto w-full max-w-7xl px-6 py-16 md:px-10 md:py-24">
        <div className="grid grid-cols-1 gap-12 md:grid-cols-[1.4fr_repeat(3,1fr)] md:gap-16">
          <div className="flex max-w-[42ch] flex-col gap-5">
            <span className="text-forest">
              <Logomark size={44} />
            </span>
            <p className="font-display text-2xl font-semibold tracking-tight text-forest">
              SkincareSync
            </p>
            <p className="font-sans text-md leading-relaxed text-subtle">
              Deterministic routine compatibility analysis. Every conflict, caution and synergy
              traces back to a parsed ingredient list and a cited rule.
            </p>
            <p className="font-sans text-sm leading-relaxed text-muted">
              Ingredient data from EU CosIng via Open Beauty Facts, under ODbL.
            </p>
          </div>

          <SectionLinks />
          <AccountLinks />
          <SourceLinks />
        </div>

        <div className="mt-16 flex flex-col gap-4 border-t border-stone pt-8 md:flex-row md:items-center md:justify-between">
          <p className="max-w-[68ch] font-sans text-sm leading-relaxed text-muted">
            © {new Date().getFullYear()} SkincareSync. Results are informational only and are not
            medical advice — consult a dermatologist about your own skin.
          </p>
          {/* TODO: these two need real routes in Routes.jsx before launch; they
              are inert placeholders rather than links that would 404. */}
          <ul className="flex items-center gap-6">
            <li className="font-sans text-sm text-muted">Privacy Policy</li>
            <li className="font-sans text-sm text-muted">Terms of Use</li>
          </ul>
        </div>
      </div>
    </footer>
  );
}
