#!/usr/bin/env bash
# Regenerates migrations/install.sql: every migration, in order, in one file.
#
# The chain is linear and each step is idempotent, so concatenating them is
# equivalent to running them one at a time. Run this after adding a migration
# — CI has no way to notice that install.sql went stale.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/migrations/install.sql"

# 000 creates and seeds `ingredients`; aidatabase.sql is migration 001 and adds
# the tables whose foreign keys point at it, so 000 must come first and cannot
# just sort into place. The rest sort by their number. Down migrations are
# rollbacks and are never part of an install.
# (No mapfile here: macOS still ships bash 3.2.)
files=("$root/migrations/000_ingredients.sql" "$root/aidatabase.sql")
while IFS= read -r f; do
    files+=("$f")
done < <(find "$root/migrations" -maxdepth 1 -name '0*.sql' \
    ! -name '*.down.sql' ! -name '000_*.sql' | sort)

{
    cat <<'HEADER'
-- SkincareSync: the whole migration chain in one file.
--
-- GENERATED — do not edit. Run scripts/build_install_sql.sh to rebuild it from
-- aidatabase.sql and migrations/0*.sql.
--
-- Every step is idempotent, so this is safe to re-run against a database that
-- is already partly or fully migrated. Each migration keeps its own
-- BEGIN/COMMIT, so a failure rolls back that step, not the ones before it.
--
-- Self-contained: migration 000 creates and seeds `ingredients`, so this runs
-- against a completely empty database as well as one that is already partly
-- or fully migrated.
--
--     psql -d "$PGDATABASE" -f migrations/install.sql
HEADER
    printf -- '--\n-- Contents, in order:\n'
    for f in "${files[@]}"; do printf -- '--   %s\n' "${f#"$root"/}"; done
    printf -- '\n\\set ON_ERROR_STOP on\n'

    for f in "${files[@]}"; do
        printf '\n\n-- %s\n-- %s\n-- %s\n\n' \
            "$(printf '=%.0s' {1..70})" "${f#"$root"/}" "$(printf '=%.0s' {1..70})"
        cat "$f"
    done
} > "$out"

echo "wrote ${out#"$root"/} ($(wc -l < "$out" | tr -d ' ') lines from ${#files[@]} files)"
