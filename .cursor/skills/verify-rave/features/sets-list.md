# Sets list

The Sets tab lists every logged set, newest day first, in the order the sets were seen within a day.

## Sub-features

- `list-all` returns every set across all events.
- `list-for-event` returns one event's sets.
- `search` filters client-side on set title, artist names, show, or venue.

## How to get to it (user POV)

- Open the **Sets** tab (second of four) in the iOS app.
- Sets are grouped under sticky day headers reading `Sat Jun 20, 2026 · Said the Sky · Brooklyn Steel`.
- Each set is one line: the title, plus the performer names right-aligned only when they differ from
  the title (b2b rows). About 13 sets fit a screen against 4 before.
- Search with the field at the top; grouping applies to the filtered results.
- API equivalent: `GET /sets`, or `GET /sets?event_id=<id>`.

## Driving it with curl

Preconditions:

- API healthy at `http://127.0.0.1:8000` (`verify-rave.sh doctor` OK).

- **List all.** `curl -sf http://127.0.0.1:8000/sets > .verify-rave/$RUN_ID/sets-list/all.json`.
  Each item has `id`, `event_id`, `title`, `date`, `artists`.
- **Assert day order.** `date` runs descending across the whole array.
- **Assert within-day order.** For a festival day, the titles are **not** alphabetical. With the
  committed snapshot, `2026-05-17` starts `Armin Van Buuren, Inellea, Black Tiger Sex Machine`.
- **Filter by event.** `curl -sf 'http://127.0.0.1:8000/sets?event_id=<id>'`; every row matches.

## Gotchas

- Order within a day comes from `sheet_row`, the row number on the sheet's Sets tab, which is the only
  time signal recorded. It is an ordering key and is deliberately not exposed in the API response.
- A set logged in the app has no `sheet_row` and sorts to the **end** of its day, not the start.
- Adding `sheet_row` to a pre-existing `rave.db` happens automatically at startup (`ALTER TABLE` plus a
  backfill keyed on set id). A DB seeded before that change but with `data/sets.json` missing keeps
  NULL rows and falls back to arbitrary order.
- Date, show, and venue are **not** on the row; they are in the day header, since they repeat for every
  set of a night.
- Row height is set by `defaultMinListRowHeight`, not by the text. SwiftUI's 44pt default is most of a
  one-line row, so both list tabs override it to 30.
