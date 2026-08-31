# Add / edit show

Users add a new show (festival/night out) or edit its name, venue, city, and dates. New shows start as **planned** with optional initial ticket spend.

## Sub-features

- `create-show` adds a new event via POST.
- `edit-show` patches metadata fields.
- `create-planned` new events have `status: planned` until sets + dates qualify as attended.

## How to get to it (user POV)

- Shows list → **+** button → `EventFormView` sheet.
- Edit from show detail → edit action.
- API: `POST /events`, `PATCH /events/{id}`.

## Driving it with curl

Preconditions:

- API healthy; disposable DB recommended so test rows do not pollute user data.

- **Create.** 
  ```bash
  curl -sf -X POST http://127.0.0.1:8000/events \
    -H 'Content-Type: application/json' \
    -d '{"show":"Smoke Test Showcase","venue":"Warehouse","city":"Oakland, CA","start_date":"2026-09-01","ticket":40}'
  ```
  Expect HTTP 201, `"status":"planned"`, generated `id`.
- **Edit.**
  ```bash
  curl -sf -X PATCH http://127.0.0.1:8000/events/<EVENT_ID> \
    -H 'Content-Type: application/json' \
    -d '{"show":"Smoke Test Showcase (updated)","city":"Berkeley, CA"}'
  ```
  Expect 200; `show` and `city` updated; spend unchanged.
- **Read-back.** `GET /events/<EVENT_ID>` confirms persisted values.
- **Proof.** Save create and detail responses under `.verify-rave/$RUN_ID/add-edit-show/`.

## Gotchas

- `show` is required on create; whitespace trimmed.
- `year` inferred from `start_date` when omitted.
- PATCH with empty body is a no-op read (returns current event).
- Id is a 12-char hash — copy from create response, do not guess.
