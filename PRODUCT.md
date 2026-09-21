# Rave v1

**Job:** a rave-goer tracks shows/festivals they went to or plan to go to, logs each set they saw, and logs spend in three buckets: Ticket, Travel, Drinks/Food/Merch.

That is the whole product. Not a festival finder, ticket marketplace, social graph, lighting suite, or a second finance app.

A schedule you upload for a show you are already tracking is the one exception, and it earns its
place by making logging faster rather than by helping you discover anything. See **Set times**.

## Offline

New features work offline the same way logging does. A local write updates Sets, Stats, and Recap — and any screen that shows the same data — immediately, and reconciles with the server when the connection returns. If a feature cannot work that way, stop and confirm the architecture with Chamiel before shipping an online-only design.

## Sheet mapping

Source (public): [Google Sheet](https://docs.google.com/spreadsheets/d/1-J4MFiVGu204R5ySidxWPogmTyiNU-v5XUUuIXAKq0w/edit)

| Sheet tab | In v1 |
| --- | --- |
| Costs (2023), Costs2 (2024), 2025, 2026 | Event rows. Date, Show, Venue, City, Ticket, Travel, Drinks/Food/Merch. Total and $ per set are computed. |
| 2023 / 2024 calendars | **Not imported.** They mix hiking, dinners, daytrips. Show rows already live on Costs / Costs2. |
| Sets | Every non-empty row. `Artist` = set title (b2bs allowed). `Artists` = comma-separated names. Linked to a parent event by show name + date/venue so you do not retype venue/city. Row order is kept: it is the order you saw the sets. |
| ArtistsVenues, Stats | **Derived.** Recomputed locally into `data/stats.json`, `GET /recap`, and `GET /stats`. |

Empty formula-fill rows on Costs2 are ignored. Footer "Total" rows are ignored. Personal trip wrappers on Costs/Costs2 (ski trips, city visits, Pokémon Go Fest, movies) are dropped. After you run `scripts/clean_sheet.py`, `data/CLEANING.md` lists exactly what this pass skipped.

**2022** has sets but no cost tab. Those events are derived from Sets (spend $0).

## Planned vs went

Taken from the sheet, not a separate column:

- **Skipped** — `(Cancelled)` or `(Skipped)` in the show name. One bucket for
  "did not go", whether the show was called off or you bailed. Spend still counts.
- **Went** — the event's end date is in the past
- **Planned** — the end date is in the future

Logged sets do not gate the status. Sets stopped being logged after 2026-06-20, so a past show with no sets is still a show you went to.

## Festivals

`days = end_date - start_date + 1`. Anything over 1 is a festival — 44 events, from 2-day
Wobbleland to 7-day EDSea. Nothing is inferred; the sheet already dates a festival as a range.
Two separate rows on back-to-back days (Illenium's two nights) stay two shows.

## Spend

Three buckets only: Ticket, Travel, Drinks/Food/Merch. `total = sum`. `$ per set = total / sets_logged`, blank when there are no sets.

## Recap (intentionally small)

All-time and by year: sets, unique artists (from the Artists column), unique show names (from Sets), spend. Yearly sets / set titles / show names match the Stats tab. Not a heavy analytics suite.

`GET /stats` adds the ArtistsVenues rankings: artists by sets seen, venues and cities by **distinct
days** (the sheet's `COUNTUNIQUEIFS` over `Sets[Date]`, not a count of events).

## Screens

Shows list (by month, filter planned / went / skipped) → show detail (dates, venue, city, spend, sets)
→ add/edit show, add artists, log spend. Sets tab, Stats tab, Recap tab. Single user.

Adding sets is two moves, because a festival night is a list you type fast and fix later. **Add
artists** takes a list of names for one night, suggests names already in your data, and makes one set
per name. Tapping a set opens it for correction: rename it into a b2b, fix the artists or the date,
or delete it. Re-typing a night you already entered adds nothing.

## Set times

A schedule can be uploaded per event and shown as a checklist, so a night gets logged by ticking off
what you saw. **Set times** appears on show detail only once a schedule exists for that show, and the
app reads it at runtime, so a schedule uploaded the week of the festival shows up without a new
build.

What gets stored is the order the sets ran in, not the clock time. `sets.slot_index` carries that
order and nothing carries a time, because "what did I see, in what order" is a question this product
answers and "what time was I standing there" is not. The times exist on the schedule, which is
reference data you uploaded, and they are there so the picker reads like the poster.

A festival day runs past midnight, so a 02:00 set belongs to the night before. `DAY_ROLLOVER_HOUR`
is 6: a slot starting before then sorts to the end of its day rather than the start.

The schedule opens on the stage grid rather than the list, because a festival night is a question
about which stage to be standing at. It opens on tonight rather than on day 1. A day with no times
on it has nothing to place on a grid, so that day falls back to the list.

## Festival mode

During a festival the schedule is the only screen that matters, and reaching it costs a scroll and
three taps. **Festival mode** puts that schedule in the tab bar and opens the app on it. The other
tabs stay one tap away.

It is on by itself for a show whose dates cover today and that has a schedule uploaded, so a
festival needs no setup on the day. On from the first midnight through 06:00 the morning after the
last night, the same rollover the set times use, because arriving a day early and leaving after a
long last night are the two ways you actually meet a festival.

Nothing stores "on". The stored value is only an **override**, set by the toggle on a show's Set
times menu:

| Stored | What it does |
| --- | --- |
| nothing | The festival happening now, if it has a schedule. |
| `on:<id>` | That show, before its first night. For reading next month's lineup in the tab. |
| `off:<id>` | Not that show, while it is running. For putting the tab away. |

An override dies with the show it names, so it never leaks into the next festival. A show with no
schedule has no tab to offer, and a show sharing the weekend with a festival cannot shadow the one
that does have a schedule.

The Shows list runs newest-first, except under **Planned**, where it flips to soonest-first — the
next show is the one that matters.
