"""Social sign-in over OpenID Connect (Google, Apple).

Providers are enabled only when their credentials are configured, so an
unconfigured provider cannot be rendered in the UI or started by a crafted URL.
"""

from .client import OAuthError, OAuthIdentity
from .providers import OAuthProvider, get_provider, get_providers, reset_provider_cache

__all__ = [
    "OAuthError",
    "OAuthIdentity",
    "OAuthProvider",
    "get_provider",
    "get_providers",
    "reset_provider_cache",
]
