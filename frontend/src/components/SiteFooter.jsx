import { Logomark } from "./ui/Icon.jsx";

export function SiteFooter() {
  return (
    <footer className="siteFooter">
      <div className="siteFooter__inner">
        <div className="siteFooter__brand">
          <span className="siteFooter__mark">
            <Logomark size={22} />
          </span>
          <p>
            <strong>SkincareSync</strong>
            <span>Deterministic routine compatibility analysis</span>
          </p>
        </div>

        <p className="siteFooter__disclaimer">
          Results come from a rules engine over published literature and are informational only.
          They are not medical advice — consult a dermatologist about your own skin.
        </p>
      </div>
    </footer>
  );
}
