from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from main import recap_bucket  # noqa: E402


def _event(**kwargs) -> dict:
    row = {
        "id": "e",
        "show": "Show",
        "venue": "Venue",
        "city": "City",
        "year": 2025,
        "ticket": 0,
        "travel": 0,
        "drinks_food_merch": 0,
        "sets_logged": 0,
    }
    row.update(kwargs)
    row["total"] = round(row["ticket"] + row["travel"] + row["drinks_food_merch"], 2)
    n = row["sets_logged"]
    row["dollars_per_set"] = round(row["total"] / n, 2) if n else None
    return row


def _set_row(**kwargs) -> dict:
    row = {
        "id": "s",
        "event_id": "e",
        "title": "Set",
        "show": "Show",
        "city": "City",
        "year": 2025,
        "date": "2025-01-01",
        "artists": ["A"],
    }
    row.update(kwargs)
    return row


def test_year_slices_do_not_leak():
    e24 = _event(id="e24", show="2024 Show", year=2024, city="Austin, TX", ticket=11, sets_logged=1)
    e25 = _event(id="e25", show="2025 Show", year=2025, city="Miami, FL", ticket=22, sets_logged=1)
    s24 = _set_row(
        id="s24",
        event_id="e24",
        year=2024,
        city="Austin, TX",
        date="2024-03-01",
        artists=["Vintage"],
        show="2024 Show",
    )
    s25 = _set_row(
        id="s25",
        event_id="e25",
        year=2025,
        city="Miami, FL",
        date="2025-03-01",
        artists=["Current"],
        show="2025 Show",
    )
    y24 = recap_bucket([e24], [s24])
    y25 = recap_bucket([e25], [s25])
    assert y24["top_artist"] == {"name": "Vintage", "count": 1}
    assert y24["top_city"] == {"name": "Austin, TX", "count": 1}
    assert y24["spend"] == 11
    assert y24["most_sets"] == {"name": "2024 Show", "count": 1}
    assert y25["top_artist"] == {"name": "Current", "count": 1}
    assert y25["top_city"] == {"name": "Miami, FL", "count": 1}
    assert y25["spend"] == 22
    assert y25["most_sets"] == {"name": "2025 Show", "count": 1}


def test_top_artist_is_set_count_not_spend():
    cheap = _event(id="c", show="Cheap Night", ticket=5, sets_logged=2)
    pricey = _event(id="p", show="Pricey Night", ticket=900, sets_logged=1)
    sets = [
        _set_row(id="s1", event_id="c", artists=["Cheap Artist"], date="2025-01-01"),
        _set_row(id="s2", event_id="c", artists=["Cheap Artist"], date="2025-01-02"),
        _set_row(id="s3", event_id="p", artists=["Pricey Artist"], date="2025-01-03"),
    ]
    bucket = recap_bucket([cheap, pricey], sets)
    assert bucket["top_artist"] == {"name": "Cheap Artist", "count": 2}


def test_top_city_uses_distinct_set_dates_not_events():
    fest = _event(id="a", show="Fest", city="City A", sets_logged=2)
    club1 = _event(id="b1", show="Club 1", city="City B", sets_logged=1)
    club2 = _event(id="b2", show="Club 2", city="City B", sets_logged=1)
    sets = [
        _set_row(id="s1", event_id="a", city="City A", date="2025-06-01", artists=["X"]),
        _set_row(id="s2", event_id="a", city="City A", date="2025-06-02", artists=["Y"]),
        _set_row(id="s3", event_id="b1", city="City B", date="2025-07-01", artists=["Z"]),
        _set_row(id="s4", event_id="b2", city="City B", date="2025-07-01", artists=["W"]),
    ]
    bucket = recap_bucket([fest, club1, club2], sets)
    assert bucket["top_city"] == {"name": "City A", "count": 2}
    city_by_events = {}
    for e in (fest, club1, club2):
        city_by_events[e["city"]] = city_by_events.get(e["city"], 0) + 1
    assert city_by_events["City B"] > city_by_events["City A"]


def test_most_sets_is_the_event_not_grouped_show_names():
    a = _event(id="ll-2024", show="Lost Lands", year=2024, sets_logged=3)
    b = _event(id="ll-2025", show="Lost Lands", year=2025, sets_logged=5)
    c = _event(id="edc", show="EDC", year=2025, sets_logged=4)
    bucket = recap_bucket([a, b, c], [])
    assert bucket["most_sets"] == {"name": "Lost Lands", "count": 5}


def test_best_dollars_per_set_excludes_free_shows():
    free = _event(id="free", show="Free Fest", ticket=0, travel=0, drinks_food_merch=0, sets_logged=40)
    paid = _event(id="paid", show="Paid Club", ticket=80, travel=0, drinks_food_merch=0, sets_logged=2)
    bucket = recap_bucket([free, paid], [])
    assert free["total"] == 0
    assert bucket["best_dollars_per_set"] == {"name": "Paid Club", "dollars_per_set": 40.0}
    assert bucket["most_sets"] == {"name": "Free Fest", "count": 40}


def test_spend_by_type_sums_to_spend():
    evs = [
        _event(id="a", ticket=10.1, travel=2.2, drinks_food_merch=3.3),
        _event(id="b", ticket=0, travel=4.4, drinks_food_merch=0),
    ]
    bucket = recap_bucket(evs, [])
    sbt = bucket["spend_by_type"]
    assert sbt == {"ticket": 10.1, "travel": 6.6, "drinks_food_merch": 3.3}
    assert bucket["spend"] == 20.0
    assert round(sbt["ticket"] + sbt["travel"] + sbt["drinks_food_merch"], 2) == bucket["spend"]
