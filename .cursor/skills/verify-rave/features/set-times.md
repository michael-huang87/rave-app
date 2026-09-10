# Set times

A festival schedule uploaded to the API and shown in the app as a checklist, so a night gets logged
by ticking off what you saw instead of typing it. The log stores the order the sets ran in, never a
clock time; the times live on the schedule, which is reference data.

The schedule is uploaded separately and read at runtime, so a new one appears in the app without a
new build.

## Sub-features

- `schedule-upload` PUT replaces an event's whole schedule and assigns the running order.
- `schedule-rollover` a set after midnight closes its festival day instead of opening it.
- `schedule-read` GET returns the slots in order and marks which are already logged.
- `schedule-seen` POST logs the ticked slots in schedule order, whatever order they were sent in.
- `schedule-unmark` unticking is `DELETE /sets/{id}`; there is no unmark route.
- `schedule-script` `scripts/upload_schedule.py` uploads a CSV or JSON file.

## How to get to it (user POV)

- Show detail → sets card → **⋯** → **Set times** → `ScheduleView`. The entry point does not exist
  until a schedule exists for that event, which keeps it out of the way on the 200-odd events that
  will never have one. With no schedule the header keeps its plain **Add artists** button; the
  ellipsis menu only appears when there are two actions to fit.
- Pick a day, tap rows to tick them, Save. Unticking a row that was already logged deletes that set.
- API: `PUT /events/{id}/schedule`, `GET /events/{id}/schedule`, `POST /events/{id}/schedule/seen`.

## Driving it with curl

Preconditions:

- API healthy; a multi-day event id from create or list.

- **Upload a schedule.**
  ```bash
  curl -sf -X PUT http://127.0.0.1:8000/events/<EVENT_ID>/schedule \
    -H 'Content-Type: application/json' \
    -d '{"slots":[
      {"day":"2026-09-18","stage":"Wompy Woods","title":"Bear Grillz","start_time":"01:30"},
      {"day":"2026-09-18","stage":"Prehistoric Paradox","title":"Excision b2b SLANDER","start_time":"23:00","end_time":"00:30"},
      {"day":"2026-09-18","stage":"Subsidia","title":"Alvyn","start_time":"20:00"}]}'
  ```
  Expect 200 with `count` 3 and `days` holding the one day.
- **Verify the running order.** `GET /events/<EVENT_ID>/schedule` → `sort_index` 0, 1, 2 runs Alvyn
  (20:00), Excision b2b SLANDER (23:00), Bear Grillz (01:30). The 01:30 slot sorting last, not
  first, is the rollover rule working.
- **Tick two slots, sent backwards on purpose.**
  ```bash
  curl -sf -X POST http://127.0.0.1:8000/events/<EVENT_ID>/schedule/seen \
    -H 'Content-Type: application/json' -d '{"slot_ids":["<SLOT_2>","<SLOT_0>"]}'
  ```
  Expect 201. Then `GET /events/<EVENT_ID>` lists the two sets in schedule order, not the order
  posted, and no set carries a time field.
- **Re-tick the same slots.** Repeat the identical command. Expect `created` empty and both titles in
  `skipped`, with `sets_logged` unchanged.
- **Untick.** `DELETE /sets/<SET_ID>` → 204, then `GET .../schedule` shows that slot back to
  `"seen": false` with a null `set_id`.
- **Re-upload.** PUT a shorter list. `GET` returns only the new slots, with `sort_index` renumbered
  from 0.
- **Proof.** Save the PUT response, both GETs, the seen response and the read-back under
  `.verify-rave/$RUN_ID/set-times/`.

## Gotchas

- A festival day runs past midnight. `DAY_ROLLOVER_HOUR` is 6, so a slot starting before 06:00 sorts
  as `hour + 24` inside its `day`. `day` is the festival day, not the calendar day the clock time
  falls on, so a 02:00 Saturday-morning set is uploaded with Friday's `day`.
- `sort_index` is assigned by the server on upload. A client that sends its own is ignored.
- PUT replaces. There is no PATCH and no DELETE; `{"slots": []}` is how you clear a schedule.
- Slot ids are derived from event, day, stage, title and start time, so re-uploading an unchanged
  schedule keeps the same ids and the `seen` flags still line up.
- A ticked set records `sets.slot_id`, which is what lets four slots all titled "Secret Takeover" on
  one night be ticked apart. A set typed through **Add artists** or imported from the sheet has no
  `slot_id`, so it still lights up a slot it matches by `(date, title)`, but it can only claim one,
  and the first in running order wins.
- `split_artists` drops a trailing parenthetical when deriving artists, so
  `Excision (2 Hour Set)` keeps its title and counts as `Excision` in `/stats` and the recap. A colon
  is deliberately left alone, since the sheet's `Malaa: Alter Ego` names the artist first and a
  lineup's `Fresh Meat: KEEB` names it second.
- Unknown slot ids in a `seen` call are ignored rather than fatal, because a client can hold ids from
  a schedule that has since been replaced.
- `sets.slot_index` carries the order and is null for every row that predates this. It sorts after
  `sheet_row`, so an imported night and a ticked night both read back the way they ran.
- Set times are not stored on a set. Asking the API what time you saw someone is not a question this
  data can answer, by design.
