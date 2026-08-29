// Product URLs and images come from Open Beauty Facts, which anyone can edit,
// and from scraped brand pages. React blocks `javascript:` in href on its own,
// but nothing stops `data:`, `blob:` or an unexpected custom scheme, and an
// unchecked href is a phishing destination presented under our own label.
// Only ordinary web URLs are rendered; anything else is dropped.
const SAFE_URL_SCHEMES = new Set(["http:", "https:"]);

export function safeExternalUrl(value) {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const url = new URL(value, window.location.origin);
    return SAFE_URL_SCHEMES.has(url.protocol) ? url.href : null;
  } catch {
    return null;
  }
}

export function citationUrl(citation) {
  const match = /PMID[:\s]*(\d+)/i.exec(citation ?? "");
  return match ? `https://pubmed.ncbi.nlm.nih.gov/${match[1]}/` : null;
}

export function pluralize(count, singular, plural = `${singular}s`) {
  return `${count} ${count === 1 ? singular : plural}`;
}

export function sentenceCase(value) {
  if (!value) return "";
  return value.charAt(0).toUpperCase() + value.slice(1);
}

export function productLabel(product, fallback = "Untitled product") {
  return [product?.brand, product?.name].filter(Boolean).join(" ").trim() || fallback;
}

export function formatFunction(slug) {
  return sentenceCase((slug || "").replace(/-/g, " "));
}

export function firstIdentifier(value) {
  if (!value) return null;
  return value.split("/")[0].trim() || null;
}

export function formatRelativeDate(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
