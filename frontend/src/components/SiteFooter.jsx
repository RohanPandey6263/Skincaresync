import { Icon, Logomark } from "./ui/Icon.jsx";
import { Link } from "../lib/router.jsx";
import { TABS } from "../lib/tabs.js";

const COL_TITLE = "font-sans text-2xs label-caps text-paper/60";
const COL_LINK =
  "group inline-flex items-center gap-2 font-sans text-sm font-medium text-paper transition-colors " +
  "duration-150 hover:text-coral-deep focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral-deep focus-visible:ring-offset-2 focus-visible:ring-offset-cocoa";

function Column({ id, title, children }) {
  return (
    <nav className="flex flex-col gap-5" aria-labelledby={id}>
      <h2 className={COL_TITLE} id={id}>
        {title}
      </h2>
      <ul className="flex flex-col gap-3">{children}</ul>
    </nav>
  );
}

/** Sections link by hash: `App` treats the hash as the source of truth for the open tab. */
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
export const SOURCES = [
  { href: "https://world.openbeautyfacts.org/", label: "Open Beauty Facts", role: "Product and ingredient records, ODbL" },
  { href: "https://ec.europa.eu/growth/tools-databases/cosing/", label: "EU CosIng", role: "INCI names, functions, restrictions" },
  { href: "https://dailymed.nlm.nih.gov/", label: "FDA DailyMed", role: "OTC drug labels" },
  { href: "https://pubmed.ncbi.nlm.nih.gov/", label: "PubMed", role: "Cited studies behind every rule" },
];

function SourceLinks() {
  return (
    <Column id="footer-sources" title="Data sources">
      {SOURCES.map((source) => (
        <li key={source.href}>
          <a className={COL_LINK} href={source.href} target="_blank" rel="noreferrer noopener">
            {source.label}
            <Icon name="arrowUpRight" size={12} strokeWidth={2.5} className="transition-transform duration-150 group-hover:-translate-y-px group-hover:translate-x-px" />
          </a>
        </li>
      ))}
    </Column>
  );
}

export function SiteFooter() {
  return (
    <footer className="mt-16 border-t-4 border-cocoa bg-cocoa text-paper md:mt-24">
      <div className="mx-auto w-full max-w-7xl px-6 py-16 md:px-10 md:py-24">
        <div className="grid grid-cols-1 gap-12 md:grid-cols-[1.4fr_repeat(3,1fr)] md:gap-16">
          <div className="flex max-w-[42ch] flex-col gap-6">
            <span className="text-paper">
              <Logomark size={44} />
            </span>
            <p className="font-sans text-sm leading-relaxed text-paper/70">
              Deterministic routine compatibility analysis. Every conflict, caution and synergy traces back to a
              parsed ingredient list and a cited rule.
            </p>
            <p className="font-sans text-xs leading-relaxed text-paper/50">
              Ingredient data from EU CosIng via Open Beauty Facts, under ODbL.
            </p>
          </div>

          <SectionLinks />
          <AccountLinks />
          <SourceLinks />
        </div>

        {/* The wordmark as an image: set as large as the container allows. */}
        <p
          className="mt-16 select-none overflow-hidden font-sans text-[clamp(2.25rem,9vw,8.5rem)] font-black uppercase leading-[0.8] tracking-tighter text-paper/10 md:mt-24"
          aria-hidden="true"
        >
          SkincareSync
        </p>

        <div className="mt-10 flex flex-col gap-4 border-t-2 border-cocoa/30 pt-8 md:flex-row md:items-center md:justify-between">
          <p className="max-w-[68ch] font-sans text-xs leading-relaxed text-paper/60">
            © {new Date().getFullYear()} SkincareSync. Results are informational only and are not medical advice.
            Consult a dermatologist about your own skin.
          </p>
          {/* TODO: these two need real routes before launch; inert placeholders rather than dead links. */}
          <ul className="flex items-center gap-6 font-sans text-2xs label-caps text-paper/60">
            <li>Privacy Policy</li>
            <li>Terms of Use</li>
          </ul>
        </div>
      </div>
    </footer>
  );
}
