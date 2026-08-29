"""OpenID Connect provider definitions.

Google and Apple are both OIDC, so one code path serves both. They differ in
three places, and each difference is isolated in this module:

* Apple's client secret is not a static string. It is an ES256 JWT signed with a
  key downloaded from the developer portal, valid for at most six months, which
  the application mints on demand.
* Apple returns the user's name exactly once, in the body of the first callback,
  and never again. If it is not captured then it is gone.
* Apple posts its callback as a cross-site form submission rather than a
  redirect with query parameters, which has consequences for cookie SameSite
  policy documented in `flows.py`.

A provider is enabled only when its credentials are configured, so an
unconfigured provider cannot appear in the UI or be started by a crafted URL.
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass, field
from functools import lru_cache

import jwt


@dataclass(frozen=True)
class OAuthProvider:
    key: str
    display_name: str
    authorize_url: str
    token_url: str
    jwks_url: str
    issuers: tuple[str, ...]
    scopes: tuple[str, ...]
    client_id: str
    client_secret: str | None = field(default=None, repr=False)

    # Apple only. Its callback is a POST, which changes how the flow cookie must
    # be scoped for the browser to send it back.
    uses_form_post: bool = False

    # Apple's ES256 client-secret material.
    team_id: str | None = None
    key_id: str | None = None
    private_key: str | None = field(default=None, repr=False)

    def secret(self) -> str:
        """The client secret to present at the token endpoint."""
        if self.key == "apple":
            return _apple_client_secret(self)
        assert self.client_secret is not None
        return self.client_secret


def _apple_client_secret(provider: OAuthProvider) -> str:
    """Mint Apple's short-lived client secret.

    Apple does not issue a static secret. The client authenticates with a JWT it
    signs itself using a `.p8` key from the developer portal. Apple caps the
    lifetime at six months; a short one is used here and regenerated per request,
    because signing is cheap and a long-lived secret in memory buys nothing.
    """
    if not (provider.team_id and provider.key_id and provider.private_key):
        raise ValueError(
            "Apple sign-in needs APPLE_TEAM_ID, APPLE_KEY_ID and APPLE_PRIVATE_KEY"
        )

    now = int(time.time())
    return jwt.encode(
        {
            "iss": provider.team_id,
            "iat": now,
            "exp": now + 300,
            "aud": "https://appleid.apple.com",
            "sub": provider.client_id,
        },
        provider.private_key,
        algorithm="ES256",
        headers={"kid": provider.key_id},
    )


def _env(name: str) -> str | None:
    value = os.getenv(name)
    return value.strip() if value and value.strip() else None


def _apple_private_key() -> str | None:
    """Apple's signing key, from a file path or an inline value.

    A path is preferred: it keeps the key out of the process environment, where
    it would show up in crash dumps and `/proc`. The inline form exists because
    some hosts only offer environment variables. Newlines are normalised because
    environment variables routinely arrive with them escaped.
    """
    path = _env("APPLE_PRIVATE_KEY_PATH")
    if path:
        try:
            return open(path, encoding="utf-8").read()
        except OSError as exc:
            raise ValueError(f"cannot read APPLE_PRIVATE_KEY_PATH: {exc}") from None
    inline = _env("APPLE_PRIVATE_KEY")
    return inline.replace("\\n", "\n") if inline else None


@lru_cache(maxsize=1)
def get_providers() -> dict[str, OAuthProvider]:
    """Every provider with complete credentials. Cached; config does not change."""
    providers: dict[str, OAuthProvider] = {}

    google_id = _env("GOOGLE_CLIENT_ID")
    google_secret = _env("GOOGLE_CLIENT_SECRET")
    if google_id and google_secret:
        providers["google"] = OAuthProvider(
            key="google",
            display_name="Google",
            authorize_url="https://accounts.google.com/o/oauth2/v2/auth",
            token_url="https://oauth2.googleapis.com/token",
            jwks_url="https://www.googleapis.com/oauth2/v3/certs",
            # Google is inconsistent about the scheme in `iss`; both are valid.
            issuers=("https://accounts.google.com", "accounts.google.com"),
            scopes=("openid", "email", "profile"),
            client_id=google_id,
            client_secret=google_secret,
        )

    apple_id = _env("APPLE_CLIENT_ID")
    apple_team = _env("APPLE_TEAM_ID")
    apple_key_id = _env("APPLE_KEY_ID")
    apple_key = _apple_private_key()
    if apple_id and apple_team and apple_key_id and apple_key:
        providers["apple"] = OAuthProvider(
            key="apple",
            display_name="Apple",
            authorize_url="https://appleid.apple.com/auth/authorize",
            token_url="https://appleid.apple.com/auth/token",
            jwks_url="https://appleid.apple.com/auth/keys",
            issuers=("https://appleid.apple.com",),
            scopes=("openid", "email", "name"),
            client_id=apple_id,
            uses_form_post=True,
            team_id=apple_team,
            key_id=apple_key_id,
            private_key=apple_key,
        )

    return providers


def get_provider(key: str) -> OAuthProvider | None:
    return get_providers().get(key)


def reset_provider_cache() -> None:
    """Drop cached provider configuration. Used by tests."""
    get_providers.cache_clear()
