# Log a set

Users record a DJ set they saw at a show: title (supports b2b in the title string), artist list, and optional date.

## Sub-features

- `log-set` POST creates a set linked to the parent event.
- `log-set-inherit` venue/city/show copied from parent event.
- `log-set-count` increments `sets_logged` on the parent.

## How to get to it (user POV)

- Show detail → **Log set** → `LogSetView`.
- API: `POST /events/{id}/sets`.

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

- If `artists` omitted, defaults to `[title]`.
- Duplicate titles on same event get distinct ids (hash includes title + date + artist count).
- Logging sets on a past-dated event can flip `status` to `attended` when end date ≤ as_of.
