"""Application settings, validated once at import.

Authentication depends on a handful of values that are merely inconvenient to
get wrong in development and dangerous to get wrong in production: the base URL
that email links are built from, the cookie flags, and whether email is actually
being delivered. Those are checked here rather than at the point of use, so a
misconfigured production deployment fails at startup instead of silently issuing
links to the wrong host or setting cookies without `Secure`.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from urllib.parse import urlparse


class ConfigError(RuntimeError):
    """Configuration is invalid or unsafe for the selected environment."""


def _load_dotenv() -> None:
    """Read `.env` from the repository root, if one exists.

    `.env.example` documents settings as though a `.env` is picked up, so it has
    to be -- otherwise a developer edits the file, sees nothing change, and has
    no way to tell why. Loaded here rather than only via `uvicorn --env-file` so
    the CLI scripts (`grant_admin.py`, the importers) see the same configuration
    the server does.

    Real environment variables always win: `override=False` means a value
    exported in the shell or injected by a deployment platform is never
    shadowed by a stale file left in the working tree.
    """
    try:
        from dotenv import load_dotenv
    except ImportError:  # pragma: no cover - dotenv ships with uvicorn[standard]
        return

    env_path = Path(__file__).resolve().parents[1] / ".env"
    if env_path.exists():
        load_dotenv(env_path, override=False)


_load_dotenv()


def _flag(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError as exc:
        raise ConfigError(f"{name} must be an integer") from exc


@dataclass(frozen=True)
class Settings:
    environment: str

    # Email links and post-sign-in redirects are built from this, never from the
    # request Host header, which an attacker controls.
    app_base_url: str

    # Where this API is reachable. OAuth callbacks land here, not on the
    # frontend, and the value must match what is registered with the provider
    # exactly. It differs from app_base_url whenever the two are served from
    # separate origins, which is the normal development setup.
    api_base_url: str

    session_cookie_name: str
    csrf_cookie_name: str
    cookie_secure: bool
    cookie_samesite: str
    cookie_domain: str | None

    session_idle_max_age_seconds: int
    session_absolute_max_age_seconds: int
    email_verification_ttl_seconds: int
    password_reset_ttl_seconds: int

    email_provider: str
    email_from: str
    smtp_host: str | None
    smtp_port: int
    smtp_username: str | None
    smtp_password: str | None = field(repr=False, default=None)
    smtp_starttls: bool = True

    # Development-only affordance: echo verification and reset tokens in API
    # responses so tests and local work do not need a mailbox. Forced off in
    # production by _validate, regardless of what the environment says.
    dev_echo_tokens: bool = False

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    def __post_init__(self) -> None:
        _validate(self)


def _validate(settings: Settings) -> None:
    for name, value in (("APP_BASE_URL", settings.app_base_url),
                        ("API_BASE_URL", settings.api_base_url)):
        parsed_url = urlparse(value)
        if parsed_url.scheme not in {"http", "https"} or not parsed_url.netloc:
            raise ConfigError(f"{name} must be an absolute http(s) URL, got {value!r}")
        if value.endswith("/"):
            raise ConfigError(f"{name} must not end with a trailing slash")

    parsed = urlparse(settings.app_base_url)

    if settings.cookie_samesite not in {"lax", "strict", "none"}:
        raise ConfigError("SESSION_COOKIE_SAMESITE must be lax, strict or none")

    # SameSite=None is only honoured on secure cookies; browsers reject it
    # otherwise, which would silently drop the session cookie entirely.
    if settings.cookie_samesite == "none" and not settings.cookie_secure:
        raise ConfigError("SESSION_COOKIE_SAMESITE=none requires SESSION_COOKIE_SECURE=true")

    if not settings.is_production:
        return

    problems = []
    if parsed.scheme != "https":
        problems.append("APP_BASE_URL must use https in production")
    if urlparse(settings.api_base_url).scheme != "https":
        problems.append("API_BASE_URL must use https in production")
    if not settings.cookie_secure:
        problems.append("SESSION_COOKIE_SECURE must be true in production")
    if settings.dev_echo_tokens:
        problems.append("AUTH_DEV_ECHO_TOKENS must not be enabled in production")
    if settings.email_provider == "console":
        problems.append(
            "EMAIL_PROVIDER=console does not deliver mail; set EMAIL_PROVIDER=smtp "
            "in production so verification and reset messages reach users"
        )
    if settings.email_provider == "smtp" and not settings.smtp_host:
        problems.append("SMTP_HOST is required when EMAIL_PROVIDER=smtp")
    if problems:
        raise ConfigError("Unsafe production configuration:\n  - " + "\n  - ".join(problems))


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    environment = os.getenv("SKINCARESYNC_ENV", "development").strip().lower()
    is_production = environment == "production"

    return Settings(
        environment=environment,
        app_base_url=os.getenv("APP_BASE_URL", "http://localhost:5173").rstrip("/") or "/",
        api_base_url=os.getenv("API_BASE_URL", "http://localhost:8000").rstrip("/") or "/",
        session_cookie_name=os.getenv("SESSION_COOKIE_NAME", "skincaresync_session"),
        csrf_cookie_name=os.getenv("CSRF_COOKIE_NAME", "skincaresync_csrf"),
        # Secure defaults to on in production and off locally, where the dev
        # server is plain http and a Secure cookie would never be stored.
        cookie_secure=_flag("SESSION_COOKIE_SECURE", default=is_production),
        cookie_samesite=os.getenv("SESSION_COOKIE_SAMESITE", "lax").strip().lower(),
        cookie_domain=os.getenv("SESSION_COOKIE_DOMAIN") or None,
        session_idle_max_age_seconds=_int("SESSION_IDLE_MAX_AGE_SECONDS", 14 * 24 * 3600),
        session_absolute_max_age_seconds=_int("SESSION_ABSOLUTE_MAX_AGE_SECONDS", 90 * 24 * 3600),
        email_verification_ttl_seconds=_int("EMAIL_VERIFICATION_TTL_SECONDS", 24 * 3600),
        password_reset_ttl_seconds=_int("PASSWORD_RESET_TTL_SECONDS", 3600),
        email_provider=os.getenv("EMAIL_PROVIDER", "console").strip().lower(),
        email_from=os.getenv("EMAIL_FROM", "SkincareSync <no-reply@localhost>"),
        smtp_host=os.getenv("SMTP_HOST") or None,
        smtp_port=_int("SMTP_PORT", 587),
        smtp_username=os.getenv("SMTP_USERNAME") or None,
        smtp_password=os.getenv("SMTP_PASSWORD") or None,
        smtp_starttls=_flag("SMTP_STARTTLS", default=True),
        dev_echo_tokens=_flag("AUTH_DEV_ECHO_TOKENS", default=False) and not is_production,
    )


def reset_settings_cache() -> None:
    """Drop the cached settings. Used by tests that vary the environment."""
    get_settings.cache_clear()
