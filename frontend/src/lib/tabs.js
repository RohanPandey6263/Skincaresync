/**
 * Top-level sections of the analyser.
 *
 * These were anchors down one long page. They are tabs now: one section is
 * mounted at a time, so the routine builder and a long compatibility report no
 * longer compete for the same scroll.
 *
 * Each tab keeps the hash its section used to answer to, so existing links --
 * including the ones inside the marketing copy -- still land in the right
 * place, and a reload or a shared URL restores the tab.
 */

export const TABS = [
  { key: "home", label: "Home", hash: "#top" },
  { key: "analyze", label: "Analyze", hash: "#workspace" },
  { key: "report", label: "Report", hash: "#report" },
  { key: "catalog", label: "Catalog", hash: "#catalog" },
];

/** Administrators only: the API 404s this route for everyone else. */
export const ADMIN_TABS = [{ key: "backlog", label: "Research backlog", hash: "#backlog" }];

const ALL_TABS = [...TABS, ...ADMIN_TABS];

const TAB_BY_HASH = new Map(ALL_TABS.map((tab) => [tab.hash, tab.key]));

// "How it works" was its own tab before it moved onto the landing page.
// Keep its old anchor working rather than dead-ending a shared link.
TAB_BY_HASH.set("#how-it-works", "home");

export const DEFAULT_TAB = "home";

export function tabHash(key) {
  return ALL_TABS.find((tab) => tab.key === key)?.hash ?? TABS[0].hash;
}

/**
 * The tab a hash names, or `fallback` when it names something else.
 *
 * The fallback matters: "#main" is the skip link's target, not a tab, and an
 * unrecognised hash must leave the current tab alone rather than bounce the
 * user home.
 */
export function tabFromHash(fallback = DEFAULT_TAB) {
  return TAB_BY_HASH.get(window.location.hash) ?? fallback;
}
