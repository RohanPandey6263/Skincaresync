"""Social sign-in.

No request leaves the machine. A throwaway RSA keypair stands in for a
provider's signing key, so the ID tokens under test are *really* signed and go
through the same PyJWT verification path production uses -- signature, issuer,
audience, expiry and nonce all genuinely checked. Only the network calls (the
token endpoint and the JWKS fetch) are substituted.

That distinction matters: mocking `verify_id_token` itself would prove nothing,
because the verification is the security control.
"""

from __future__ import annotations

import time
from datetime import timedelta

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from sqlalchemy import select

from skincaresync.auth import service as auth_service
from skincaresync.auth.models import OAuthFlow, User, UserIdentity, utcnow
from skincaresync.auth.oauth import client as oauth_client
from skincaresync.auth.oauth import providers as oauth_providers
from skincaresync.auth.oauth import service as oauth_service
from skincaresync.auth.oauth.client import OAuthError, verify_id_token
from skincaresync.auth.oauth.providers import OAuthProvider
from tests.test_auth_accounts import PASSWORD, register_and_verify
from tests.test_auth_password import sign_in

TEST_ISSUER = "https://accounts.example-provider.test"
TEST_CLIENT_ID = "test-client-id.apps.example"


@pytest.fixture(scope="session")
def signing_key():
    """A real RSA keypair, so signatures are genuinely verified."""
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture
def fake_provider(signing_key, monkeypatch):
    """A provider whose JWKS is served from the in-process keypair."""
    provider = OAuthProvider(
        key="google",
        display_name="Google",
        authorize_url=f"{TEST_ISSUER}/authorize",
        token_url=f"{TEST_ISSUER}/token",
        jwks_url=f"{TEST_ISSUER}/jwks",
        issuers=(TEST_ISSUER,),
        scopes=("openid", "email", "profile"),
        client_id=TEST_CLIENT_ID,
        client_secret="test-client-secret",
    )
    monkeypatch.setattr(oauth_providers, "get_providers", lambda: {"google": provider})
    monkeypatch.setattr(oauth_providers, "get_provider", lambda key: {"google": provider}.get(key))

    class LocalKey:
        key = signing_key.public_key()

    class LocalJWKClient:
        def __init__(self, *args, **kwargs):
            pass

        def get_signing_key_from_jwt(self, token):
            return LocalKey()

    monkeypatch.setattr(oauth_client, "PyJWKClient", LocalJWKClient)
    oauth_client.reset_jwk_clients()
    return provider


def make_id_token(signing_key, nonce, **overrides):
    now = int(time.time())
    claims = {
        "iss": TEST_ISSUER,
        "aud": TEST_CLIENT_ID,
        "sub": "provider-user-0001",
        "email": "social@example.com",
        "email_verified": True,
        "name": "Social User",
        "nonce": nonce,
        "iat": now,
        "exp": now + 300,
    }
    claims.update(overrides)
    return jwt.encode(claims, signing_key, algorithm="RS256")


# ---------------------------------------------------------------------------
# ID token verification
# ---------------------------------------------------------------------------


def test_a_correctly_signed_token_verifies(fake_provider, signing_key):
    token = make_id_token(signing_key, nonce="abc")
    claims = verify_id_token(fake_provider, token, nonce="abc")
    assert claims["sub"] == "provider-user-0001"


def test_a_token_signed_by_the_wrong_key_is_rejected(fake_provider):
    """The whole point of JWKS verification."""
    attacker_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    token = make_id_token(attacker_key, nonce="abc")
    with pytest.raises(OAuthError, match="verify"):
        verify_id_token(fake_provider, token, nonce="abc")


def test_an_unsigned_token_is_rejected(fake_provider, signing_key):
    """`alg: none` is the textbook JWT bypass."""
    token = jwt.encode(
        {"iss": TEST_ISSUER, "aud": TEST_CLIENT_ID, "sub": "x", "nonce": "abc",
         "iat": int(time.time()), "exp": int(time.time()) + 300},
        key="",
        algorithm="none",
    )
    with pytest.raises(OAuthError):
        verify_id_token(fake_provider, token, nonce="abc")


def test_a_token_for_another_audience_is_rejected(fake_provider, signing_key):
    """A token minted for a different application must not sign anyone in here."""
    token = make_id_token(signing_key, nonce="abc", aud="someone-elses-client-id")
    with pytest.raises(OAuthError):
        verify_id_token(fake_provider, token, nonce="abc")


def test_a_token_from_another_issuer_is_rejected(fake_provider, signing_key):
    token = make_id_token(signing_key, nonce="abc", iss="https://evil.example")
    with pytest.raises(OAuthError):
        verify_id_token(fake_provider, token, nonce="abc")


