# Log a set

Users record a DJ set they saw at a show: title (supports b2b in the title string), artist list, and optional date.

## Sub-features

- `log-set` POST creates a set linked to the parent event.
- `log-set-inherit` venue/city/show copied from parent event.
- `log-set-count` increments `sets_logged` on the parent.

## How to get to it (user POV)

- Show detail → **Add artists** → `QuickAddSetsView` for entering a night's list, and tapping a set row → `EditSetView` for correcting one. See [Quick-add artists](./quick-add-artists.md) for both.
- API: `POST /events/{id}/sets`. The app itself now posts `POST /events/{id}/sets/bulk`; this single-set route stays for one-off and scripted logging.

## Driving it with curl

Preconditions:

- API healthy; event id from create or list.

- **Log set.**
  ```bash
  curl -sf -X POST http://127.0.0.1:8000/events/<EVENT_ID>/sets \
    -H 'Content-Type: application/json' \
    -d '{"title":"Test Artist b2b Other","artists":["Test Artist","Other"],"date":"2026-09-01"}'
  ```
  Expect 201; response includes `venue` from parent event.
- **Verify count.** `GET /events/<EVENT_ID>` → `sets_logged` increased by 1; new set appears in `sets` array with matching `title`.
- **Proof.** Or run full smoke: `bash .cursor/skills/verify-rave/scripts/verify-rave.sh drive-crud` (creates event, spend, set, detail in one flow).

## Gotchas

- If `artists` is omitted, the title is split on ` b2b ` and falls back to `[title]`.
- The id hashes title + date + artist count, so an identical repeat set collides. The server re-hashes with an incrementing discriminator until the id is free, so posting the same body twice yields two rows with different ids rather than a 500.
- Logging sets on a past-dated event can flip `status` to `attended` when end date ≤ as_of.
