/**
 * "Get the iPhone app" page.
 *
 * The app is real and builds from this repository, but it has no App Store
 * listing yet. Rather than link somewhere that 404s, `APP_STORE_URL` is empty
 * and the page shows the honest state: what the app does, what it needs, and
 * how to run it from source today. Set the constant when the listing exists
 * and the primary action becomes a live download button with no other edit.
 */

import { AnchorButton, ButtonLink } from "./ui/Button.jsx";
import { Icon } from "./ui/Icon.jsx";
import { Logomark } from "./ui/Icon.jsx";
import { Container, Headline, SectionLabel } from "./ui/Section.jsx";
import { SiteFooter } from "./SiteFooter.jsx";
import { Link } from "../lib/router.jsx";

/** Set this to the App Store URL when the listing is live. Empty means "not published". */
export const APP_STORE_URL = "";

/** Everything the shipped app actually does. No feature here is aspirational. */
const FEATURES = [
  {
    title: "Build morning and evening routines",
    body: "Search by brand and product name, scan a barcode, or paste the ingredient list straight off the packaging. Drafts survive relaunching the app.",
  },
  {
    title: "Scan with the camera",
    body: "The scanner reads EAN, UPC, Code 128 and QR codes, then loads the ingredient list. Typing the number always works, so camera access is never required.",
  },
  {
    title: "Read the whole report",
    body: "Conflicts, cautions and synergies in safety order, each with its severity, whether it happens in one routine or across AM and PM, and a link to the study behind it.",
  },
  {
    title: "Browse the ingredient catalog",
    body: "The same 22,288 INCI names, with functions, CosIng restrictions, known interactions and related entries.",
  },
];

const REQUIREMENTS = [
  { label: "Device", value: "iPhone" },
  { label: "System", value: "iOS 17 or later" },
  { label: "Account", value: "Optional — analysis works signed out" },
  { label: "Backend", value: "A reachable SkincareSync API" },
];

/**
 * A line-art iPhone showing the app's own layout: the tab strip across the
 * top, a verdict headline, and a coral-edged finding. Ornament, but an honest
 * one — it is the shape of the real Report screen.
 */
function DeviceDrawing() {
  const stroke = {
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 3,
    strokeLinejoin: "round",
    strokeLinecap: "round",
  };

  return (
    <div
      className="swiss-grid-pattern flex min-h-[320px] items-center justify-center border-cocoa bg-sand px-8 py-12 text-cocoa lg:min-h-[560px] lg:border-l-4"
      aria-hidden="true"
    >
      <svg viewBox="0 0 240 460" className="h-auto w-full max-w-[260px]" focusable="false">
        {/* Body and screen. */}
        <rect x="6" y="6" width="228" height="448" rx="30" className="fill-paper" {...stroke} />
        <rect x="18" y="18" width="204" height="424" rx="20" className="fill-paper" {...stroke} />
        <rect x="96" y="24" width="48" height="9" rx="4.5" fill="currentColor" />

        {/* The tab strip: three cells, the first one filled. */}
        <rect x="18" y="44" width="68" height="34" fill="currentColor" />
        <path d="M86 44 V78 M154 44 V78 M18 78 H222" {...stroke} strokeWidth="3" />
        <rect x="34" y="56" width="36" height="6" rx="3" className="fill-paper" />
        <rect x="102" y="56" width="36" height="6" rx="3" fill="currentColor" opacity="0.35" />
        <rect x="170" y="56" width="36" height="6" rx="3" fill="currentColor" opacity="0.35" />

        {/* Verdict headline. */}
        <rect x="34" y="102" width="26" height="7" rx="3.5" className="fill-coral" />
        <rect x="34" y="122" width="150" height="17" rx="3" fill="currentColor" />
        <rect x="34" y="146" width="112" height="17" rx="3" fill="currentColor" />

        {/* Three count cells. */}
        <path d="M18 184 H222 M84 184 V226 M156 184 V226 M18 226 H222" {...stroke} strokeWidth="3" />
        <rect x="34" y="196" width="18" height="20" rx="3" className="fill-coral" />
        <rect x="100" y="196" width="14" height="20" rx="3" fill="currentColor" />
        <rect x="172" y="196" width="14" height="20" rx="3" fill="currentColor" />

        {/* A conflict finding, coral edge on the left. */}
        <rect x="34" y="252" width="172" height="86" className="fill-paper" {...stroke} />
        <rect x="34" y="252" width="9" height="86" className="fill-coral" />
        <rect x="56" y="268" width="62" height="9" rx="4.5" className="fill-coral" />
        <rect x="56" y="290" width="126" height="8" rx="4" fill="currentColor" />
        <rect x="56" y="306" width="104" height="6" rx="3" fill="currentColor" opacity="0.45" />
        <rect x="56" y="318" width="118" height="6" rx="3" fill="currentColor" opacity="0.45" />

        {/* A synergy finding on mint. */}
        <rect x="34" y="352" width="172" height="58" className="fill-mint" {...stroke} />
        <rect x="56" y="368" width="52" height="8" rx="4" fill="currentColor" />
        <rect x="56" y="386" width="120" height="6" rx="3" fill="currentColor" opacity="0.45" />
      </svg>
    </div>
  );
}

