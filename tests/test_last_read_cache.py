"""Contract tests for the last-read cache file layout (matches LastReadStore.swift)."""

from __future__ import annotations

from pathlib import Path

from last_read_cache import filename, load, save


def test_filename_keys():
    assert filename("events") == "events.json"
    assert filename("sets") == "sets.json"
    assert filename("recap") == "recap.json"
    assert filename("stats") == "stats.json"
    assert filename("event", "abc123") == "event-abc123.json"


def test_event_id_sanitizes_path_chars():
    assert filename("event", "a/b:c") == "event-a_b_c.json"


def test_save_then_load_roundtrip(tmp_path: Path):
    payload = {
        "id": "e1",
        "show": "EDC Las Vegas",
        "ticket": 1005.08,
        "travel": 430.8,
        "drinks_food_merch": 0,
        "total": 1435.88,
        "sets": [{"title": "1991", "artists": ["1991"]}],
    }
    save(tmp_path, "event", payload, event_id="e1")
    hit = load(tmp_path, "event", event_id="e1")
    assert hit is not None
    assert "saved_at" in hit
    assert hit["payload"]["show"] == "EDC Las Vegas"
    assert hit["payload"]["sets"][0]["title"] == "1991"
    assert hit["payload"]["ticket"] == 1005.08


def test_overwrite_keeps_latest(tmp_path: Path):
    save(tmp_path, "events", [{"id": "1", "show": "Old"}])
    save(tmp_path, "events", [{"id": "1", "show": "New"}])
    hit = load(tmp_path, "events")
    assert hit["payload"][0]["show"] == "New"


def test_missing_key_is_none(tmp_path: Path):
    assert load(tmp_path, "recap") is None


def test_list_and_recap_keys(tmp_path: Path):
    save(tmp_path, "events", [{"id": "1"}])
    save(tmp_path, "recap", {"all_time": {"sets": 3, "spend": 10}})
    save(tmp_path, "stats", {"artists": [{"name": "Subtronics", "count": 26}]})
    assert load(tmp_path, "events")["payload"][0]["id"] == "1"
    assert load(tmp_path, "recap")["payload"]["all_time"]["sets"] == 3
    assert load(tmp_path, "stats")["payload"]["artists"][0]["name"] == "Subtronics"
