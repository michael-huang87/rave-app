"""API tests. Snapshot assertions run only when data/events.json exists locally."""

from __future__ import annotations

import json
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
SNAPSHOT = ROOT / "data" / "events.json"
SETS_SNAPSHOT = ROOT / "data" / "sets.json"


def snapshot(path: Path) -> list[dict]:
    return json.loads(path.read_text())
needs_snapshot = pytest.mark.skipif(
    not SNAPSHOT.exists(), reason="local data/events.json not generated"
)


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("RAVE_DB", str(tmp_path / "rave.db"))
    import importlib

    import main as mainmod

    importlib.reload(mainmod)
    from fastapi.testclient import TestClient

    with TestClient(mainmod.app) as c:
        yield c


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["ok"] is True


@needs_snapshot
def test_list_events_seeded(client):
    r = client.get("/events")
    assert r.status_code == 200
    events = r.json()
    assert len(events) >= 200
    row = events[0]
    for key in ("id", "show", "ticket", "travel", "drinks_food_merch", "total", "status", "sets_logged"):
        assert key in row


@needs_snapshot
def test_event_detail_includes_sets_and_spend(client):
    """Counts come from the snapshot, not literals: the sheet changes, the contract does not."""
    source = next(e for e in snapshot(SNAPSHOT) if e["show"] == "EDC Las Vegas" and e["year"] == 2026)
    expected_sets = sum(1 for s in snapshot(SETS_SNAPSHOT) if s["event_id"] == source["id"])
    detail = client.get(f"/events/{source['id']}").json()
    assert detail["sets_logged"] == expected_sets
    assert len(detail["sets"]) == expected_sets
    assert detail["ticket"] == source["ticket"]
    assert detail["travel"] == source["travel"]
    assert abs(detail["total"] - (source["ticket"] + source["travel"] + source["drinks_food_merch"])) < 0.01
    assert detail["sets"][0]["title"]
    assert "artists" in detail["sets"][0]


@needs_snapshot
def test_list_sets(client):
    r = client.get("/sets")
    assert r.status_code == 200
    assert len(r.json()) == len(snapshot(SETS_SNAPSHOT))


@needs_snapshot
def test_recap(client):
    sets = snapshot(SETS_SNAPSHOT)
    recap = client.get("/recap").json()
    assert recap["all_time"]["sets"] == len(sets)
    assert recap["all_time"]["set_titles"] == len({s["title"] for s in sets})
    for year, bucket in recap["by_year"].items():
        assert bucket["sets"] == sum(1 for s in sets if str(s.get("year")) == year)
    assert sum(b["sets"] for b in recap["by_year"].values()) == len(sets)


def test_create_event_log_set_and_spend(client):
    created = client.post(
        "/events",
        json={
            "show": "Smoke Test Showcase",
            "venue": "Warehouse",
            "city": "Oakland, CA",
            "start_date": "2099-01-01",
            "ticket": 40,
        },
    )
    assert created.status_code == 201
    eid = created.json()["id"]
    assert created.json()["status"] == "planned"
    spend = client.patch(
        f"/events/{eid}/spend",
        json={"ticket": 40, "travel": 12.5, "drinks_food_merch": 8},
    )
    assert spend.status_code == 200
    assert spend.json()["total"] == 60.5
    logged = client.post(
        f"/events/{eid}/sets",
        json={"title": "Test Artist b2b Other", "artists": ["Test Artist", "Other"], "date": "2099-01-01"},
    )
    assert logged.status_code == 201
    assert logged.json()["venue"] == "Warehouse"
    detail = client.get(f"/events/{eid}").json()
    assert detail["sets_logged"] == 1
    assert detail["dollars_per_set"] == 60.5


def test_status_is_date_based(client):
    past = client.post("/events", json={"show": "Past Show", "start_date": "2020-01-01"})
    assert past.json()["status"] == "attended"
    for name in ("Ghost Fest (Cancelled)", "Bailed Fest (Skipped)"):
        off = client.post("/events", json={"show": name, "start_date": "2020-01-01"})
        assert off.json()["status"] == "skipped", name


def test_reload_snapshot_refuses_to_drop_hand_entered_rows(client):
    created = client.post("/events", json={"show": "Hand Entered", "start_date": "2020-01-01"})
    assert created.status_code == 201
    blocked = client.post("/admin/reload-snapshot")
    assert blocked.status_code == 409
    assert "would be lost" in blocked.json()["detail"]
    assert client.get(f"/events/{created.json()['id']}").status_code == 200
    assert client.post("/admin/reload-snapshot?force=true").status_code == 200
    assert client.get(f"/events/{created.json()['id']}").status_code == 404


@needs_snapshot
def test_sets_come_back_in_sheet_order(client):
    """The sheet's row order is the order the sets were seen; alphabetical destroyed it."""
    sets = client.get("/sets").json()
    by_id = {s["id"]: s.get("sheet_row") for s in snapshot(SETS_SNAPSHOT)}

    dates = [s["date"] for s in sets]
    assert dates == sorted(dates, reverse=True), "days should stay newest-first"

    for day in ("2026-05-17", "2025-10-25"):
        rows = [by_id[s["id"]] for s in sets if s["date"] == day]
        assert len(rows) > 1, f"{day} needs several sets to be worth checking"
        assert rows == sorted(rows), f"{day} lost sheet order"
        titles = [s["title"] for s in sets if s["date"] == day]
        assert titles != sorted(titles), f"{day} is still alphabetical"


@needs_snapshot
def test_hand_logged_set_sorts_after_the_sheet_rows_of_its_day(client):
    """A set logged in the app has no sheet_row; it belongs at the end of its night, not the start."""
    event = client.get("/events").json()[-1]
    day = client.get(f"/sets?event_id={event['id']}").json()
    assert day, "picked an event with no sets"

    client.post(
        f"/events/{event['id']}/sets",
        json={"title": "AAA Encore", "artists": ["AAA Encore"], "date": day[0]["date"]},
    )
    same_day = [s["title"] for s in client.get(f"/sets?event_id={event['id']}").json() if s["date"] == day[0]["date"]]
    assert same_day[-1] == "AAA Encore", same_day


@needs_snapshot
def test_stats_match_the_sheets_own_analytics(client):
    """Venue/city counts are distinct set-dates, the way ArtistsVenues computes them."""
    stats = client.get("/stats").json()
    venues = {v["name"]: v["count"] for v in stats["venues"]}
    cities = {c["name"]: c["count"] for c in stats["cities"]}

    # Straight from the sheet's ArtistsVenues tab.
    assert venues["Bill Graham"] == 37
    assert venues["Midway"] == 23
    assert venues["Oakland Arena"] == 9
    assert cities["San Francisco, CA"] == 74
    assert cities["Las Vegas, NV"] == 26
    assert stats["artists"][0] == {"name": "Subtronics", "count": 26}

    for key in ("artists", "venues", "cities"):
        counts = [x["count"] for x in stats[key]]
        assert counts == sorted(counts, reverse=True), f"{key} not ranked"

    sets = snapshot(SETS_SNAPSHOT)
    assert len(cities) == len({s["city"].strip().lower() for s in sets if s.get("city")})