def test_an_expired_token_is_rejected(fake_provider, signing_key):
    now = int(time.time())
    token = make_id_token(signing_key, nonce="abc", iat=now - 7200, exp=now - 3600)
    with pytest.raises(OAuthError):
        verify_id_token(fake_provider, token, nonce="abc")


def test_a_token_with_the_wrong_nonce_is_rejected(fake_provider, signing_key):
    """Without this an ID token captured from one browser replays into another."""
    token = make_id_token(signing_key, nonce="issued-for-another-browser")
    with pytest.raises(OAuthError):
        verify_id_token(fake_provider, token, nonce="this-browsers-nonce")


def test_a_token_with_no_subject_is_rejected(fake_provider, signing_key):
    token = make_id_token(signing_key, nonce="abc", sub="")
    with pytest.raises(OAuthError):
        verify_id_token(fake_provider, token, nonce="abc")


# ---------------------------------------------------------------------------
# Flow state
# ---------------------------------------------------------------------------


def test_a_flow_is_single_use(db_session, fake_provider):
    flow = oauth_service.start_flow(db_session, fake_provider, "/")
    oauth_service.consume_flow(db_session, flow.flow_key, "google", flow.state)

    with pytest.raises(auth_service.AuthError):
        oauth_service.consume_flow(db_session, flow.flow_key, "google", flow.state)


def test_a_flow_with_a_mismatched_state_is_refused(db_session, fake_provider):
    """The state check is what stops a cross-site forced sign-in."""
    flow = oauth_service.start_flow(db_session, fake_provider, "/")
    with pytest.raises(auth_service.AuthError):
        oauth_service.consume_flow(db_session, flow.flow_key, "google", "attacker-chosen-state")


def test_a_flow_from_another_provider_is_refused(db_session, fake_provider):
    flow = oauth_service.start_flow(db_session, fake_provider, "/")
    with pytest.raises(auth_service.AuthError):
        oauth_service.consume_flow(db_session, flow.flow_key, "apple", flow.state)


def test_an_expired_flow_is_refused(db_session, fake_provider):
    flow = oauth_service.start_flow(db_session, fake_provider, "/")
    row = db_session.scalar(select(OAuthFlow))
    row.created_at = utcnow() - timedelta(hours=2)
    row.expires_at = utcnow() - timedelta(hours=1)
    db_session.flush()

    with pytest.raises(auth_service.AuthError):
        oauth_service.consume_flow(db_session, flow.flow_key, "google", flow.state)


def test_the_flow_key_is_not_stored(db_session, fake_provider):
    flow = oauth_service.start_flow(db_session, fake_provider, "/")
    row = db_session.scalar(select(OAuthFlow))
    assert len(bytes(row.flow_key_hash)) == 32
    assert flow.flow_key.encode() not in bytes(row.flow_key_hash)


def test_an_off_site_redirect_target_is_reduced_before_storage(db_session, fake_provider):
    from skincaresync.auth.cookies import safe_redirect_path

    oauth_service.start_flow(db_session, fake_provider, safe_redirect_path("https://evil.example"))
    assert db_session.scalar(select(OAuthFlow)).redirect_to == "/"


# ---------------------------------------------------------------------------
# Account resolution and linking
# ---------------------------------------------------------------------------


def identity(**overrides):
    from skincaresync.auth.oauth.client import OAuthIdentity

    fields = {
        "provider": "google",
        "subject": "provider-user-0001",
        "email": "social@example.com",
        "email_verified": True,
        "display_name": "Social User",
    }
    fields.update(overrides)
    return OAuthIdentity(**fields)


def test_a_new_provider_account_creates_a_user(db_session):
    context = auth_service.RequestContext()
    user = oauth_service.resolve_sign_in(db_session, identity(), context)

    assert user.email == "social@example.com"
    assert user.is_email_verified
    # No password, and no placeholder standing in for one.
    assert user.password_hash is None
    assert user.role == "user"


def test_signing_in_again_reuses_the_same_account(db_session):
    context = auth_service.RequestContext()
    first = oauth_service.resolve_sign_in(db_session, identity(), context)
    second = oauth_service.resolve_sign_in(db_session, identity(), context)

    assert first.user_id == second.user_id
    assert len(db_session.scalars(select(User)).all()) == 1


def test_identity_is_keyed_on_subject_not_email(db_session):
    """A provider account whose email later changes is still the same account."""
    context = auth_service.RequestContext()
    original = oauth_service.resolve_sign_in(db_session, identity(), context)
    moved = oauth_service.resolve_sign_in(
        db_session, identity(email="renamed@example.com"), context
    )

    assert original.user_id == moved.user_id


