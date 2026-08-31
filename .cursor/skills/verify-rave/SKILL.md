---
name: verify-rave
description: Verify Rave (personal show log) by driving the FastAPI backend on port 8000 with curl. Use when proving show CRUD, set logging, spend tracking, or recap behavior. Primary surface is the REST API; iOS Simulator is manual-only (no UI harness).
---

# Verify Rave

Rave is a personal show log: events (shows/festivals), sets seen, and spend in three buckets. The **primary verification surface is the FastAPI REST API** (`backend/main.py`). The iOS SwiftUI app (`ios/Rave.xcodeproj`) is the user UI but has no automated harness — verify it manually in Xcode Simulator after the API checks pass.

**Isolation:** Each verification run uses its own `RAVE_DB` and optional `RAVE_PORT`. Never drive a backend the user already has on `:8000` unless you started it in this run. Refuse to attach to shared instances.

## Launch

From repo root, one-time deps:

```bash
pip install -r backend/requirements.txt
```

Start an isolated instance (default port 8000, disposable DB):

```bash
RUN_ID="$(date +%s)-$$"
export RUN_ID
export ARTIFACTS_DIR=".verify-rave/$RUN_ID"
bash .cursor/skills/verify-rave/scripts/verify-rave.sh launch
```

Ready when `launch` prints `ready http://127.0.0.1:8000`. Logs: `$ARTIFACTS_DIR/state/uvicorn.log`.

Optional snapshot seed (not required for CRUD smoke): download sheet and run `python3 scripts/clean_sheet.py`, then restart or `POST /admin/reload-snapshot`. Snapshot files are gitignored.

**Teardown:** see Cleanup below.

## Doctor

Run before driving whenever health is uncertain:

```bash
bash .cursor/skills/verify-rave/scripts/verify-rave.sh doctor
```

Expect `OK: pid=… port=8000 db=… url=http://127.0.0.1:8000`. Fails if pid missing, process dead, `/health` not `{"ok":true}`, or port owned by another process.

Read-only sanity without the helper:

```bash
curl -sf http://127.0.0.1:8000/health
```

## Drive

Harness: **HTTP via curl** (same paths the iOS `APIClient` uses). Prefer the helper for CRUD smoke; use raw curl for list/recap features per the feature map.

### CRUD smoke (create show → log spend → log set → read detail)

```bash
bash .cursor/skills/verify-rave/scripts/verify-rave.sh drive-crud
```

This exercises the real user write path: `POST /events`, `PATCH /events/{id}/spend`, `POST /events/{id}/sets`, `GET /events/{id}`. Asserts `sets_logged == 1`, `total == 60.5`, `dollars_per_set == 60.5`.

### Pytest (alternative harness)

Uses in-process `TestClient` with temp DB — good for CI, not a running server:

```bash
python3 -m pytest tests/test_api.py::test_create_event_log_set_and_spend -q
python3 -m pytest tests/test_api.py::test_health -q
```

Snapshot-backed tests require local `data/events.json` from `scripts/clean_sheet.py`.

### Feature map

Read `.cursor/skills/verify-rave/features/README.md` before proving a specific feature. Each file lists entry points, curl commands, and expected observable state.

### iOS (manual only)

1. Start backend (Launch above).
2. Open `ios/Rave.xcodeproj` in Xcode, run on iOS 17+ Simulator.
3. Simulator uses `http://127.0.0.1:8000` (`APIClient.baseURL`). Physical device needs LAN IP.
4. No XCTest UI automation exists — screenshot manually if needed.

## Evidence

Proof artifacts live under `.verify-rave/<RUN_ID>/` (gitignored). Standards:

- Exercise the **real user API path**, not direct DB writes.
- Capture **action and resulting state**: request bodies/responses for writes, then a read-back (`GET /events/{id}`).
- Verify **side effects**: row counts via `sets_logged`, computed `total` and `dollars_per_set`, recap aggregates when testing list/recap.
- `drive-crud` writes: `crud/create.json`, `crud/spend.json`, `crud/set.json`, `crud/detail.json`, `crud/proof.json`.
- Record `RUN_ID` and feature ID with every artifact.
- Pytest output alone is insufficient when the task asks for end-to-end server proof — launch uvicorn and curl.

## Cleanup

Removes the server and disposable DB; **keeps proof artifacts**:

```bash
bash .cursor/skills/verify-rave/scripts/verify-rave.sh cleanup
```

Confirm artifacts still exist:

```bash
ls ".verify-rave/$RUN_ID/crud/proof.json"
```

Never `killall uvicorn` — only kill the pid in `$ARTIFACTS_DIR/state/uvicorn.pid`.

## Helpers

| Script | Purpose |
| --- | --- |
| `.cursor/skills/verify-rave/scripts/verify-rave.sh launch` | Start isolated uvicorn |
| `.cursor/skills/verify-rave/scripts/verify-rave.sh doctor` | Pre-flight health + port ownership |
| `.cursor/skills/verify-rave/scripts/verify-rave.sh drive-crud` | Full CRUD smoke + proof JSON |
| `.cursor/skills/verify-rave/scripts/verify-rave.sh cleanup` | Stop our server, remove temp DB |

Environment variables: `RUN_ID`, `ARTIFACTS_DIR`, `RAVE_DB`, `RAVE_PORT`.
