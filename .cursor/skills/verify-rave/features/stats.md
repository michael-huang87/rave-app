# Stats

The Stats tab ranks artists, venues, and cities, reproducing the sheet's `ArtistsVenues` tab in the app.

## Sub-features

- `rank-artists` ranks performer names by sets seen.
- `rank-venues` ranks venues by distinct days visited.
- `rank-cities` ranks cities by distinct days with a show.

## How to get to it (user POV)

- Open the **Stats** tab (third of four) in the iOS app.
- Each section lists its top 10; tap `All <n>` to push the full ranked list.
- API equivalent: `GET /stats`.

## Driving it with curl

Preconditions:

- API healthy at `http://127.0.0.1:8000` (`verify-rave.sh doctor` OK).
- Seeded from a snapshot; an empty DB returns three empty arrays.

- **Read the rankings.** `curl -sf http://127.0.0.1:8000/stats > .verify-rave/$RUN_ID/stats/all.json`.
  Returns `{"artists": [...], "venues": [...], "cities": [...]}`, each entry `{"name", "count"}`.
- **Assert ranked.** Each array is sorted by `count` descending, then name.
- **Assert it matches the sheet.** With the committed snapshot these are exact:
  `artists[0] == {"name": "Subtronics", "count": 26}`, `venues["Bill Graham"] == 37`,
  `venues["Midway"] == 23`, `cities["San Francisco, CA"] == 74`, `cities["Las Vegas, NV"] == 26`.

## Gotchas

- Venues and cities count **distinct set-dates**, not events — the sheet's `COUNTUNIQUEIFS` over
  `Sets[Date]`. Counting events instead put Midway at 29 against the sheet's 23.
- Everything is derived from the `sets` table, so a show with no logged sets contributes nothing.
  Venue and city totals therefore lag the event list.
- Names group case-insensitively; the first casing seen is what displays.
- Counts are computed live from SQLite, not read from `data/stats.json`, so hand-added shows count.