def test_a_verified_provider_email_links_to_an_existing_password_account(api_client, db_session):
    """The provider vouching for mailbox control meets the same bar as our own
    verification link, so this is safe to link automatically."""
    register_and_verify(api_client, "social@example.com")
    existing = db_session.scalar(select(User).where(User.email_normalized == "social@example.com"))

    linked = oauth_service.resolve_sign_in(
        db_session, identity(), auth_service.RequestContext()
    )

    assert linked.user_id == existing.user_id
    assert len(db_session.scalars(select(User)).all()) == 1
    assert db_session.scalar(select(UserIdentity)).user_id == existing.user_id


def test_an_unverified_provider_email_is_refused_not_linked(api_client, db_session):
    """Linking here would hand the account to whoever can set an unverified
    address at the provider."""
    register_and_verify(api_client, "social@example.com")

    with pytest.raises(auth_service.AuthError) as excinfo:
        oauth_service.resolve_sign_in(
            db_session, identity(email_verified=False), auth_service.RequestContext()
        )

    assert excinfo.value.code == "email_unverified"
    # And no second account was quietly created either.
    assert len(db_session.scalars(select(User)).all()) == 1
    assert db_session.scalars(select(UserIdentity)).all() == []


def test_one_provider_account_cannot_be_claimed_by_two_users(api_client, db_session):
    context = auth_service.RequestContext()
    first = oauth_service.resolve_sign_in(db_session, identity(), context)

    register_and_verify(api_client, "other@example.com")
    other = db_session.scalar(select(User).where(User.email_normalized == "other@example.com"))

    with pytest.raises(auth_service.AuthError) as excinfo:
        oauth_service.link_to_current_user(db_session, other, identity(), context)

    assert excinfo.value.code == "already_linked"
    assert db_session.scalar(select(UserIdentity)).user_id == first.user_id


def test_a_provider_that_shares_no_email_cannot_create_an_account(db_session):
    with pytest.raises(auth_service.AuthError) as excinfo:
        oauth_service.resolve_sign_in(
            db_session, identity(email=None), auth_service.RequestContext()
        )
    assert excinfo.value.code == "no_email"


def test_a_deactivated_account_cannot_be_signed_into_through_a_provider(db_session):
    context = auth_service.RequestContext()
    user = oauth_service.resolve_sign_in(db_session, identity(), context)
    auth_service.deactivate_account(db_session, user, context)

    with pytest.raises(auth_service.AuthError) as excinfo:
        oauth_service.resolve_sign_in(db_session, identity(), context)
    assert excinfo.value.code == "account_unavailable"


# ---------------------------------------------------------------------------
# Passwordless accounts
# ---------------------------------------------------------------------------


def test_a_provider_only_account_cannot_sign_in_with_a_password(db_session, api_client):
    oauth_service.resolve_sign_in(db_session, identity(), auth_service.RequestContext())

    response = api_client.post(
        "/api/auth/login", json={"email": "social@example.com", "password": PASSWORD}
    )
    # Indistinguishable from any other failure: this must not become an oracle
    # for which accounts use a provider.
    assert response.status_code == 401


def test_a_provider_only_account_can_set_a_first_password(db_session, api_client, mailbox):
    user = oauth_service.resolve_sign_in(db_session, identity(), auth_service.RequestContext())
    assert not user.has_password

    auth_service.change_password(
        db_session, user, current_password="", new_password="a brand new passphrase",
        context=auth_service.RequestContext(),
    )

    db_session.refresh(user)
    assert user.has_password
    assert api_client.post(
        "/api/auth/login",
        json={"email": "social@example.com", "password": "a brand new passphrase"},
    ).status_code == 200


def test_unlinking_the_only_sign_in_method_is_refused(db_session):
    context = auth_service.RequestContext()
    user = oauth_service.resolve_sign_in(db_session, identity(), context)

    with pytest.raises(auth_service.AuthError) as excinfo:
        oauth_service.unlink(db_session, user, "google", context)

    assert excinfo.value.code == "last_sign_in_method"
    assert oauth_service.list_identities(db_session, user)


def test_unlinking_is_allowed_once_a_password_exists(db_session):
    context = auth_service.RequestContext()
    user = oauth_service.resolve_sign_in(db_session, identity(), context)
    auth_service.change_password(
        db_session, user, "", "a brand new passphrase", context
    )

    oauth_service.unlink(db_session, user, "google", context)
    assert oauth_service.list_identities(db_session, user) == []


def test_deleting_an_account_removes_its_provider_links(db_session):
    """Otherwise the linked Google account signs straight back into the shell,
    because identities are keyed on `sub` rather than the scrambled email."""
    context = auth_service.RequestContext()
    user = oauth_service.resolve_sign_in(db_session, identity(), context)
    auth_service.delete_account(db_session, user, context)

    assert db_session.scalars(select(UserIdentity)).all() == []
    # And the provider account can now start a fresh one.
    fresh = oauth_service.resolve_sign_in(db_session, identity(), context)
    assert fresh.user_id != user.user_id


# ---------------------------------------------------------------------------
# HTTP surface
# ---------------------------------------------------------------------------


