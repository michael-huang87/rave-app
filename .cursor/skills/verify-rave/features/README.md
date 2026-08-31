# Rave verification map

This directory is the maintained source for verifying user-facing behavior of Rave. Read the index before driving the app, then use the matching feature file as the recipe.

## Baseline preconditions

- Launch the API with an isolated DB: `bash .cursor/skills/verify-rave/scripts/verify-rave.sh launch` (sets `RUN_ID` and `ARTIFACTS_DIR`).
- Default URL: `http://127.0.0.1:8000`. Override with `RAVE_PORT` if 8000 is taken.
- Run `bash .cursor/skills/verify-rave/scripts/verify-rave.sh doctor` and require OK with matching pid and db path.
- Never drive a backend instance you did not start in this verification run.

## Driving conventions

- Start every recipe from the baseline state unless its preconditions say otherwise.
- Use HTTP against the same routes the iOS app uses (`APIClient.swift`).
- Treat curl bodies and paths as literal. JSON keys use snake_case.
- Capture write responses **and** a read-back GET for mutation proof.
- Restore or delete test data created during a recipe; do not remove proof artifacts during cleanup.

## Proof and skip reporting

- Capture the user action and the resulting state, not only the final response.
- API proof includes request method/path, response status, response body JSON, and a follow-up GET where applicable.
- Mutation proof must show computed fields (`total`, `sets_logged`, `dollars_per_set`, recap aggregates).
- Record the feature ID and entry point with every artifact under `.verify-rave/<RUN_ID>/`.
- Report unreachable paths with the attempted command and unmet precondition.
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file uses exactly four H2 sections: `Sub-features`, `How to get to it (user POV)`, `Driving it with curl`, and `Gotchas`.

## Features

- [Shows list](./shows-list.md) — filter and browse events by status/year.
- [Show detail](./show-detail.md) — view a single show with sets and spend.
- [Add / edit show](./add-edit-show.md) — create and update event metadata.
- [Log a set](./log-set.md) — record a DJ set on an event.
- [Sets list](./sets-list.md) — browse every logged set in the order it was seen.
- [Stats](./stats.md) — artist / venue / city rankings.
- [Log spend and recap](./log-spend-recap.md) — update spend buckets and read aggregate stats.
