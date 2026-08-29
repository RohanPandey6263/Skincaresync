"""Request and response models for the authentication API.

All validation and normalisation happens here, on the server. The browser
performs the same checks for immediate feedback, but nothing depends on it.

No response model carries a password, hash, token or session identifier.
"""

from __future__ import annotations

import re
import unicodedata
from datetime import datetime

from pydantic import BaseModel, EmailStr, Field, field_validator

from .security import MAX_PASSWORD_LENGTH, MIN_PASSWORD_LENGTH

MAX_EMAIL_LENGTH = 254  # RFC 5321 limit on a forward path
MAX_DISPLAY_NAME_LENGTH = 80

# Rejected outright because they are the passwords guessed first, regardless of
# length. This is a floor, not a policy engine; strength meters belong in the UI.
_COMMON_PASSWORDS = frozenset(
    {
        "password", "password1", "password123", "passw0rd", "letmein",
        "qwertyuiop", "12345678", "123456789", "1234567890", "iloveyou",
        "adminadmin", "welcome123", "changeme", "skincaresync", "administrator",
    }
)


def _normalize_unicode(value: str) -> str:
    """NFKC-normalise and strip.

    Without this, a display name or password could contain confusable or
    zero-width characters that compare unequal to what the user believes they
    typed. NFKC is also what Postgres-side comparisons assume.
    """
    return unicodedata.normalize("NFKC", value).strip()


class PasswordField(BaseModel):
    """Shared password validation."""

    password: str = Field(min_length=MIN_PASSWORD_LENGTH, max_length=MAX_PASSWORD_LENGTH)

    @field_validator("password")
    @classmethod
    def check_password(cls, value: str) -> str:
        # Deliberately not stripped: leading and trailing spaces are legitimate
        # password characters and a password manager may well generate them.
        normalized = unicodedata.normalize("NFKC", value)
        if len(normalized) < MIN_PASSWORD_LENGTH:
            raise ValueError(f"Password must be at least {MIN_PASSWORD_LENGTH} characters.")
        if normalized.lower() in _COMMON_PASSWORDS:
            raise ValueError("Choose a less common password.")
        if re.fullmatch(r"(.)\1*", normalized):
            raise ValueError("Choose a less predictable password.")
        return normalized


class EmailField(BaseModel):
    email: EmailStr = Field(max_length=MAX_EMAIL_LENGTH)

    @field_validator("email")
    @classmethod
    def normalize(cls, value: str) -> str:
        # Only the domain is case-insensitive per RFC, but every mainstream
        # provider treats the local part that way too, and the database enforces
        # uniqueness on the lowercased value. Lowercasing here keeps the API,
        # the ORM and the unique index in agreement.
        return value.strip().lower()


class RegisterRequest(EmailField, PasswordField):
    display_name: str | None = Field(default=None, max_length=MAX_DISPLAY_NAME_LENGTH)

    @field_validator("display_name")
    @classmethod
    def clean_display_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = _normalize_unicode(value)
        if not cleaned:
            return None
        # Control characters have no place in a name and can corrupt log lines
        # and email headers.
        if any(unicodedata.category(ch).startswith("C") for ch in cleaned):
            raise ValueError("Name contains characters that are not allowed.")
        return cleaned


class LoginRequest(EmailField):
    # Not length-validated: an existing account may predate the current minimum,
    # and rejecting a short password here would reveal the policy boundary
    # rather than simply failing to authenticate.
    password: str = Field(min_length=1, max_length=MAX_PASSWORD_LENGTH)
    next: str | None = Field(default=None, max_length=512)


class ForgotPasswordRequest(EmailField):
    pass


class ResendVerificationRequest(EmailField):
    pass


class TokenRequest(BaseModel):
    token: str = Field(min_length=16, max_length=512)


class ResetPasswordRequest(PasswordField):
    token: str = Field(min_length=16, max_length=512)


class ChangePasswordRequest(PasswordField):
    current_password: str = Field(min_length=1, max_length=MAX_PASSWORD_LENGTH)


class DeleteAccountRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=MAX_PASSWORD_LENGTH)
    # Typed confirmation, so a mis-click cannot erase an account.
    confirm: str = Field(min_length=1, max_length=32)

    @field_validator("confirm")
    @classmethod
    def must_confirm(cls, value: str) -> str:
        if value.strip().upper() != "DELETE":
            raise ValueError("Type DELETE to confirm.")
        return value.strip().upper()


class UpdateRoleRequest(BaseModel):
    role: str

    @field_validator("role")
    @classmethod
    def known_role(cls, value: str) -> str:
        if value not in {"user", "admin"}:
            raise ValueError("Role must be 'user' or 'admin'.")
        return value


# --- responses --------------------------------------------------------------


class UserResponse(BaseModel):
    user_id: int
    email: str
    display_name: str | None
    role: str
    status: str
    email_verified: bool
    # Lets the UI offer "set a password" instead of "change password" for an
    # account created through a provider. Not a secret: the user already knows.
    has_password: bool
    created_at: datetime


class LinkedIdentityResponse(BaseModel):
    provider: str
    email: str | None
    created_at: datetime
    last_login_at: datetime | None


class SessionResponse(BaseModel):
    session_id: int
    created_at: datetime
    last_seen_at: datetime
    ip_address: str | None
    user_agent: str | None
    current: bool


class AuthEventResponse(BaseModel):
    event_type: str
    created_at: datetime
    ip_address: str | None
    detail: dict


class MessageResponse(BaseModel):
    message: str
    # Populated only when AUTH_DEV_ECHO_TOKENS is on, which production forbids.
    # Lets local work and tests complete email flows without a mailbox.
    dev_token: str | None = None


class LoginResponse(BaseModel):
    user: UserResponse
    csrf_token: str
    redirect_to: str
