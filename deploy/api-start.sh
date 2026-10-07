#!/bin/sh
# Starts the API. The image's CMD; kept as a script so the bind logic can be
# read rather than escaped inside a JSON string.
set -eu

# Which address to listen on:
#   0.0.0.0  (default) IPv4. What compose needs, and safe on any host -- even
#            one with IPv6 switched off, where binding an IPv6 socket fails.
#   dual     IPv4 and IPv6 together. For a private network that may hand the
#            proxy either kind of address (Railway's does).
#   ::       IPv6 only. asyncio marks a "::" socket IPv6-only, so IPv4
#            connections are refused; prefer `dual` unless that is intended.
case "${BIND_HOST:-0.0.0.0}" in
    dual)
        # An empty host makes asyncio open one socket per address family.
        host=""
        if [ "${WEB_CONCURRENCY:-1}" -gt 1 ]; then
            # uvicorn's multi-worker path pre-binds a single IPv4 socket for an
            # empty host, so `dual` silently degrades to IPv4 there.
            echo "BIND_HOST=dual with WEB_CONCURRENCY>1 listens on IPv4 only" >&2
        fi
        ;;
    *) host="${BIND_HOST:-0.0.0.0}" ;;
esac

exec uvicorn skincaresync.api:app \
    --host "$host" \
    --port "${PORT:-8000}" \
    --workers "${WEB_CONCURRENCY:-1}"
