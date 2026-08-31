# Rave v1

**Job:** a rave-goer tracks shows/festivals they went to or plan to go to, logs each set they saw, and logs spend in three buckets: Ticket, Travel, Drinks/Food/Merch.

That is the whole product. Not a festival finder, ticket marketplace, social graph, lighting suite, or a second finance app.

## Sheet mapping

Source (public): [Google Sheet](https://docs.google.com/spreadsheets/d/1-J4MFiVGu204R5ySidxWPogmTyiNU-v5XUUuIXAKq0w/edit)

| Sheet tab | In v1 |
| --- | --- |
| Costs (2023), Costs2 (2024), 2025, 2026 | Event rows. Date, Show, Venue, City, Ticket, Travel, Drinks/Food/Merch. Total and $ per set are computed. |
| 2023 / 2024 calendars | **Not imported.** They mix hiking, dinners, daytrips. Show rows already live on Costs / Costs2. |
| Sets | Every non-empty row. `Artist` = set title (b2bs allowed). `Artists` = comma-separated names. Linked to a parent event by show name + date/venue so you do not retype venue/city. Row order is kept: it is the order you saw the sets. |
| ArtistsVenues, Stats | **Derived.** Recomputed locally into `data/stats.json` and `GET /recap`. |

Empty formula-fill rows on Costs2 are ignored. Footer "Total" rows are ignored. Personal trip wrappers on Costs/Costs2 (ski trips, city visits, Pokémon Go Fest, movies) are dropped. After you run `scripts/clean_sheet.py`, `data/CLEANING.md` lists exactly what this pass skipped.

**2022** has sets but no cost tab. Those events are derived from Sets (spend $0).

## Planned vs went

Taken from the sheet, not a separate column:

- **Skipped** — `(Cancelled)` or `(Skipped)` in the show name. One bucket for
  "did not go", whether the show was called off or you bailed. Spend still counts.
- **Went** — the event's end date is in the past
- **Planned** — the end date is in the future

Logged sets do not gate the status. Sets stopped being logged after 2026-06-20, so a past show with no sets is still a show you went to.

## Spend

Three buckets only: Ticket, Travel, Drinks/Food/Merch. `total = sum`. `$ per set = total / sets_logged`, blank when there are no sets.

## Recap (intentionally small)

All-time and by year: sets, unique artists (from the Artists column), unique show names (from Sets), spend. Yearly sets / set titles / show names match the Stats tab. Not a heavy analytics suite.

## Screens

Shows list (filter planned / went / cancelled) → show detail (dates, venue, city, spend, sets) → add/edit show, log a set, log spend. Recap tab. Single user.
