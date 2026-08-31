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
python3 -m uvicorn --app-dir backend main:app --reload --port 8000
```

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

## iOS (open on a Mac)

1. Build the local snapshot and start the backend.
2. Open `ios/Rave.xcodeproj` in Xcode (iOS 17+).
3. Simulator talks to `http://127.0.0.1:8000`. On a device, change `APIClient.baseURL` to your Mac's LAN IP.
4. Do not submit to App Store Connect.
