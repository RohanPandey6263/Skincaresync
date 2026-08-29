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
  429: "Too many requests. Please wait a moment and try again.",
  502: "The product lookup service is unavailable right now.",
  503: "The service is busy. Please try again in a moment.",
};

// No request may hang indefinitely. Product lookup reaches out to DailyMed and
// Open Beauty Facts, so it is allowed longer than a catalog query, but the
// spinner always resolves one way or the other.
const DEFAULT_TIMEOUT_MS = 12000;
const LOOKUP_TIMEOUT_MS = 20000;

function withTimeout(options = {}, timeoutMs = DEFAULT_TIMEOUT_MS) {
  // A caller-supplied signal (used to cancel superseded searches) must still
  // win, so the two are combined rather than one replacing the other.
  const timeoutSignal = AbortSignal.timeout(timeoutMs);
  const signal = options.signal
    ? AbortSignal.any([options.signal, timeoutSignal])
    : timeoutSignal;
  return { ...options, signal, __timeoutSignal: timeoutSignal };
}

const CSRF_COOKIE = "skincaresync_csrf";

function readCookie(name) {
  const match = document.cookie.match(new RegExp(`(?:^|;\\s*)${name}=([^;]*)`));
  return match ? decodeURIComponent(match[1]) : null;
}

async function request(path, options = {}) {
  const { __timeoutSignal, ...fetchOptions } = options;

  // Cookies must travel so the API can recognise a signed-in caller, and any
  // state-changing request from one must carry the CSRF token. Anonymous
  // callers send neither and the server exempts them.
  fetchOptions.credentials = "include";
  const method = (fetchOptions.method || "GET").toUpperCase();
  if (!["GET", "HEAD", "OPTIONS"].includes(method)) {
    const csrf = readCookie(CSRF_COOKIE);
    if (csrf) {
      fetchOptions.headers = { ...fetchOptions.headers, "X-CSRF-Token": csrf };
    }
  }

  let response;
  try {
    response = await fetch(`${API_BASE}${path}`, fetchOptions);
  } catch (error) {
    if (__timeoutSignal?.aborted) {
      throw new ApiError("That request took too long. Please try again.", 408);
    }
    if (error?.name === "AbortError" || error?.name === "TimeoutError") throw error;
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
  return request("/api/health", withTimeout());
}

export function lookupProductByCode(code) {
  return request(
    `/api/products/code?${new URLSearchParams({ value: code })}`,
    withTimeout({}, LOOKUP_TIMEOUT_MS),
  );
}

export function searchProducts({ brand = "", name = "" }) {
  return request(
    `/api/products/search?${new URLSearchParams({ brand, name })}`,
    withTimeout({}, LOOKUP_TIMEOUT_MS),
  );
}

export function analyzeRoutine({ skinProfile, amProducts, pmProducts }) {
  return request("/api/analyze", withTimeout({
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      skin_profile: { skin_type: skinProfile.skinType, concerns: skinProfile.concerns },
      am_products: amProducts.map(toProductPayload),
      pm_products: pmProducts.map(toProductPayload),
    }),
  }));
}

export function getGaps() {
  return request("/api/gaps", withTimeout());
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
  return request(`/api/ingredients?${params}`, withTimeout({ signal }));
}

export function suggestIngredients(query, signal) {
  return request(
    `/api/ingredients/suggest?${new URLSearchParams({ q: query })}`,
    withTimeout({ signal }),
  );
}

export function getIngredientFacets() {
  return request("/api/ingredients/facets", withTimeout());
}

export function getIngredient(id) {
  return request(`/api/ingredients/${id}`, withTimeout());
}

function toProductPayload(product) {
  return {
    brand: product.brand ?? "",
    name: product.name,
    raw_ingredient_list: product.raw_ingredient_list,
  };
}
