export const API_BASE = import.meta.env.VITE_API_URL ?? "http://localhost:8000";

export class ApiError extends Error {
  constructor(message, status = 0) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

const STATUS_FALLBACK = {
  404: "We could not find a match for that request.",
  422: "Some of the submitted values were not valid.",
  502: "The product lookup service is unavailable right now.",
  503: "The service is temporarily unavailable.",
};

async function request(path, options) {
  let response;
  try {
    response = await fetch(`${API_BASE}${path}`, options);
  } catch (error) {
    if (error?.name === "AbortError") throw error;
    throw new ApiError(
      "Cannot reach the SkincareSync API. Confirm the backend is running on " + API_BASE + ".",
    );
  }

  if (!response.ok) {
    let detail = null;
    try {
      const body = await response.json();
      if (typeof body?.detail === "string") detail = body.detail;
    } catch {
      /* response had no JSON body */
    }
    throw new ApiError(
      detail ?? STATUS_FALLBACK[response.status] ?? `Request failed (${response.status}).`,
      response.status,
    );
  }

  return response.json();
}

export function getHealth() {
  return request("/api/health");
}

export function lookupProductByCode(code) {
  return request(`/api/products/code?${new URLSearchParams({ value: code })}`);
}

export function searchProducts({ brand = "", name = "" }) {
  return request(`/api/products/search?${new URLSearchParams({ brand, name })}`);
}

export function analyzeRoutine({ skinProfile, amProducts, pmProducts }) {
  return request("/api/analyze", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      skin_profile: { skin_type: skinProfile.skinType, concerns: skinProfile.concerns },
      am_products: amProducts.map(toProductPayload),
      pm_products: pmProducts.map(toProductPayload),
    }),
  });
}

export function getGaps() {
  return request("/api/gaps");
}

export function searchIngredients({
  query = "",
  functions = [],
  source,
  letter,
  onlyWithInteractions = false,
  onlyRestricted = false,
  limit = 20,
  offset = 0,
  signal,
} = {}) {
  const params = new URLSearchParams({
    q: query,
    limit: String(limit),
    offset: String(offset),
  });
  for (const fn of functions) params.append("functions", fn);
  if (source) params.set("source", source);
  if (letter) params.set("letter", letter);
  if (onlyWithInteractions) params.set("only_with_interactions", "true");
  if (onlyRestricted) params.set("only_restricted", "true");
  return request(`/api/ingredients?${params}`, { signal });
}

export function suggestIngredients(query, signal) {
  return request(
    `/api/ingredients/suggest?${new URLSearchParams({ q: query })}`,
    { signal },
  );
}

export function getIngredientFacets() {
  return request("/api/ingredients/facets");
}

export function getIngredient(id) {
  return request(`/api/ingredients/${id}`);
}

function toProductPayload(product) {
  return {
    brand: product.brand ?? "",
    name: product.name,
    raw_ingredient_list: product.raw_ingredient_list,
  };
}
