#!/usr/bin/env bash
# Proves an edit made with no signal survives a force quit and lands when signal returns.
#
# Runs against a throwaway copy of the database on its own port, so the backend you actually
# use is never touched. Three processes, because the queue has to outlive the app that made it.
set -euo pipefail

cd "$(dirname "$0")/.."

PORT="${RAVE_VERIFY_PORT:-8975}"
DB=$(mktemp -t rave-verify-XXXX.db)
BIN=$(mktemp -d)/outbox-live-check
PY="${RAVE_PYTHON:-.venv/bin/python}"

cp backend/rave.db "$DB"
RAVE_DB="$DB" "$PY" -m uvicorn --app-dir backend main:app --port "$PORT" --log-level warning &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true; rm -f "$DB"' EXIT

for _ in $(seq 1 40); do
    curl -sf "http://127.0.0.1:$PORT/health" >/dev/null && break
    sleep 0.25
done

swiftc -parse-as-library \
    ios/Rave/Models/RaveModels.swift \
    ios/Rave/Services/LastReadStore.swift \
    ios/Rave/Services/APIClient.swift \
    ios/Rave/Services/Outbox.swift \
    ios/OutboxLiveCheck.swift \
    -o "$BIN"

SUPPORT="$HOME/Library/Application Support"
rm -f "$SUPPORT/Outbox.json" "$SUPPORT/Rave/LastRead/sets.json"

SET_ID=$(curl -s "http://127.0.0.1:$PORT/sets" | \
    "$PY" -c 'import json,sys; print(next(s["id"] for s in json.load(sys.stdin) if "b2b" in s["title"].lower()))')
export RAVE_CHECK_SET_ID="$SET_ID"
echo "editing set $SET_ID"

RAVE_API_BASE_URL="http://127.0.0.1:$PORT" "$BIN" online-first
RAVE_API_BASE_URL="http://127.0.0.1:9"     "$BIN" offline-edit
RAVE_API_BASE_URL="http://127.0.0.1:$PORT" "$BIN" back-online

rm -f "$SUPPORT/Outbox.json" "$SUPPORT/Rave/LastRead/sets.json"
echo "outbox live check passed"
