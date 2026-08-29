/**
 * Provider sign-in buttons.
 *
 * These are plain links, not fetch calls. OAuth needs a top-level browser
 * navigation to the provider; an XHR would be blocked by CORS and could not
 * show the provider's own consent screen, which is the part the user is meant
 * to see and trust.
 *
 * The list comes from the server, so a provider without credentials configured
 * never renders a button that would dead-end.
 */

import { useEffect, useState } from "react";
import { API_BASE } from "../../lib/api.js";

// Brand marks, drawn rather than imported, so no third-party asset is fetched at
// runtime. Each keeps its official colours -- both providers require their mark
// be recognisable and unmodified.
const MARKS = {
  google: (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true" focusable="false">
      <path fill="#4285F4" d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.7-1.57 2.68-3.88 2.68-6.62z" />
      <path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.8.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.03-3.7H.96v2.33A9 9 0 0 0 9 18z" />
      <path fill="#FBBC05" d="M3.97 10.72a5.4 5.4 0 0 1 0-3.44V4.95H.96a9 9 0 0 0 0 8.1l3.01-2.33z" />
      <path fill="#EA4335" d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.58C13.46.9 11.43 0 9 0A9 9 0 0 0 .96 4.95l3.01 2.33C4.68 5.16 6.66 3.58 9 3.58z" />
    </svg>
  ),
  apple: (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        d="M13.6 9.58c.02-2.03 1.66-3 1.73-3.05-.94-1.38-2.41-1.57-2.93-1.59-1.25-.13-2.44.73-3.07.73-.63 0-1.61-.71-2.65-.69-1.36.02-2.62.79-3.32 2-1.41 2.45-.36 6.08 1.02 8.07.67.97 1.48 2.07 2.53 2.03 1.02-.04 1.4-.66 2.63-.66s1.58.66 2.65.64c1.1-.02 1.79-.99 2.46-1.97.78-1.13 1.1-2.22 1.11-2.28-.02-.01-2.13-.82-2.16-3.23zM11.6 3.6c.56-.68.94-1.62.83-2.56-.81.03-1.79.54-2.37 1.21-.52.6-.97 1.56-.85 2.48.9.07 1.83-.46 2.39-1.13z"
      />
    </svg>
  ),
};

export function SocialButtons({ next = "", label = "Continue with" }) {
  const [providers, setProviders] = useState(null);

  useEffect(() => {
    let active = true;
    fetch(`${API_BASE}/api/auth/oauth/providers`, { credentials: "include" })
      .then((response) => (response.ok ? response.json() : []))
      .then((list) => active && setProviders(list))
      // Social sign-in is an addition, not a requirement. If the list cannot be
      // fetched, the password form below still works.
      .catch(() => active && setProviders([]));
    return () => {
      active = false;
    };
  }, []);

  // Render nothing while loading rather than a placeholder that shifts layout
  // under the primary form.
  if (!providers?.length) return null;

  const query = next ? `?next=${encodeURIComponent(next)}` : "";

  return (
    <>
      <div className="socialButtons">
        {providers.map((provider) => (
          <a
            key={provider.key}
            className={`socialButton socialButton--${provider.key}`}
            href={`${API_BASE}/api/auth/oauth/${provider.key}/start${query}`}
            // A full navigation, deliberately: OAuth cannot run inside fetch.
            data-testid={`social-${provider.key}`}
          >
            <span className="socialButton__mark">{MARKS[provider.key] ?? null}</span>
            <span>
              {label} {provider.display_name}
            </span>
          </a>
        ))}
      </div>
      <div className="authDivider" role="separator">
        <span>or</span>
      </div>
    </>
  );
}

/** Human wording for the `?error=` code the OAuth callback redirects with. */
export const OAUTH_ERRORS = {
  cancelled: "Sign-in was cancelled.",
  expired: "That sign-in attempt timed out. Please try again.",
  invalid_request: "That sign-in attempt was incomplete. Please try again.",
  invalid_id_token: "We could not verify the response from that provider.",
  invalid_flow: "That sign-in attempt timed out. Please try again.",
  provider_unreachable: "We could not reach that sign-in provider. Try again shortly.",
  token_exchange_failed: "That provider rejected the sign-in. Please try again.",
  no_id_token: "That provider did not return an identity.",
  no_email: "That provider did not share an email address, which an account needs.",
  email_unverified:
    "That provider has not verified your email address. Sign in with your password, then connect the account from your security settings.",
  already_linked: "That account is already connected to a different SkincareSync account.",
  account_unavailable: "This account is not available.",
  account_conflict: "We could not complete that sign-in. Please try again.",
};
