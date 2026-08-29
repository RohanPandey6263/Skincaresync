"""In-process sliding-window rate limiting.

The API is unauthenticated, so the only thing standing between a script and the
database is a request budget per client. The expensive endpoints -- routine
analysis, and product lookup, which fans out to two third-party services -- get
tighter budgets than autocomplete.

This counts in process memory. That is correct for a single uvicorn worker and
approximate across several (each worker keeps its own counts, so the effective
limit is the configured one times the worker count). Moving to more than one
machine means moving these counters to Redis; the interface would not change.
"""

from __future__ import annotations

import threading
import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request

# Stop tracking clients that have been idle for longer than this, so the table
# cannot grow without bound under a rotating set of source addresses.
_IDLE_EVICTION_SECONDS = 900


class RateLimiter:
    """Allow `limit` requests per `window_seconds` for each key."""

    def __init__(self, limit: int, window_seconds: float = 60.0):
        self.limit = limit
        self.window = window_seconds
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()
        self._last_sweep = time.monotonic()

    def check(self, key: str) -> float:
        """Return 0.0 if the request is allowed, else seconds until it would be."""
        now = time.monotonic()
        with self._lock:
            self._maybe_sweep(now)
            hits = self._hits[key]
            cutoff = now - self.window
            while hits and hits[0] <= cutoff:
                hits.popleft()

            if len(hits) >= self.limit:
                return max(0.0, hits[0] + self.window - now)

            hits.append(now)
            return 0.0

    def _maybe_sweep(self, now: float) -> None:
        if now - self._last_sweep < _IDLE_EVICTION_SECONDS:
            return
        self._last_sweep = now
        stale = [key for key, hits in self._hits.items() if not hits or hits[-1] <= now - _IDLE_EVICTION_SECONDS]
        for key in stale:
            del self._hits[key]

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


def client_key(request: Request, trust_proxy: bool = False) -> str:
    """Identify the caller.

    `X-Forwarded-For` is only honoured when the deployment explicitly says it sits
    behind a proxy; otherwise any client could spoof the header and sidestep the
    limit entirely.
    """
    if trust_proxy:
        forwarded = request.headers.get("x-forwarded-for", "")
        if forwarded:
            return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def limiter_dependency(limiter: RateLimiter, trust_proxy: bool = False):
    """Build a FastAPI dependency that enforces `limiter`."""

    def enforce(request: Request) -> None:
        retry_after = limiter.check(client_key(request, trust_proxy))
        if retry_after:
            raise HTTPException(
                status_code=429,
                detail="Too many requests. Please slow down and try again shortly.",
                headers={"Retry-After": str(max(1, int(retry_after) + 1))},
            )

    return enforce
