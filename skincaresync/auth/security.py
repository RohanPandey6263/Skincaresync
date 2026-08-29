"""Password hashing, token generation, and constant-time comparison.

No cryptography is implemented here. Passwords go through argon2-cffi, the
reference Argon2 binding, at its Argon2id defaults. Tokens come from `secrets`,
the standard library's CSPRNG. This module only wires those together.

Two different one-way functions are used, on purpose:

* Passwords are low-entropy and human-chosen, so they need a slow, memory-hard
  KDF. That is Argon2id.
* Session, verification and reset tokens are 256-bit values from a CSPRNG. They
  are not guessable, so the expensive KDF buys nothing; a single SHA-256 is the
  standard choice and keeps lookup a single indexed query. What matters is that
  the plaintext token is never stored, so a database disclosure cannot be
  replayed.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets

from argon2 import PasswordHasher
from argon2 import exceptions as argon2_exceptions

# Every way argon2-cffi can reject a stored hash. `Argon2Error` is the base of
# the verification failures; `InvalidHash` subclasses ValueError rather than
# Argon2Error, so it is not covered by the former and must be listed.
# `InvalidHashError` is an alias kept for older releases.
_HASH_ERRORS: tuple[type[Exception], ...] = tuple(
    {
        argon2_exceptions.Argon2Error,
        argon2_exceptions.InvalidHash,
        getattr(argon2_exceptions, "InvalidHashError", argon2_exceptions.InvalidHash),
    }
)

# argon2-cffi's defaults are Argon2id with sensible cost parameters and are
# revised by its maintainers as hardware moves; tracking them is better than
# freezing numbers here. Kept in one place so a future tuning pass has an
# obvious home.
_hasher = PasswordHasher()

# Long enough that hashing cost cannot be used as a denial-of-service lever,
# short enough to be irrelevant to real users. Argon2 has no low ceiling of its
# own, unlike bcrypt's 72-byte truncation.
MAX_PASSWORD_LENGTH = 1024
MIN_PASSWORD_LENGTH = 12

TOKEN_BYTES = 32  # 256 bits


def hash_password(password: str) -> str:
    """Return an Argon2id hash. The encoded form carries its own parameters."""
    if len(password) > MAX_PASSWORD_LENGTH:
        raise ValueError("password exceeds maximum length")
    return _hasher.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    """Check a password. False on any mismatch, malformed hash, or no hash at all.

    `None` means the account signs in only through a linked provider. That is a
    normal state, so it returns False rather than raising -- but it is checked
    explicitly so a future refactor cannot turn "no password" into "any password".
    """
    if password_hash is None:
        return False
    if len(password) > MAX_PASSWORD_LENGTH:
        return False
    try:
        return _hasher.verify(password_hash, password)
    except _HASH_ERRORS:
        return False


def needs_rehash(password_hash: str | None) -> bool:
    """Whether a stored hash predates the current cost parameters."""
    if password_hash is None:
        return False
    try:
        return _hasher.check_needs_rehash(password_hash)
    except _HASH_ERRORS:
        return True


def dummy_verify() -> None:
    """Burn one Argon2 verification against a throwaway hash.

    Sign-in for an address that does not exist must take about as long as one
    for an address that does, or response timing becomes an account oracle that
    no amount of careful wording in the response body can close.
    """
    try:
        _hasher.verify(_DUMMY_HASH, "not-the-password")
    except _HASH_ERRORS:
        pass


_DUMMY_HASH = _hasher.hash("dummy-password-for-constant-time-comparison")


def generate_token() -> str:
    """A fresh 256-bit URL-safe token, safe to put in an email link."""
    return secrets.token_urlsafe(TOKEN_BYTES)


def hash_token(token: str) -> bytes:
    """The stored form of a token. Never store or log the token itself."""
    return hashlib.sha256(token.encode("utf-8")).digest()


def tokens_equal(left: str, right: str) -> bool:
    """Constant-time comparison, for CSRF tokens and similar."""
    return hmac.compare_digest(left, right)
