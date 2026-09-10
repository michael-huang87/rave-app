# Quick-add artists

Users type a list of artist names for a night and get one set per name. Corrections come afterwards: rename a set into a b2b, fix its artists or date, or delete it.

## Sub-features

- `bulk-add` one POST creates one set per list entry, in the order posted.
- `bulk-add-b2b` an entry containing ` b2b ` splits into several artists on one set.
- `bulk-add-idempotent` re-posting a list creates nothing and reports the names as `skipped`.
- `bulk-add-night` `date` picks the night; it defaults to the event's `start_date`.
- `edit-set` PATCH changes `title`, `artists`, or `date` independently.
- `delete-set` DELETE removes a set and drops `sets_logged`.

## How to get to it (user POV)

- Show detail → **Add artists** → `QuickAddSetsView` sheet. Type or paste names, tap a suggestion from `GET /stats`, reorder or delete before saving, then Save sends one request.
- Show detail → tap any set row → `EditSetView` sheet, which also holds the destructive Delete.
- API: `POST /events/{id}/sets/bulk`, `PATCH /sets/{id}`, `DELETE /sets/{id}`.

## Driving it with curl

Preconditions:

- API healthy; event id from create or list. A disposable DB is recommended.

- **Bulk add.**
  ```bash
  curl -sf -X POST http://127.0.0.1:8000/events/<EVENT_ID>/sets/bulk \
    -H 'Content-Type: application/json' \
    -d '{"artists":["Subtronics","Excision b2b SLANDER","Alvyn"],"date":"2026-09-01"}'
  ```
  Expect 201, `created` with three sets in that order, `skipped` empty. The second set has `title` `"Excision b2b SLANDER"` and `artists` `["Excision","SLANDER"]`.
- **Re-post the same list.** Repeat the identical command. Expect 201, `created` empty, `skipped` listing all three names.
- **Verify order and count.** `GET /events/<EVENT_ID>` → `sets_logged` is 3 and `sets` runs in the posted order for that night.
- **Edit a set.**
  ```bash
  curl -sf -X PATCH http://127.0.0.1:8000/sets/<SET_ID> \
    -H 'Content-Type: application/json' \
    -d '{"title":"Subtronics b2b Ganja White Night","artists":["Subtronics","Ganja White Night"]}'
  ```
  Expect 200 with both fields updated and `date` unchanged.
- **Delete a set.** `curl -sf -o /dev/null -w '%{http_code}' -X DELETE http://127.0.0.1:8000/sets/<SET_ID>` → 204, then `GET /events/<EVENT_ID>` shows `sets_logged` down by one.
- **Proof.** Save the bulk response, the re-post response, and both detail read-backs under `.verify-rave/$RUN_ID/quick-add-artists/`.

## Gotchas

- Idempotency is per `event_id` + `date`. Normalization collapses whitespace and case, so `"  excision  "` matches an existing `Excision` on the same night. The same name on a different night is a new set.
- Blank and whitespace-only entries are dropped silently and never appear in `skipped`.
- Duplicates inside one request body collapse too. First occurrence wins, the rest go to `skipped`.
- Splitting happens only on ` b2b ` surrounded by whitespace. A name containing `b2b` without spaces stays one artist.
- PATCH does not re-derive `artists` from `title`. Changing the title alone leaves the old artists in place; the iOS edit sheet syncs them client-side so the user can see and override the result.
- Bulk-added sets have no `sheet_row`, so they close their night in `GET /events/{id}` in insertion order.
- PATCH with an empty body is a no-op read. Ids are 12-char hashes, copy them from a response.
