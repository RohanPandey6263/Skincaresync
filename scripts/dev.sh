#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -x "$root/venv/bin/uvicorn" ]]; then
  uvicorn="$root/venv/bin/uvicorn"
elif [[ -x "$root/.venv/bin/uvicorn" ]]; then
  uvicorn="$root/.venv/bin/uvicorn"
else
  echo "Create a venv and run: pip install -r requirements.txt" >&2
  exit 1
fi

if [[ ! -d "$root/frontend/node_modules" ]]; then
  echo "Run npm install in frontend first." >&2
  exit 1
fi

"$uvicorn" skincaresync.api:app --reload --host 127.0.0.1 --port 8000 &
api_pid=$!
(cd "$root/frontend" && npm run dev) &
frontend_pid=$!

cleanup() {
  trap - EXIT INT TERM
  kill "$api_pid" "$frontend_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "API  http://localhost:8000"
echo "App  http://localhost:5173"
wait
