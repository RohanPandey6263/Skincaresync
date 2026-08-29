/**
 * Authentication API client.
 *
 * Every request sends cookies (`credentials: "include"`) and every unsafe
 * request carries the CSRF token as a header. The token comes from a cookie the
 * server sets non-HttpOnly for exactly this purpose.
 *
 * No token, session identifier or password is ever written to localStorage or
 * sessionStorage. The session lives only in an HttpOnly cookie the page cannot
 * read, so an XSS bug cannot exfiltrate it.
 */

import { API_BASE, ApiError } from "./api.js";

const CSRF_COOKIE = "skincaresync_csrf";
const TIMEOUT_MS = 15000;

function readCookie(name) {
  const match = document.cookie.match(new RegExp(`(?:^|;\\s*)${name}=([^;]*)`));
  return match ? decodeURIComponent(match[1]) : null;
}

function fieldErrorsFrom(detail) {
  // FastAPI reports validation failures as a list of {loc, msg}. Map them onto
  // field names so the form can show each message next to its own input.
  if (!Array.isArray(detail)) return null;
  const errors = {};
  for (const item of detail) {
    const field = Array.isArray(item?.loc) ? item.loc[item.loc.length - 1] : null;
    if (field && item?.msg) {
      errors[field] = String(item.msg).replace(/^Value error,\s*/, "");
    }
  }
  return Object.keys(errors).length ? errors : null;
}

export class AuthApiError extends ApiError {
  constructor(message, status, fieldErrors = null, retryAfter = null) {
    super(message, status);
    this.name = "AuthApiError";
    this.fieldErrors = fieldErrors;
    this.retryAfter = retryAfter;
  }
}

async function request(path, { method = "GET", body, signal } = {}) {
  const headers = { Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";

  if (!["GET", "HEAD", "OPTIONS"].includes(method)) {
    const csrf = readCookie(CSRF_COOKIE);
    if (csrf) headers["X-CSRF-Token"] = csrf;
  }

  const timeout = AbortSignal.timeout(TIMEOUT_MS);
  let response;
  try {
    response = await fetch(`${API_BASE}${path}`, {
      method,
      headers,
      // Without this the session cookie is not sent cross-origin from the Vite
      // dev server, and every request looks anonymous.
      credentials: "include",
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
    });
  } catch (error) {
    if (timeout.aborted) throw new AuthApiError("That took too long. Try again.", 408);
    if (error?.name === "AbortError") throw error;
    throw new AuthApiError("Cannot reach the server. Check your connection.", 0);
  }

  if (response.status === 204) return null;

  let payload = null;
  try {
    payload = await response.json();
  } catch {
    /* some errors have no JSON body */
  }

  if (!response.ok) {
    const detail = payload?.detail;
    const fieldErrors = fieldErrorsFrom(detail);
    const message = fieldErrors
      ? "Please correct the highlighted fields."
      : typeof detail === "string"
        ? detail
        : "Something went wrong. Please try again.";
    throw new AuthApiError(
      message,
      response.status,
      fieldErrors,
      response.headers.get("Retry-After"),
    );
  }

  return payload;
}

export const authApi = {
  session: () => request("/api/auth/session"),
  register: (body) => request("/api/auth/register", { method: "POST", body }),
  login: (body) => request("/api/auth/login", { method: "POST", body }),
  logout: () => request("/api/auth/logout", { method: "POST" }),
  logoutAll: () => request("/api/auth/logout-all", { method: "POST" }),
  verifyEmail: (token) => request("/api/auth/verify-email", { method: "POST", body: { token } }),
  resendVerification: (email) =>
    request("/api/auth/resend-verification", { method: "POST", body: { email } }),
  forgotPassword: (email) =>
    request("/api/auth/forgot-password", { method: "POST", body: { email } }),
  resetPassword: (token, password) =>
    request("/api/auth/reset-password", { method: "POST", body: { token, password } }),
  changePassword: (currentPassword, password) =>
    request("/api/auth/change-password", {
      method: "POST",
      body: { current_password: currentPassword, password },
    }),
  listIdentities: () => request("/api/auth/identities"),
  unlinkIdentity: (provider) =>
    request(`/api/auth/identities/${encodeURIComponent(provider)}`, { method: "DELETE" }),
  listSessions: () => request("/api/auth/sessions"),
  revokeSession: (id) => request(`/api/auth/sessions/${id}`, { method: "DELETE" }),
  events: () => request("/api/auth/events"),
  deactivate: () => request("/api/auth/deactivate", { method: "POST" }),
  deleteAccount: (currentPassword) =>
    request("/api/auth/delete", {
      method: "POST",
      body: { current_password: currentPassword, confirm: "DELETE" },
    }),
};
