#!/usr/bin/env bash
# Rave API verification helper. Run from repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"

# Prefer real curl over shell aliases (e.g. context-mode wrappers).
if [[ -x /usr/bin/curl ]]; then
  CURL="/usr/bin/curl"
else
  CURL="$(command -v curl)"
fi

RUN_ID="${RUN_ID:-$(date +%s)-$$}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/.verify-rave/$RUN_ID}"
STATE_DIR="${STATE_DIR:-$ARTIFACTS_DIR/state}"
PID_FILE="$STATE_DIR/uvicorn.pid"
LOG_FILE="$STATE_DIR/uvicorn.log"
DB_FILE="${RAVE_DB:-$STATE_DIR/rave.db}"
PORT="${RAVE_PORT:-8000}"
BASE_URL="http://127.0.0.1:$PORT"

mkdir -p "$ARTIFACTS_DIR" "$STATE_DIR"

cmd="${1:-}"
shift || true

case "$cmd" in
  launch)
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "Already running (pid $(cat "$PID_FILE"))"
      exit 0
    fi
    existing="$(lsof -ti ":$PORT" 2>/dev/null | head -1 || true)"
    if [[ -n "$existing" ]]; then
      echo "FAIL: port $PORT already in use by pid $existing — set RAVE_PORT to a free port" >&2
      exit 1
    fi
    export RAVE_DB="$DB_FILE"
    if [[ -x "$ROOT/.venv/bin/python" ]]; then
      PYTHON="$ROOT/.venv/bin/python"
    else
      PYTHON="python3"
    fi
    "$PYTHON" -m uvicorn --app-dir backend main:app --port "$PORT" >"$LOG_FILE" 2>&1 &
    echo $! >"$PID_FILE"
    for _ in $(seq 1 30); do
      if "$CURL" -sf "$BASE_URL/health" >/dev/null 2>&1; then
        owner="$(lsof -ti ":$PORT" 2>/dev/null | head -1 || true)"
        if [[ "$owner" != "$(cat "$PID_FILE")" ]]; then
          echo "FAIL: port $PORT owned by pid $owner after launch (expected $(cat "$PID_FILE"))" >&2
          exit 1
        fi
        echo "ready $BASE_URL (pid $(cat "$PID_FILE"), db $DB_FILE)"
        exit 0
      fi
      sleep 0.2
    done
    echo "Server failed to become ready; see $LOG_FILE" >&2
    exit 1
    ;;
  doctor)
    ok=0
    if [[ ! -f "$PID_FILE" ]]; then
      echo "FAIL: no pid file at $PID_FILE — run launch first"
      exit 1
    fi
    pid="$(cat "$PID_FILE")"
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "FAIL: uvicorn pid $pid not running"
      exit 1
    fi
    health="$("$CURL" -sf "$BASE_URL/health" || true)"
    if [[ "$health" != '{"ok":true}' ]]; then
      echo "FAIL: health check returned: ${health:-<empty>}"
      exit 1
    fi
    owner="$(lsof -ti ":$PORT" 2>/dev/null | head -1 || true)"
    if [[ -n "$owner" && "$owner" != "$pid" ]]; then
      echo "FAIL: port $PORT owned by pid $owner, expected $pid"
      exit 1
    fi
    echo "OK: pid=$pid port=$PORT db=$DB_FILE url=$BASE_URL"
    ;;
  drive-crud)
    mkdir -p "$ARTIFACTS_DIR/crud"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    show="Verify Run $RUN_ID"
    create="$("$CURL" -sf -X POST "$BASE_URL/events" \
      -H 'Content-Type: application/json' \
      -d "{\"show\":\"$show\",\"venue\":\"Warehouse\",\"city\":\"Oakland, CA\",\"start_date\":\"2026-09-01\",\"ticket\":40}")"
    echo "$create" | tee "$ARTIFACTS_DIR/crud/create.json"
    eid="$(python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" <<<"$create")"
    spend="$("$CURL" -sf -X PATCH "$BASE_URL/events/$eid/spend" \
      -H 'Content-Type: application/json' \
      -d '{"ticket":40,"travel":12.5,"drinks_food_merch":8}')"
    echo "$spend" | tee "$ARTIFACTS_DIR/crud/spend.json"
    logged="$("$CURL" -sf -X POST "$BASE_URL/events/$eid/sets" \
      -H 'Content-Type: application/json' \
      -d '{"title":"Test Artist b2b Other","artists":["Test Artist","Other"],"date":"2026-09-01"}')"
    echo "$logged" | tee "$ARTIFACTS_DIR/crud/set.json"
    detail="$("$CURL" -sf "$BASE_URL/events/$eid")"
    echo "$detail" | tee "$ARTIFACTS_DIR/crud/detail.json"
    python3 - <<PY
import json, sys
d = json.loads("""$detail""")
assert d["sets_logged"] == 1, d
assert d["total"] == 60.5, d
assert d["dollars_per_set"] == 60.5, d
assert d["sets"][0]["title"] == "Test Artist b2b Other"
print("PASS: create→spend→set→detail")
PY
    cat >"$ARTIFACTS_DIR/crud/proof.json" <<EOF
{"run_id":"$RUN_ID","timestamp":"$ts","event_id":"$eid","show":"$show","sets_logged":1,"total":60.5}
EOF
    echo "proof written to $ARTIFACTS_DIR/crud/proof.json"
    ;;
  cleanup)
    if [[ -f "$PID_FILE" ]]; then
      pid="$(cat "$PID_FILE")"
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
      fi
      rm -f "$PID_FILE"
    fi
    rm -f "$DB_FILE" "$DB_FILE-journal" 2>/dev/null || true
    echo "cleaned instance (artifacts kept at $ARTIFACTS_DIR)"
    ;;
  *)
    echo "Usage: verify-rave.sh {launch|doctor|drive-crud|cleanup}" >&2
    exit 1
    ;;
esac
