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
| `ios/Rave.xcodeproj` | SwiftUI app: show list, detail, add/edit, add artists, edit set, log spend, sets, stats, recap |

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

Useful routes: `GET /events`, `GET /events/{id}` (includes sets + spend), `POST /events`, `PATCH /events/{id}`, `PATCH /events/{id}/spend`, `POST /events/{id}/sets`, `POST /events/{id}/sets/bulk`, `PATCH /sets/{id}`, `DELETE /sets/{id}`, `PUT /events/{id}/schedule`, `GET /events/{id}/schedule`, `POST /events/{id}/schedule/seen`, `GET /recap`, `GET /stats`.

## Set times

A festival schedule is uploaded per event and read by the app at runtime, so a schedule that drops
the week of the show appears without a new build. The log keeps the order the sets ran in, not the
clock times.

```bash
python3 scripts/upload_schedule.py <event_id> schedule.csv --dry-run
python3 scripts/upload_schedule.py <event_id> schedule.csv
```

CSV columns are `day,stage,title,start_time,end_time`. `day` is the **festival** day, so a 02:00 set
is uploaded under the night it belongs to, not the calendar date it starts on.

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
restart instead — except where `init_schema` carries an explicit migration, as it
does for `sets.sheet_row`.

`reconcile.py` is read-only and always exits 0. Re-run it after editing the
sheet to watch the lists shrink. Empty sections still print their `(0)` so a
category that regresses is visible.

## iOS (open on a Mac)

1. Build the local snapshot and start the backend.
2. Open `ios/Rave.xcodeproj` in Xcode (iOS 17+).
3. Simulator talks to `http://127.0.0.1:8000`. On a device, set `APIBaseURL` in `ios/Rave/Info.plist` to your Mac's API URL (see below).
4. After a successful load, the app writes last-read JSON under Application Support `Rave/LastRead/` (events list, event detail, sets, recap, stats). Offline or unreachable backend shows that cache with an "Offline — last loaded data" banner. Edits are refused until there is a signal — there is no write queue. Pull to refresh or wait for the path to come back; both refetch and update the cache.
5. Do not submit to App Store Connect.

This Linux VM cannot simulator-run iOS. Cache file layout is covered by `tests/test_last_read_cache.py`. On a Mac: load online, enable airplane mode, reopen Shows / a show / Recap / Stats.

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

### Installing a build to a phone that is not here

Tailscale lets the running app reach the API from anywhere. It does **not** let Xcode install a
build: with the phone online on the tailnet, `xcrun devicectl list devices` still reports it
`unavailable`. iOS 17+ discovers phones through Bonjour, which is link-local multicast and cannot
cross a WireGuard tunnel.

`scripts/coredevice-tailnet.sh` works around that. It fabricates the phone's Bonjour record on this
Mac and points it at the Mac's **own** en0 address, where `socat` forwards the CoreDevice ports to
the phone's tailnet IP. The record has to name en0 rather than the tailnet address, because
`remotepairingd` scopes its connection to the local interface and refuses a tunnel-scoped peer.

```bash
brew install socat
bash scripts/coredevice-tailnet.sh status        # preflight
bash scripts/coredevice-tailnet.sh capture       # ONCE, phone on USB or this wifi
bash scripts/coredevice-tailnet.sh bridge        # then, with the phone anywhere
```

`capture` is the step that needs the phone present, because it reads the real advertisement the
bridge later replays. After that the phone can be on cellular in another country.

If the phone is never next to the build Mac, run `probe` on whatever machine it *is* next to and
copy the block it prints into the build Mac's config. `probe` needs no Tailscale and writes nothing,
and on a Linux box the equivalent is `avahi-browse -rt _remotepairing._tcp`.

**Before trusting any of this, check the phone actually accepts the connection over the tunnel:**

```bash
nc -z -G 5 <phone-tailnet-ip> 49152 && echo OPEN || echo CLOSED
```

Everything else is plumbing around that one fact. If it reports CLOSED with the phone awake and
Tailscale connected in the foreground, the bridge cannot work, because there is nothing on the far
side for `socat` to reach.

Run `bridge` while installing rather than leaving it up. Each proxied port costs a `socat` pair at
about 2.1MB, so the default 55100-55130 range holds roughly 130MB. The trusted tunnel picks its port
per session, so widen with `COREDEVICE_PORT_LO` / `COREDEVICE_PORT_HI` if an install cannot connect.
`install-agent` will run it at login if you would rather pay the memory than remember the command.

Two things to know. The listeners bind to the Mac's LAN address, so anything on your home network
can reach the phone's developer services while the bridge is up. And this leans on Apple's private
discovery stack, so an OS update can break it; nothing here is a supported interface.

Method credit: [How to remotely iterate & deploy your sideloaded iOS apps over
tailnet](https://dev.to/kvnpt/how-to-remotely-iterate-deploy-your-sideloaded-ios-apps-over-tailnet-jak).
