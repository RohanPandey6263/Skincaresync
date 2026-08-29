"""OIDC client: authorization URL, token exchange, ID token verification.

No cryptography is implemented here. Signature verification and JWKS handling
are PyJWT's; PKCE values come from `secrets`. This module wires them together
and enforces the checks that make the result trustworthy:

* the signature verifies against the provider's published keys
* `iss` is one the provider is allowed to claim
* `aud` is our client id, so a token minted for a different application is not
  accepted
* `exp` and `iat` are current
* `nonce` matches the value bound to this browser's flow, so a token captured
  elsewhere cannot be replayed

Skipping any of these turns "verify the ID token" into "decode the ID token",
which is what makes the difference between authentication and a claim.
"""

from __future__ import annotations

import base64
import hashlib
import logging
import secrets
from dataclasses import dataclass
from urllib.parse import urlencode

import httpx
import jwt
from jwt import PyJWKClient

from .providers import OAuthProvider

logger = logging.getLogger(__name__)

# Providers answer in well under this. A bound matters because the token
# exchange happens while the user waits on a redirect.
HTTP_TIMEOUT_SECONDS = 10.0
MAX_RESPONSE_BYTES = 1024 * 1024


class OAuthError(Exception):
    """A social sign-in could not be completed."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class OAuthIdentity:
    """What a provider asserted about the person who just signed in."""

    provider: str
    subject: str
    email: str | None
    email_verified: bool
    display_name: str | None


def generate_pkce_pair() -> tuple[str, str]:
    """Return (verifier, challenge) for PKCE S256.

    PKCE stops an authorization code that leaks -- through a redirect log, a
    referrer header, or a malicious app registered for the same URI -- from
    being exchangeable by anyone but the client that began the flow.
    """
    verifier = secrets.token_urlsafe(64)
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return verifier, challenge


def build_authorization_url(
    provider: OAuthProvider,
    redirect_uri: str,
    state: str,
    nonce: str,
    code_challenge: str,
) -> str:
    params = {
        "client_id": provider.client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(provider.scopes),
        "state": state,
        "nonce": nonce,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
    }
    if provider.uses_form_post:
        # Apple will only release email and name scopes to a form_post response.
        params["response_mode"] = "form_post"
    else:
        # Ask Google for the account chooser rather than silently reusing
        # whichever account the browser signed into last.
        params["prompt"] = "select_account"
    return f"{provider.authorize_url}?{urlencode(params)}"


def exchange_code(
    provider: OAuthProvider,
    code: str,
    redirect_uri: str,
    code_verifier: str,
) -> dict:
    """Trade the authorization code for tokens."""
    data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
        "client_id": provider.client_id,
        "client_secret": provider.secret(),
        "code_verifier": code_verifier,
    }
    try:
        response = httpx.post(
            provider.token_url,
            data=data,
            headers={"Accept": "application/json"},
            timeout=HTTP_TIMEOUT_SECONDS,
        )
    except httpx.HTTPError as exc:
        logger.warning("%s token exchange failed to connect: %s", provider.key, exc)
        raise OAuthError("provider_unreachable", "Could not reach the sign-in provider.") from None

    if response.status_code != 200:
        # The body can echo the client secret back in an error description, so
        # only the status is logged.
        logger.warning("%s token exchange returned %s", provider.key, response.status_code)
        raise OAuthError("token_exchange_failed", "The sign-in provider rejected this request.")

    payload = response.json()
    if "id_token" not in payload:
        raise OAuthError("no_id_token", "The sign-in provider did not return an identity.")
    return payload


# One client per provider, so the JWKS is fetched once and cached rather than on
# every sign-in. PyJWKClient handles refresh when an unknown key id appears,
# which is what makes provider key rotation a non-event.
_jwk_clients: dict[str, PyJWKClient] = {}


def _jwk_client(provider: OAuthProvider) -> PyJWKClient:
    client = _jwk_clients.get(provider.key)
    if client is None:
        client = PyJWKClient(provider.jwks_url, cache_keys=True, lifespan=3600)
        _jwk_clients[provider.key] = client
    return client


def reset_jwk_clients() -> None:
    """Drop cached signing keys. Used by tests."""
    _jwk_clients.clear()


def verify_id_token(provider: OAuthProvider, id_token: str, nonce: str) -> dict:
    """Verify an ID token and return its claims, or raise."""
    try:
        signing_key = _jwk_client(provider).get_signing_key_from_jwt(id_token)
        claims = jwt.decode(
            id_token,
            signing_key.key,
            algorithms=["RS256", "ES256"],
            audience=provider.client_id,
            issuer=list(provider.issuers),
            options={
                "require": ["exp", "iat", "iss", "aud", "sub"],
                "verify_exp": True,
                "verify_iat": True,
                "verify_aud": True,
                "verify_iss": True,
                "verify_signature": True,
            },
        )
    except jwt.PyJWTError as exc:
        logger.warning("%s id_token rejected: %s", provider.key, type(exc).__name__)
        raise OAuthError("invalid_id_token", "Could not verify the sign-in response.") from None
    except Exception as exc:
        logger.warning("%s JWKS lookup failed: %s", provider.key, type(exc).__name__)
        raise OAuthError("provider_unreachable", "Could not reach the sign-in provider.") from None

    # PyJWT does not check nonce; it is an OIDC concept, not a JWT one. Without
    # this an ID token obtained for one browser could be replayed into another.
    if not secrets.compare_digest(str(claims.get("nonce", "")), nonce):
        logger.warning("%s id_token nonce mismatch", provider.key)
        raise OAuthError("invalid_id_token", "Could not verify the sign-in response.")

    if not claims.get("sub"):
        raise OAuthError("invalid_id_token", "The provider did not identify the account.")

    return claims


def identity_from_claims(
    provider: OAuthProvider,
    claims: dict,
    apple_user_payload: dict | None = None,
) -> OAuthIdentity:
    """Reduce provider claims to the fields the application stores."""
    email = claims.get("email")
    email = email.strip().lower() if isinstance(email, str) and email.strip() else None

    # Google sends a real boolean; Apple sends the string "true". Anything else
    # is treated as unverified, which is the safe direction: an unverified
    # address is never auto-linked to an existing account.
    raw_verified = claims.get("email_verified")
    email_verified = raw_verified is True or str(raw_verified).lower() == "true"

    display_name = claims.get("name")
    if not display_name and apple_user_payload:
        # Apple sends the name once, in the first callback body, never in the
        # ID token and never again.
        name = apple_user_payload.get("name") or {}
        parts = [name.get("firstName"), name.get("lastName")]
        display_name = " ".join(part for part in parts if part) or None

    if isinstance(display_name, str):
        display_name = display_name.strip()[:80] or None
    else:
        display_name = None

    return OAuthIdentity(
        provider=provider.key,
        subject=str(claims["sub"]),
        email=email,
        email_verified=email_verified,
        display_name=display_name,
    )
