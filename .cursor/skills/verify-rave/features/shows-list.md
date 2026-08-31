# Shows list

The shows list lets a user browse all tracked shows/festivals, optionally filtered by planned vs attended vs cancelled, or by year.

## Sub-features

- `list-all` returns every event ordered by start date.
- `list-status` filters by `planned`, `attended`, or `cancelled`.
- `list-year` filters by calendar year on the event row.

## How to get to it (user POV)

- Open the **Shows** tab in the iOS app (default tab).
- Use the status picker (Planned / Went / Cancelled / All) and optional year filter.
- API equivalent: `GET /events` with optional `status` and `year` query params.

## Driving it with curl

Preconditions:

- API healthy at `http://127.0.0.1:8000` (`verify-rave.sh doctor` OK).

- **List all.** `curl -sf http://127.0.0.1:8000/events | python3 -m json.tool | head`. Returns a JSON array; each item has `id`, `show`, `status`, `total`, `sets_logged`.
- **Filter attended.** `curl -sf 'http://127.0.0.1:8000/events?status=attended'`. Every returned row has `"status":"attended"`.
- **Filter year.** `curl -sf 'http://127.0.0.1:8000/events?year=2026'`. Every returned row has `"year":2026`.
- **Proof.** Save output: `curl -sf http://127.0.0.1:8000/events > .verify-rave/$RUN_ID/shows-list/all.json`. Assert array length ≥ 1 after creating a test event (see add-edit-show).

## Gotchas

- Status is **computed**, not stored: cancelled if `(cancelled)` in show name; attended if sets logged and end date ≤ `as_of` (2026-08-31); else planned.
- Empty DB returns `[]` — not an error. Seed with `scripts/clean_sheet.py` or create an event first.
- List rows omit nested `sets`; use show detail for set arrays.
