#!/usr/bin/env python3
"""Print every remaining data discrepancy in data/*.json for a human to adjudicate.

Read-only. Re-run after editing the sheet or the ETL to see the lists shrink.
Alias knowledge is imported from clean_sheet rather than copied, so "known alias"
means exactly what the linker means by it.
"""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(ROOT / "backend"))

from clean_sheet import find_host_event, venues_compatible  # noqa: E402
from main import NOT_ATTENDED_MARKERS  # noqa: E402


def load(name: str) -> list[dict]:
    path = DATA / name
    if not path.exists():
        raise SystemExit(f"Missing {path}. Run scripts/clean_sheet.py first.")
    return json.loads(path.read_text())


def where(e: dict) -> str:
    return f"{e['show']} @ {e.get('venue') or '(no venue)'}"


def main() -> None:
    events = load("events.json")
    sets = load("sets.json")
    by_id = {e["id"]: e for e in events}
    linked = Counter(s["event_id"] for s in sets)
    by_event = defaultdict(list)
    for s in sets:
        by_event[s["event_id"]].append(s)
    today = date.today().isoformat()
    sections: list[tuple[str, list[str]]] = []

    rows = []
    for e in sorted(events, key=lambda x: x.get("start_date") or ""):
        sheet, got = e.get("sets_sheet") or 0, linked.get(e["id"], 0)
        if sheet != got:
            rows.append(f"  {e.get('start_date')}  sheet={sheet:>2} linked={got:>2}  {where(e)}")
    sections.append(("Sheet count != linked count", rows))

    rows = []
    for e in sorted(events, key=lambda x: x.get("start_date") or ""):
        last = e.get("end_date") or e.get("start_date")
        if linked.get(e["id"], 0) or not last or last > today:
            continue
        if any(m in e["show"].lower() for m in NOT_ATTENDED_MARKERS):
            continue
        rows.append(f"  {e.get('start_date')}  sheet={e.get('sets_sheet') or 0:>2}  {where(e)}")
        for s in sets:
            if s.get("date") == e.get("start_date"):
                host = by_id.get(s["event_id"], {})
                rows.append(
                    f"      same-day set {s['title']!r} show={s.get('show')!r} "
                    f"venue={s.get('venue')!r} -> {host.get('show', '?')}"
                )
    sections.append(("Past events with zero linked sets", rows))

    rows = []
    for s in sorted(sets, key=lambda x: x.get("date") or ""):
        e = by_id.get(s["event_id"])
        if not e or not s.get("venue") or not e.get("venue"):
            continue
        if not venues_compatible(e.get("venue"), s.get("venue")):
            rows.append(
                f"  {s.get('date')}  {s['title']!r}: set says {s['venue']!r}, "
                f"event says {e['venue']!r} ({e['show']})"
            )
    sections.append(("Set venue contradicts event venue, not a known alias", rows))

    rows = [
        f"  {e.get('start_date')}  {e['show']}  (linked={linked.get(e['id'], 0)})"
        for e in sorted(events, key=lambda x: x.get("start_date") or "")
        if not e.get("venue")
    ]
    sections.append(("Events with no venue", rows))

    rows = []
    for e in events:
        if e.get("source") != "derived_from_sets":
            continue
        host = find_host_event(events, e, e.get("start_date"), e.get("end_date"))
        if host:
            rows.append(f"  {e.get('start_date')}  {where(e)}  vs sheet row {host.get('start_date')}")
    sections.append(("Derived-from-Sets events that duplicate a Costs row", rows))

    rows = [
        f"  {s.get('date')}  {s['title']!r} event_id={s.get('event_id')!r}"
        for s in sets
        if not s.get("event_id") or not s.get("date")
    ]
    sections.append(("Sets with no event or no date", rows))

    print(f"Rave reconciliation — {len(events)} events, {len(sets)} sets, as of {today}\n")
    for title, rows in sections:
        indented = sum(1 for r in rows if r.startswith("      "))
        print(f"## {title} ({len(rows) - indented})")
        for r in rows:
            print(r)
        print()
    total = sum(len(r) - sum(1 for x in r if x.startswith("      ")) for _, r in sections)
    print(f"{len(sections)} categories, {total} items to adjudicate.")


if __name__ == "__main__":
    main()
