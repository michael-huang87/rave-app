"""API tests. Snapshot assertions run only when data/events.json exists locally."""

from __future__ import annotations

from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
SNAPSHOT = ROOT / "data" / "events.json"
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
    events = client.get("/events").json()
    edc = next(e for e in events if e["show"] == "EDC Las Vegas" and e["year"] == 2026)
    detail = client.get(f"/events/{edc['id']}").json()
    assert detail["sets_logged"] == 41
    assert detail["ticket"] == 1005.08
    assert detail["travel"] == 430.8
    assert abs(detail["total"] - 1435.88) < 0.01
    assert len(detail["sets"]) == 41
    assert detail["sets"][0]["title"]
    assert "artists" in detail["sets"][0]


@needs_snapshot
def test_list_sets(client):
    r = client.get("/sets")
    assert r.status_code == 200
    sets = r.json()
    assert len(sets) == 1241


@needs_snapshot
def test_recap(client):
    recap = client.get("/recap").json()
    assert recap["all_time"]["sets"] == 1241
    assert recap["all_time"]["set_titles"] == 705
    assert recap["by_year"]["2025"]["sets"] == 472
    assert recap["by_year"]["2025"]["shows"] == 56


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
    off = client.post("/events", json={"show": "Ghost Fest (Cancelled)", "start_date": "2020-01-01"})
    assert off.json()["status"] == "cancelled"
