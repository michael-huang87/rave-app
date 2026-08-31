# Show detail

Show detail displays one event's dates, venue, city, spend buckets, computed totals, and all logged sets.

## Sub-features

- `detail-fields` returns event metadata and spend summary.
- `detail-sets` embeds the ordered set list with artists.
- `detail-computed` includes `sets_logged`, `total`, `dollars_per_set`, and `status`.

## How to get to it (user POV)

- Tap a show row in the Shows list → `EventDetailView`.
- API equivalent: `GET /events/{id}`.

## Driving it with curl

Preconditions:

- API healthy; at least one event exists (create via add-edit-show or seed snapshot).

- **Create fixture event** (if none). See add-edit-show; capture `id` from create response.
- **Read detail.** `curl -sf http://127.0.0.1:8000/events/<EVENT_ID> | python3 -m json.tool`. Response includes top-level spend fields and a `sets` array.
- **Assert shape.** Python one-liner or jq: `"sets" in obj`, each set has `title` and `artists`.
- **Proof.** `curl -sf http://127.0.0.1:8000/events/<EVENT_ID> > .verify-rave/$RUN_ID/show-detail/detail.json`.

## Gotchas

- 404 if id unknown: `{"detail":"event not found"}`.
- `dollars_per_set` is null when `sets_logged` is 0.
- Snapshot-backed smoke expects EDC Las Vegas 2026 with 41 sets when `data/events.json` is seeded.
