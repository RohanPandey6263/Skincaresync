"""Who the caller is, when there is a proxy in the way.

`X-Forwarded-For` is a list that grows left to right: each proxy appends the
peer it heard from. So the leftmost entry is whatever the *original client*
sent -- attacker-controlled -- and the rightmost entries are the ones added by
infrastructure you actually control.

Two deployments, two correct answers:

* **nginx from `deploy/nginx.conf`** sets the header with `$remote_addr`,
  overwriting anything the client sent. The list is then exactly one entry long
  and trustworthy, so the leftmost is right. `TRUST_PROXY=true` alone.
* **Behind a platform edge (Railway, Render, Fly, a load balancer)** the
  leftmost entry is still forgeable. Set `TRUST_PROXY_HOPS` to the number of
  proxies between the client and this app and the client is read that many
  positions from the right: 1 if the API faces the edge directly, 2 for the
  Railway layout where nginx sits behind the edge with BEHIND_EDGE_PROXY=true
  (it appends the edge's address). Counting from the right is correct whether
  the edge itself appends to the header or replaces it.

Getting this wrong is not cosmetic. Trusting a forgeable leftmost entry lets a
caller rotate past every rate limit at will and write false addresses into the
auth audit log; trusting none of it behind a proxy collapses every user onto the
proxy's own address, so one noisy client rate-limits everybody.
"""

from __future__ import annotations

import os


def trust_proxy() -> bool:
    """Whether `X-Forwarded-For` is consulted at all."""
    return os.getenv("TRUST_PROXY", "").strip().lower() in {"1", "true", "yes", "on"}


def trusted_hops() -> int:
    """How many proxies sit in front. 0 means "the header is already rewritten"."""
    try:
        return max(0, int(os.getenv("TRUST_PROXY_HOPS", "0")))
    except ValueError:
        return 0


def forwarded_for(header: str, hops: int | None = None) -> str | None:
    """The client address from an `X-Forwarded-For` value, or None.

    With `hops` 0 the leftmost entry is returned, which is correct only when the
    proxy overwrites the header. With `hops` N the Nth entry from the right is
    returned -- the address the outermost trusted proxy observed.
    """
    entries = [part.strip() for part in header.split(",") if part.strip()]
    if not entries:
        return None
    if hops is None:
        hops = trusted_hops()
    if hops <= 0:
        return entries[0]
    # Each hop consumes one entry from the right. A list shorter than the
    # configured depth means fewer proxies ran than expected, so the leftmost
    # entry is the earliest address anyone actually observed.
    index = len(entries) - hops
    return entries[index] if index >= 0 else entries[0]
