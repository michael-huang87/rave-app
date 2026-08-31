"""ETL linking rules. Covers the two branches that carry the misattribution risk."""

from __future__ import annotations

from collections import Counter
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from clean_sheet import derive_events_from_sets, link_sets  # noqa: E402


def event(eid, show, venue, start, end=None, source="sheet"):
    return {
        "id": eid,
        "show": show,
        "venue": venue,
        "city": None,
        "year": int(start[:4]),
        "start_date": start,
        "end_date": end or start,
        "source": source,
    }


def set_row(title, show, venue, day):
    return {"title": title, "show": show, "venue": venue, "date": day, "year": int(day[:4])}


def test_venue_beats_a_lone_show_match():
    """Five 'EDC Preparty' sets on 2024-05-16 span two rooms; only venue tells them apart."""
    ebc = event("ebc", "EDC Las Vegas Preparty X", "EBC at Night", "2024-05-16")
    liv = event("liv", "Said the Sky | WB | Trivecta", "LIV Beach", "2024-05-16")
    sets = [
        set_row("Said the Sky", "EDC Preparty", "LIV Beach", "2024-05-16"),
        set_row("Trivecta", "EDC Preparty", "LIV Beach", "2024-05-16"),
        set_row("William Black", "EDC Preparty", "LIV Beach", "2024-05-16"),
        set_row("Excision", "EDC Preparty", "EBC at Night", "2024-05-16"),
        set_row("Armnhmr", "EDC Preparty", "EBC at Night", "2024-05-16"),
    ]
    linked, unmatched = link_sets([ebc, liv], sets)
    assert unmatched == []
    assert Counter(s["event_id"] for s in linked) == {"liv": 3, "ebc": 2}


def test_year_straddling_group_merges_into_its_cost_row():
    """Countdown NYE runs Dec 30 to Jan 1, so money and sets land on different sheet tabs."""
    cost_row = event("nye", "Countdown NYE", "NOS Event Center", "2023-01-01")
    sets = [
        set_row("Zedd", "Countdown NYE", "NOS Event Center", "2022-12-30"),
        set_row("Slander", "Countdown NYE", "NOS Event Center", "2022-12-31"),
    ]
    derived = derive_events_from_sets(sets, [cost_row])
    assert derived == []
    assert {s["event_id"] for s in sets} == {"nye"}


def test_a_group_with_no_nearby_cost_row_still_derives_an_event():
    """2022 has no cost tab at all; those events must still be invented."""
    sets = [set_row("Excision", "Lost Lands", "Legend Valley", "2022-09-23")]
    derived = derive_events_from_sets(sets, [])
    assert len(derived) == 1
    assert derived[0]["source"] == "derived_from_sets"
    assert sets[0]["event_id"] == derived[0]["id"]


def test_last_resort_refuses_a_contradicting_venue():
    """The date-blind fallback once carried a set six months onto the wrong show."""
    tahoe = event("tahoe", "John Summit", "Tahoe Blue Event Center", "2025-02-22")
    stray = set_row("John Summit", "John Summit", "LIV Beach", "2025-08-30")
    linked, unmatched = link_sets([tahoe], [stray])
    assert unmatched == [stray]
    assert linked[0].get("event_id") is None


def test_last_resort_still_links_a_set_with_no_venue():
    """Refusing on a missing venue would strand sets that contradict nothing."""
    tahoe = event("tahoe", "John Summit", "Tahoe Blue Event Center", "2025-02-22")
    loose = set_row("John Summit", "John Summit", None, "2025-08-30")
    linked, unmatched = link_sets([tahoe], [loose])
    assert unmatched == []
    assert linked[0]["event_id"] == "tahoe"
