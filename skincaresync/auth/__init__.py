"""Authentication and authorization.

Password hashing is Argon2id via argon2-cffi. Sessions are opaque 256-bit
tokens stored as SHA-256 digests and carried in an HttpOnly cookie, which is
what makes them revocable -- a stateless JWT could not implement "sign out all
devices". The schema is owned by migrations/007_auth.sql; these models mirror it
and never create it.
"""

from .dependencies import (
    AuthenticatedUser,
    enforce_csrf,
    get_optional_user,
    require_admin,
    require_user,
    require_verified_user,
)
from .models import AuthEvent, AuthToken, Base, TokenPurpose, User, UserRole, UserSession, UserStatus
from .service import AuthError

__all__ = [
    "AuthError",
    "AuthEvent",
    "AuthToken",
    "AuthenticatedUser",
    "Base",
    "TokenPurpose",
    "User",
    "UserRole",
    "UserSession",
    "UserStatus",
    "enforce_csrf",
    "get_optional_user",
    "require_admin",
    "require_user",
    "require_verified_user",
]
