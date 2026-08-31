# Shows list

The shows list lets a user browse all tracked shows/festivals, optionally filtered by planned vs attended vs skipped, or by year.

## Sub-features

- `list-all` returns every event ordered by start date.
- `list-status` filters by `planned`, `attended`, or `skipped`. There is no `cancelled` status;
  `?status=cancelled` returns an empty list.
- `list-year` filters by calendar year on the event row.

## How to get to it (user POV)

- Open the **Shows** tab in the iOS app (default tab).
- Use the status picker (All / Went / Planned / Skipped), pinned above the list.
- Rows are grouped under sticky month headers (`August 2026`) with the month's event count trailing.
- Each row is a single line: day of month, show name, then venue (falling back to city). The day is
  tinted by status — cyan went, pink planned, grey skipped — instead of a status capsule.
- Under the **Planned** filter only, months and rows run soonest-first so the next show is the top row.
  Every other filter stays newest-first.
- Multi-day events carry a pink tent glyph after the show name; show detail spells it out as
  `Festival · 5 days`.
- API equivalent: `GET /events` with optional `status` and `year` query params.

## Driving it with curl

Preconditions:

- API healthy at `http://127.0.0.1:8000` (`verify-rave.sh doctor` OK).

- **List all.** `curl -sf http://127.0.0.1:8000/events | python3 -m json.tool | head`. Returns a JSON array; each item has `id`, `show`, `status`, `total`, `sets_logged`.
- **Filter attended.** `curl -sf 'http://127.0.0.1:8000/events?status=attended'`. Every returned row has `"status":"attended"`.
- **Filter year.** `curl -sf 'http://127.0.0.1:8000/events?year=2026'`. Every returned row has `"year":2026`.
- **Proof.** Save output: `curl -sf http://127.0.0.1:8000/events > .verify-rave/$RUN_ID/shows-list/all.json`. Assert array length ≥ 1 after creating a test event (see add-edit-show).

## Gotchas

- `days` is computed from the date range (`end_date - start_date + 1`, floored at 1). A festival is just
  `days > 1` — 44 of 239 events. Two separate rows on back-to-back days (Illenium's two nights) stay two
  shows; that is deliberate, a two-night run is not a festival.
- Status is **computed**, not stored: `skipped` if the show name contains `(cancelled)` or `(skipped)`,
  `attended` if the end date is on or before today, else `planned`. Logged sets do **not** gate it — a
  past show with no sets is still attended, because sets stopped being logged after 2026-06-20.
- The comparison is against `date.today()`, so status moves as real time passes. Tests that pin a
  status must pick dates far from today rather than assuming a frozen `as_of`.
- Empty DB returns `[]` — not an error. Seed with `scripts/clean_sheet.py` or create an event first.
- List rows omit nested `sets`; use show detail for set arrays.
- Sets, spend, and city are **not** on the list row by design; check show detail for those.
- The Planned reversal is client-side. `GET /events` is always newest-first, so curl cannot prove it —
  verify it in the app.
