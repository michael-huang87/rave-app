# Rave

Personal show log: what you went to (or plan to), which sets you saw, and what you spent. Not a festival finder, marketplace, or social app.

v1 is a **working skeleton** with a real data model imported from the existing Google Sheet. The cleaned snapshot is **local only** (gitignored). The iOS app was scaffolded for Xcode on a Mac; it was **not** run in the iOS Simulator on the Linux VM that created this repo.

## What's in this repo

| Path | What it is |
| --- | --- |
| `PRODUCT.md` | v1 job and sheet → app mapping |
| `data/README.md` | How to download the sheet and build a local snapshot |
| `scripts/clean_sheet.py` | Writes `data/*.json` on your machine |
| `backend/` | FastAPI + SQLite, seeds from the local snapshot if present |
| `ios/Rave.xcodeproj` | SwiftUI app: show list, detail, add/edit, log set, log spend, recap |

## Local snapshot (Mac)

Do this once (or whenever the sheet changes). Nothing under `data/` except that README is committed.

```bash
mkdir -p data/source
curl -L -o data/source/rave-sheet.xlsx \
  "https://docs.google.com/spreadsheets/d/1-J4MFiVGu204R5ySidxWPogmTyiNU-v5XUUuIXAKq0w/export?format=xlsx"
pip install -r backend/requirements.txt
python3 scripts/clean_sheet.py
```

## Backend

```bash
python3 -m uvicorn --app-dir backend main:app --reload --host 0.0.0.0 --port 8000
```

Use `--host 0.0.0.0` so a phone on the same Wi‑Fi can reach the API. Simulator still uses `127.0.0.1`.

Without a local snapshot the API starts empty; you can still add shows by hand. With a snapshot it seeds events/sets/spend.

```bash
curl -s http://127.0.0.1:8000/events | head
curl -s http://127.0.0.1:8000/sets | head
curl -s http://127.0.0.1:8000/recap
```

Useful routes: `GET /events`, `GET /events/{id}` (includes sets + spend), `POST /events`, `PATCH /events/{id}`, `PATCH /events/{id}/spend`, `POST /events/{id}/sets`, `GET /recap`.

```bash
python3 -m pytest tests/test_api.py -q
```

Snapshot-backed tests skip if `data/events.json` is missing.

## Reconciling the data

The sheet is the source of truth, so corrections belong in the sheet or in
`scripts/clean_sheet.py`, never in the DB directly.

```bash
cp backend/rave.db backend/rave.db.bak   # reload-snapshot drops the DB
python3 scripts/reconcile.py             # every remaining discrepancy, by category
```

`POST /admin/reload-snapshot` returns 409 rather than dropping rows the
snapshot cannot regenerate; pass `?force=true` to override. It cannot add new
columns to an existing DB, so a schema change needs `rm backend/rave.db` and a
restart instead.

`reconcile.py` is read-only and always exits 0. Re-run it after editing the
sheet to watch the lists shrink. Empty sections still print their `(0)` so a
category that regresses is visible.

## iOS (open on a Mac)

1. Build the local snapshot and start the backend.
2. Open `ios/Rave.xcodeproj` in Xcode (iOS 17+).
3. Simulator talks to `http://127.0.0.1:8000`. On a device, set `APIBaseURL` in `ios/Rave/Info.plist` to your Mac's API URL (see below).
4. Do not submit to App Store Connect.

### Physical device — home Wi‑Fi only

Set `APIBaseURL` to `http://<your-mac-lan-ip>:8000`. Phone and Mac must be on the same Wi‑Fi.

```bash
ipconfig getifaddr en0
bash scripts/print_device_api_url.sh
```

### Physical device — anywhere (Tailscale, free)

Tailscale gives your Mac a stable private IP (`100.x.x.x`) that works on home Wi‑Fi and cellular.

**1. Mac — install and sign in**

- App Store: search **Tailscale**, install, open, sign in (Google/Apple/GitHub all work).
- Or Terminal: `brew install --cask tailscale` (needs your password), then open Tailscale from Applications.

**2. iPhone — install and sign in**

- App Store: **Tailscale**, install, sign in with the **same account** as the Mac.
- Allow the VPN configuration when prompted. Leave Tailscale connected.

**3. Get your Mac's Tailscale IP**

```bash
tailscale ip -4
# example: 100.64.0.5
```

**4. Point the app at Tailscale**

In `ios/Rave/Info.plist`, set:

```xml
<key>APIBaseURL</key>
<string>http://100.x.x.x:8000</string>
```

Replace `100.x.x.x` with the output of `tailscale ip -4`. Rebuild and run on your phone.

**5. Keep the backend running on your Mac**

```bash
.venv/bin/python -m uvicorn --app-dir backend main:app --host 0.0.0.0 --port 8000
```

Your Mac must be awake and online. Tailscale on the phone must be connected (VPN icon in status bar).

**Verify from the phone:** open Safari and visit `http://100.x.x.x:8000/health` — you should see `{"ok":true}`.
