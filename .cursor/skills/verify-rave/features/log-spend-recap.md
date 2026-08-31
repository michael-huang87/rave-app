# Log spend and recap

Users update spend in three buckets (Ticket, Travel, Drinks/Food/Merch) and view aggregate stats on the Recap tab.

## Sub-features

- `log-spend` PATCH replaces bucket values on an event.
- `spend-computed` `total` and `dollars_per_set` recomputed after spend or set changes.
- `recap-all-time` GET /recap returns all-time and by-year aggregates.

## How to get to it (user POV)

- Show detail → **Log spend** → `LogSpendView`.
- **Recap** tab → `RecapView`.
- API: `PATCH /events/{id}/spend`, `GET /recap`.

## Driving it with curl

Preconditions:

- API healthy; event with at least one set for meaningful `dollars_per_set` (optional).

- **Log spend.**
  ```bash
  curl -sf -X PATCH http://127.0.0.1:8000/events/<EVENT_ID>/spend \
    -H 'Content-Type: application/json' \
    -d '{"ticket":40,"travel":12.5,"drinks_food_merch":8}'
  ```
  Expect 200; `"total":60.5`.
- **With one set logged.** `GET /events/<EVENT_ID>` → `dollars_per_set` equals `total / sets_logged`.
- **Recap.**
  ```bash
  curl -sf http://127.0.0.1:8000/recap | python3 -m json.tool
  ```
  Expect keys `as_of`, `all_time`, `by_year`, `counts`. After CRUD smoke, `all_time.sets` increases.
- **Proof.** `curl -sf http://127.0.0.1:8000/recap > .verify-rave/$RUN_ID/recap/recap.json`.

## Gotchas

- PATCH spend replaces provided buckets; omitted buckets keep existing values.
- Recap `all_time.sets` counts set rows, not unique titles.
- Snapshot seed expects `all_time.sets == 1241` when `data/events.json` exists — only assert on seeded DB.
- Recap `as_of` is fixed at 2026-08-31 in backend (`AS_OF` constant).
