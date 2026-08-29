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
