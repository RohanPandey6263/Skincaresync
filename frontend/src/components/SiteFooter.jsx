import { Icon, Logomark } from "./ui/Icon.jsx";
import { Link } from "../lib/router.jsx";
import { TABS } from "../lib/tabs.js";

/**
 * Sections link by hash rather than through a callback: `App` already treats the
 * hash as the source of truth for the open tab, so a plain anchor here is a real
 * link — middle-clickable, copyable — and needs no prop drilled down.
 */
function SectionLinks() {
  return (
    <nav className="siteFooter__col" aria-labelledby="footer-sections">
      <h2 className="siteFooter__colTitle" id="footer-sections">
        Sections
      </h2>
      <ul>
        {TABS.map((tab) => (
          <li key={tab.key}>
            <a href={tab.hash}>{tab.label}</a>
          </li>
        ))}
      </ul>
    </nav>
  );
}

function AccountLinks() {
  return (
    <nav className="siteFooter__col" aria-labelledby="footer-account">
      <h2 className="siteFooter__colTitle" id="footer-account">
        Account
      </h2>
      <ul>
        <li>
          <Link to="/signin">Sign in</Link>
        </li>
        <li>
          <Link to="/register">Create an account</Link>
        </li>
        <li>
          <Link to="/account/security">Account &amp; security</Link>
        </li>
      </ul>
    </nav>
  );
}

// Every source the catalog and the rules engine actually draw on. Attribution is
// an ODbL obligation, not decoration -- see ATTRIBUTION.md.
const SOURCES = [
  { href: "https://world.openbeautyfacts.org/", label: "Open Beauty Facts" },
  {
    href: "https://ec.europa.eu/growth/tools-databases/cosing/",
    label: "EU CosIng",
  },
  { href: "https://dailymed.nlm.nih.gov/", label: "FDA DailyMed" },
  { href: "https://pubmed.ncbi.nlm.nih.gov/", label: "PubMed" },
];

function SourceLinks() {
  return (
    <nav className="siteFooter__col" aria-labelledby="footer-sources">
      <h2 className="siteFooter__colTitle" id="footer-sources">
        Data sources
      </h2>
      <ul>
        {SOURCES.map((source) => (
          <li key={source.href}>
            <a href={source.href} target="_blank" rel="noreferrer noopener">
              {source.label}
              <Icon name="external" size={12} />
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
}

export function SiteFooter() {
  return (
    <footer className="siteFooter">
      <div className="siteFooter__inner">
        <div className="siteFooter__top">
          <div className="siteFooter__brand">
            <span className="siteFooter__mark">
              <Logomark size={30} />
            </span>
            <p className="siteFooter__wordmark">SkincareSync</p>
            <p className="siteFooter__blurb">
              Deterministic routine compatibility analysis. Every conflict, caution and synergy
              traces back to a parsed ingredient list and a cited rule.
            </p>
            <p className="siteFooter__attribution">
              Ingredient data from EU CosIng via Open Beauty Facts, under ODbL.
            </p>
          </div>

          <div className="siteFooter__cols">
            <SectionLinks />
            <AccountLinks />
            <SourceLinks />
          </div>
        </div>

        <div className="siteFooter__bottom">
          <p className="siteFooter__disclaimer">
            © {new Date().getFullYear()} SkincareSync. Results are informational only and are not
            medical advice — consult a dermatologist about your own skin.
          </p>
          {/* TODO: these two need real routes in Routes.jsx before launch; they
              are inert placeholders rather than links that would 404. */}
          <ul className="siteFooter__legal">
            <li>
              <span>Privacy Policy</span>
            </li>
            <li>
              <span>Terms of Use</span>
            </li>
          </ul>
        </div>
      </div>
    </footer>
  );
}
