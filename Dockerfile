# SkincareSync API.
#
# Runtime only: the ingredient importers in scripts/ are one-off jobs run
# against the database, not part of the serving image.

FROM python:3.13-slim AS base

# Every dependency ships a manylinux wheel (psycopg2-binary, argon2-cffi,
# cryptography included), so no compiler is needed and none is installed --
# a build toolchain in a production image is attack surface that never runs.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Dependencies first: this layer is rebuilt only when the requirements change,
# not on every source edit.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY skincaresync/ ./skincaresync/
COPY scripts/ ./scripts/
COPY migrations/ ./migrations/
COPY aidatabase.sql ./

# Unprivileged, and owning nothing it runs: the image is read-only in practice.
# The one exception is data/, where import_ingredient_catalog.py caches the
# ~22,000-entry Open Beauty Facts taxonomy between runs -- without it the
# importer cannot create its own cache directory under root-owned /app.
RUN useradd --system --create-home --uid 10001 skincaresync \
    && mkdir -p /app/data \
    && chown skincaresync:skincaresync /app/data
USER skincaresync

# The port is a runtime setting, not a build-time one: compose publishes 8000,
# while Railway, Render and Fly inject their own $PORT and route to that. EXPOSE
# is documentation only and names the default.
ENV PORT=8000
EXPOSE 8000

# The rate limiter counts in process memory, so each worker gets its own budget
# and the effective limit is WEB_CONCURRENCY x the configured value. One worker
# keeps the limits exact; raise it only after moving the counters to Redis
# (see skincaresync/ratelimit.py).
ENV WEB_CONCURRENCY=1

# Compose and most platforms supply their own health check; this one makes a
# bare `docker run` self-describing too.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import os,urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8000')+'/api/health', timeout=4).status == 200 else 1)"

# No --proxy-headers: the app reads X-Forwarded-For itself, gated on
# TRUST_PROXY (skincaresync/ratelimit.py and auth/dependencies.py), and both
# take the FIRST entry. Letting uvicorn rewrite request.client from the same
# header as well would apply that trust decision twice, in two places, with
# only one of them configurable.
CMD ["sh", "-c", "exec uvicorn skincaresync.api:app --host 0.0.0.0 --port ${PORT:-8000} --workers ${WEB_CONCURRENCY}"]