def test_unconfigured_providers_are_not_advertised(api_client, monkeypatch):
    monkeypatch.setattr(oauth_providers, "get_providers", dict)
    assert api_client.get("/api/auth/oauth/providers").json() == []


def test_configured_providers_are_advertised(api_client, fake_provider):
    listed = api_client.get("/api/auth/oauth/providers").json()
    assert [p["key"] for p in listed] == ["google"]


def test_starting_an_unknown_provider_is_a_404(api_client):
    assert api_client.get(
        "/api/auth/oauth/myspace/start", follow_redirects=False
    ).status_code == 404


def test_start_redirects_to_the_provider_with_state_nonce_and_pkce(api_client, fake_provider):
    response = api_client.get("/api/auth/oauth/google/start", follow_redirects=False)

    assert response.status_code == 303
    location = response.headers["location"]
    assert location.startswith(f"{TEST_ISSUER}/authorize")
    for required in ("state=", "nonce=", "code_challenge=", "code_challenge_method=S256"):
        assert required in location
    # The flow cookie is not readable by script.
    cookie = next(h for h in response.headers.get_list("set-cookie") if "skincaresync_oauth" in h)
    assert "HttpOnly" in cookie


def test_start_does_not_accept_an_off_site_next(api_client, fake_provider, db_session):
    api_client.get(
        "/api/auth/oauth/google/start?next=https://evil.example", follow_redirects=False
    )
    assert db_session.scalar(select(OAuthFlow)).redirect_to == "/"


def test_the_callback_url_points_at_the_api_not_the_frontend(fake_provider, auth_env):
    """The callback route lives on the API. Building it from APP_BASE_URL sends
    the provider to the frontend origin, where nothing answers -- and the failure
    only shows up after the user has already approved at the provider."""
    from skincaresync.auth.oauth.routes import _callback_url

    callback = _callback_url("google")
    assert callback.startswith(auth_env.api_base_url)
    assert callback == f"{auth_env.api_base_url}/api/auth/oauth/google/callback"
    if auth_env.api_base_url != auth_env.app_base_url:
        assert not callback.startswith(auth_env.app_base_url)


def test_production_requires_https_on_both_base_urls(monkeypatch):
    from skincaresync import config

    monkeypatch.setenv("SKINCARESYNC_ENV", "production")
    monkeypatch.setenv("APP_BASE_URL", "https://app.example.com")
    monkeypatch.setenv("API_BASE_URL", "http://api.example.com")  # not https
    monkeypatch.setenv("SESSION_COOKIE_SECURE", "true")
    monkeypatch.setenv("EMAIL_PROVIDER", "smtp")
    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    config.reset_settings_cache()

    with pytest.raises(config.ConfigError, match="API_BASE_URL"):
        config.get_settings()
    config.reset_settings_cache()


def test_a_callback_without_a_flow_cookie_fails_closed(api_client, fake_provider):
    response = api_client.get(
        "/api/auth/oauth/google/callback?code=abc&state=xyz", follow_redirects=False
    )
    assert response.status_code == 303
    assert "error=" in response.headers["location"]


def test_a_cancelled_sign_in_returns_to_the_sign_in_page(api_client, fake_provider):
    response = api_client.get(
        "/api/auth/oauth/google/callback?error=access_denied", follow_redirects=False
    )
    assert response.status_code == 303
    assert "error=cancelled" in response.headers["location"]


def test_linking_requires_a_session(api_client, fake_provider):
    assert api_client.get(
        "/api/auth/oauth/google/link", follow_redirects=False
    ).status_code == 401


def test_identities_are_listed_for_the_signed_in_user(api_client, db_session):
    register_and_verify(api_client, "social@example.com")
    sign_in(api_client, "social@example.com")
    oauth_service.resolve_sign_in(db_session, identity(), auth_service.RequestContext())

    listed = api_client.get("/api/auth/identities").json()
    assert [item["provider"] for item in listed] == ["google"]
    # Nothing token-shaped is exposed.
    assert "subject" not in listed[0]


def test_identity_endpoints_require_a_session(api_client):
    assert api_client.get("/api/auth/identities").status_code == 401
    assert api_client.delete("/api/auth/identities/google").status_code == 401


def test_unlinking_requires_a_csrf_token(api_client, db_session):
    register_and_verify(api_client, "social@example.com")
    sign_in(api_client, "social@example.com")
    oauth_service.resolve_sign_in(db_session, identity(), auth_service.RequestContext())

    assert api_client.delete("/api/auth/identities/google").status_code == 403


def test_the_account_response_reports_whether_a_password_is_set(api_client, db_session):
    register_and_verify(api_client, "social@example.com")
    sign_in(api_client, "social@example.com")
    assert api_client.get("/api/auth/me").json()["has_password"] is True
