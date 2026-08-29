#!/usr/bin/env python3
"""Promote or demote an account.

The migration creates no seed administrator and no default credentials, because
a hardcoded account is a backdoor that survives into production. The first admin
is made deliberately, by an operator with database access, from an account that
already registered through the normal flow.

Usage
-----
    python scripts/grant_admin.py alice@example.com
    python scripts/grant_admin.py alice@example.com --revoke
    python scripts/grant_admin.py --list
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select  # noqa: E402

from skincaresync.auth.db import session_scope  # noqa: E402
from skincaresync.auth.models import AuthEvent, User, UserRole  # noqa: E402
from skincaresync.auth.service import normalize_email, revoke_all_sessions  # noqa: E402


def list_admins() -> int:
    with session_scope() as db:
        admins = db.scalars(
            select(User).where(User.role == UserRole.ADMIN.value).order_by(User.email)
        ).all()
        if not admins:
            print("No administrators. Promote one with:")
            print("  python scripts/grant_admin.py you@example.com")
            return 0
        print(f"{len(admins)} administrator(s):")
        for user in admins:
            verified = "verified" if user.email_verified_at else "UNVERIFIED"
            print(f"  {user.email}  ({user.status}, {verified})")
    return 0


def set_role(email: str, revoke: bool) -> int:
    role = UserRole.USER if revoke else UserRole.ADMIN
    with session_scope() as db:
        user = db.scalar(select(User).where(User.email_normalized == normalize_email(email)))
        if user is None:
            print(f"No account for {email!r}. Register through the app first.", file=sys.stderr)
            return 1
        if user.status != "active":
            print(f"Account is {user.status}; refusing to change its role.", file=sys.stderr)
            return 1
        if user.role == role.value:
            print(f"{user.email} is already {role.value}.")
            return 0

        if revoke:
            remaining = db.scalar(
                select(User).where(
                    User.role == UserRole.ADMIN.value,
                    User.user_id != user.user_id,
                    User.status == "active",
                )
            )
            if remaining is None:
                print("Refusing to remove the last administrator.", file=sys.stderr)
                return 1

        user.role = role.value
        # A privilege change must not leave sessions running under the old role.
        revoked = revoke_all_sessions(db, user, reason="role_changed_by_operator")
        db.add(
            AuthEvent(
                user_id=user.user_id,
                event_type="role.changed",
                detail={"role": role.value, "actor": "cli"},
            )
        )
        print(f"{user.email} is now {role.value}. Signed out {revoked} session(s).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("email", nargs="?", help="Account to change")
    parser.add_argument("--revoke", action="store_true", help="Demote to a normal user")
    parser.add_argument("--list", action="store_true", help="List current administrators")
    args = parser.parse_args()

    if args.list:
        return list_admins()
    if not args.email:
        parser.error("provide an email address, or --list")
    return set_role(args.email, args.revoke)


if __name__ == "__main__":
    raise SystemExit(main())