/** A shell command, set in mono on sand. */
function Command({ children }) {
  return (
    <code className="block overflow-x-auto border-2 border-cocoa bg-sand px-4 py-3 font-mono text-sm text-ink">
      {children}
    </code>
  );
}

export function IosAppPage() {
  const published = Boolean(APP_STORE_URL);

  return (
    <>
      <main className="flex-1 bg-paper" id="main" tabIndex={-1}>
        {/* Reached from a link rather than the tab bar, so it carries its own way back. */}
        <div className="border-b-4 border-cocoa">
          <Container className="flex h-20 items-center justify-between gap-6">
            <Link
              to="/"
              className="flex items-center gap-3 text-ink no-underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral-deep focus-visible:ring-offset-4"
            >
              <Logomark size={36} />
              <span className="hidden font-sans text-lg font-black uppercase tracking-tighter sm:block">
                SkincareSync
              </span>
            </Link>
            <ButtonLink to="/" variant="secondary" size="sm" iconAfter="arrowRight">
              Back to the analyser
            </ButtonLink>
          </Container>
        </div>

        <Container>
          {/* 01 — the offer. 7:5, headline against the device drawing. */}
          <section
            className="grid grid-cols-1 border-b-4 border-cocoa lg:grid-cols-12"
            aria-labelledby="ios-title"
          >
            <div className="flex flex-col gap-8 py-12 md:py-20 lg:col-span-7 lg:pr-12">
              <SectionLabel number="01">SkincareSync for iPhone</SectionLabel>
              <Headline as="h1" size="hero" id="ios-title">
                The same engine, in your <span className="text-coral-deep">pocket.</span>
              </Headline>
              <p className="max-w-[52ch] font-sans text-lg leading-relaxed text-cocoa">
                A native iPhone app built on the same cited interaction database as this site. Scan a barcode in
                the shop, build your morning and evening routines, and read the whole report on the device.
              </p>

              {published ? (
                <div className="flex flex-col gap-4 sm:flex-row sm:items-center">
                  <AnchorButton
                    href={APP_STORE_URL}
                    variant="primary"
                    size="lg"
                    iconAfter="arrowUpRight"
                    target="_blank"
                    rel="noreferrer noopener"
                  >
                    Download on the App Store
                  </AnchorButton>
                  <p className="font-sans text-xs label-caps text-cocoa">Free · iPhone · iOS 17+</p>
                </div>
              ) : (
                /* No listing yet, so no button that dead-ends. The status is
                   stated plainly and the build instructions are below. */
                <div className="flex flex-col gap-4">
                  <div className="relative flex items-start gap-4 border-2 border-cocoa bg-sand py-4 pl-7 pr-5">
                    <span className="absolute inset-y-0 left-0 w-2 bg-coral" aria-hidden="true" />
                    <Icon name="info" size={18} strokeWidth={2.25} className="mt-0.5 shrink-0 text-ink" />
                    <div className="flex flex-col gap-2">
                      <p className="font-sans text-xs label-caps text-ink">Not on the App Store yet</p>
                      <p className="max-w-[52ch] font-sans text-sm leading-relaxed text-cocoa">
                        The app is finished and runs on iPhone and the simulator, but it has no store listing.
                        You can build and run it from the repository today — the steps are in section 04.
                      </p>
                    </div>
                  </div>
                  <div className="flex flex-col gap-4 sm:flex-row sm:items-center">
                    <AnchorButton href="#install" variant="primary" size="lg" iconAfter="arrowRight">
                      How to install it
                    </AnchorButton>
                    <p className="font-sans text-xs label-caps text-cocoa">iPhone · iOS 17+</p>
                  </div>
                </div>
              )}
            </div>

            <div className="lg:col-span-5">
              <DeviceDrawing />
            </div>
          </section>

          {/* 02 — what it does. 4:8, sticky heading against a ruled list. */}
          <section
            className="grid grid-cols-1 gap-10 border-b-4 border-cocoa py-16 md:py-24 lg:grid-cols-12 lg:gap-12"
            aria-labelledby="ios-features-title"
          >
            <div className="flex flex-col gap-6 lg:col-span-4 lg:sticky lg:top-12 lg:self-start">
              <SectionLabel number="02">On the device</SectionLabel>
              <Headline id="ios-features-title">Everything the site does.</Headline>
              <p className="max-w-[36ch] font-sans text-base leading-relaxed text-cocoa">
                Nothing is reimplemented on the phone. The app calls the same API, so a report reads identically
                in both places.
              </p>
            </div>

            <ol className="flex flex-col border-t-4 border-cocoa lg:col-span-8">
              {FEATURES.map((feature, index) => (
                <li
                  key={feature.title}
                  className="group grid grid-cols-[3.5rem_1fr] gap-6 border-b-2 border-cocoa py-8 md:grid-cols-[6rem_1fr] md:gap-10"
                >
                  <span
                    className="font-sans text-4xl font-black leading-none tracking-tighter text-cocoa/25 transition-colors duration-150 group-hover:text-coral-deep md:text-6xl"
                    aria-hidden="true"
                  >
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <div className="flex flex-col gap-3">
                    <h3 className="font-sans text-feature font-black uppercase text-ink">{feature.title}</h3>
                    <p className="max-w-[56ch] font-sans text-base leading-relaxed text-cocoa">{feature.body}</p>
                  </div>
                </li>
              ))}
            </ol>
          </section>

          {/* 03 — what it needs. */}
          <section
            className="grid grid-cols-1 gap-10 border-b-4 border-cocoa py-16 md:py-24 lg:grid-cols-12"
            aria-labelledby="ios-requirements-title"
          >
            <div className="flex flex-col gap-6 lg:col-span-5">
              <SectionLabel number="03">Requirements</SectionLabel>
              <Headline id="ios-requirements-title">What it needs.</Headline>
            </div>
            <dl className="grid grid-cols-1 gap-px border-4 border-cocoa bg-cocoa sm:grid-cols-2 lg:col-span-7">
              {REQUIREMENTS.map((item) => (
                <div key={item.label} className="flex flex-col gap-3 bg-paper p-6">
                  <dt className="font-sans text-2xs label-caps text-cocoa">{item.label}</dt>
                  <dd className="font-sans text-base font-bold text-ink">{item.value}</dd>
                </div>
              ))}
            </dl>
          </section>

          {/* 04 — how to install it today. */}
          <section
            className="grid grid-cols-1 gap-10 py-16 md:py-24 lg:grid-cols-12 lg:gap-12"
            id="install"
            aria-labelledby="ios-install-title"
          >
            <div className="flex flex-col gap-6 lg:col-span-4">
              <SectionLabel number="04">Install</SectionLabel>
              <Headline id="ios-install-title">Build it from source.</Headline>
              <p className="max-w-[36ch] font-sans text-base leading-relaxed text-cocoa">
                The Xcode project is in the repository. It has no third-party dependencies, so there is nothing to
                fetch before it builds.
              </p>
            </div>

            <ol className="flex flex-col gap-8 lg:col-span-8">
              <li className="flex flex-col gap-4 border-t-2 border-cocoa pt-6">
                <p className="font-sans text-xs label-caps text-ink">01 · Start the backend</p>
                <Command>uvicorn skincaresync.api:app --reload</Command>
                <p className="font-sans text-sm leading-relaxed text-cocoa">
                  Debug builds talk to <span className="font-mono">http://127.0.0.1:8000</span> by default. For a
                  physical iPhone, point <span className="font-mono">API_BASE_URL</span> in{" "}
                  <span className="font-mono">ios/Config/Debug.xcconfig</span> at your Mac&rsquo;s LAN address.
                </p>
              </li>
              <li className="flex flex-col gap-4 border-t-2 border-cocoa pt-6">
                <p className="font-sans text-xs label-caps text-ink">02 · Open the project</p>
                <Command>open ios/SkincareSync.xcodeproj</Command>
              </li>
              <li className="flex flex-col gap-4 border-t-2 border-cocoa pt-6">
                <p className="font-sans text-xs label-caps text-ink">03 · Run</p>
                <p className="font-sans text-sm leading-relaxed text-cocoa">
                  Select the shared <span className="font-mono">SkincareSync</span> scheme and an iPhone simulator,
                  then press Run. Installing on your own iPhone additionally needs a signing team set in
                  Xcode&rsquo;s Signing &amp; Capabilities tab.
                </p>
              </li>
            </ol>
          </section>
        </Container>
      </main>

      <SiteFooter />
    </>
  );
}
