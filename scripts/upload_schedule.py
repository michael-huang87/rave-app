#!/usr/bin/env python3
"""Upload a festival's set times to an event, so the app can show a schedule with no new build.

The server owns the running order: it sorts the rows and assigns sort_index, so the order
you hand it here does not matter. --dry-run prints what would be sent and touches nothing.
A re-upload replaces the event's schedule, so fixing a stage name and re-running converges.
"""

from __future__ import annotations

import argparse
import csv
import json
import urllib.error
import urllib.request
from collections import defaultdict
from pathlib import Path

FIELDS = ("day", "stage", "title", "start_time", "end_time")


def read_csv(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        missing = {"day", "title"} - set(reader.fieldnames or [])
        if missing:
            raise SystemExit(f"{path} needs a header row with {', '.join(sorted(missing))}")
        return [{k: (row.get(k) or "").strip() or None for k in FIELDS} for row in reader]


def read_json(path: Path) -> list[dict]:
    body = json.loads(path.read_text())
    rows = body.get("slots") if isinstance(body, dict) else body
    if not isinstance(rows, list):
        raise SystemExit(f"{path} is neither a list of slots nor {{'slots': [...]}}")
    return [{k: r.get(k) for k in FIELDS} for r in rows]


def load(path: Path) -> list[dict]:
    if not path.exists():
        raise SystemExit(f"Missing {path}")
    return read_csv(path) if path.suffix.lower() == ".csv" else read_json(path)


def show(slots: list[dict]) -> None:
    by_day: dict[str, list[dict]] = defaultdict(list)
    for s in slots:
        by_day[s.get("day") or "(no day)"].append(s)
    for day in sorted(by_day):
        print(f"## {day} ({len(by_day[day])})")
        for s in by_day[day]:
            when = "-".join(t for t in (s.get("start_time"), s.get("end_time")) if t) or "(no time)"
            print(f"  {when:>13}  {s.get('stage') or '(no stage)'}: {s.get('title')}")
        print()
    print(f"{len(slots)} slots across {len(by_day)} days.")


def put(api: str, event_id: str, slots: list[dict]) -> dict:
    request = urllib.request.Request(
        f"{api.rstrip('/')}/events/{event_id}/schedule",
        data=json.dumps({"slots": slots}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="PUT",
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as exc:
        detail = json.loads(exc.read() or b"{}").get("detail", exc.reason)
        raise SystemExit(f"{exc.code} from {api}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Cannot reach {api}: {exc.reason}") from exc


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("event_id", help="id from GET /events")
    parser.add_argument("path", type=Path, help="CSV with a day,stage,title,start_time,end_time header, or JSON")
    parser.add_argument("--api", default="http://127.0.0.1:8000")
    parser.add_argument("--dry-run", action="store_true", help="print the parsed slots and send nothing")
    args = parser.parse_args()

    slots = load(args.path)
    if args.dry_run:
        show(slots)
        return
    result = put(args.api, args.event_id, slots)
    print(f"{result['count']} slots on {args.event_id} across {len(result['days'])} days: {', '.join(result['days'])}")


if __name__ == "__main__":
    main()
