#!/usr/bin/env python3
"""Thin single-user API for Rave v1. Seeds from data/*.json."""

from __future__ import annotations

import json
import os
import sqlite3
from contextlib import asynccontextmanager, contextmanager
from datetime import date
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
DB_PATH = Path(os.environ.get("RAVE_DB", Path(__file__).resolve().parent / "rave.db"))


@asynccontextmanager
async def lifespan(_: FastAPI):
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with db() as conn:
        init_schema(conn)
        seed_if_empty(conn)
    yield


app = FastAPI(title="Rave", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


@contextmanager
def db():
    conn = connect()
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS events (
            id TEXT PRIMARY KEY,
            show TEXT NOT NULL,
            venue TEXT,
            city TEXT,
            year INTEGER,
            start_date TEXT,
            end_date TEXT,
            date_display TEXT,
            ticket REAL NOT NULL DEFAULT 0,
            travel REAL NOT NULL DEFAULT 0,
            drinks_food_merch REAL NOT NULL DEFAULT 0,
            sets_sheet INTEGER NOT NULL DEFAULT 0,
            source TEXT,
            source_tab TEXT
        );
        CREATE TABLE IF NOT EXISTS sets (
            id TEXT PRIMARY KEY,
            event_id TEXT NOT NULL,
            title TEXT NOT NULL,
            show TEXT,
            venue TEXT,
            city TEXT,
            year INTEGER,
            date TEXT,
            sheet_row INTEGER,
            artists_json TEXT NOT NULL DEFAULT '[]',
            FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE
        );
        """
    )
    # A DB created before sheet_row existed still holds hand-entered rows worth keeping,
    # so widen it in place rather than making anyone delete rave.db.
    cols = {r["name"] for r in conn.execute("PRAGMA table_info(sets)")}
    if "sheet_row" not in cols:
        conn.execute("ALTER TABLE sets ADD COLUMN sheet_row INTEGER")
        backfill_sheet_rows(conn)


def backfill_sheet_rows(conn: sqlite3.Connection) -> None:
    """Set ids already encode the sheet row, so this joins exactly rather than guessing."""
    sets_path = DATA / "sets.json"
    if not sets_path.exists():
        return
    conn.executemany(
        "UPDATE sets SET sheet_row = ? WHERE id = ? AND sheet_row IS NULL",
        [(s.get("sheet_row"), s["id"]) for s in json.loads(sets_path.read_text())],
    )


def money(value: Any) -> float:
    try:
        return round(float(value or 0), 2)
    except (TypeError, ValueError):
        return 0.0


# One bucket for "did not go", however it happened. Marked in the show name
# because the sheet has no status column.
NOT_ATTENDED_MARKERS = ("(cancelled)", "(skipped)")

# The sheet lists a night's sets in the order you saw them, so sheet_row is the only
# time signal there is. Hand-logged sets have none and sort to the end of their day.
SET_ORDER = "COALESCE(sheet_row, 1000000)"


def status_for(show: str, start: str | None, end: str | None) -> str:
    lowered = (show or "").lower()
    if any(m in lowered for m in NOT_ATTENDED_MARKERS):
        return "skipped"
    last = end or start
    return "attended" if last and date.fromisoformat(last) <= date.today() else "planned"


def shape_event(row: sqlite3.Row, sets_count: int) -> dict:
    ticket, travel, merch = money(row["ticket"]), money(row["travel"]), money(row["drinks_food_merch"])
    total = round(ticket + travel + merch, 2)
    return {
        "id": row["id"],
        "show": row["show"],
        "venue": row["venue"],
        "city": row["city"],
        "year": row["year"],
        "start_date": row["start_date"],
        "end_date": row["end_date"],
        "date_display": row["date_display"],
        "ticket": ticket,
        "travel": travel,
        "drinks_food_merch": merch,
        "total": total,
        "sets_logged": sets_count,
        "sets_sheet": row["sets_sheet"],
        "dollars_per_set": round(total / sets_count, 2) if sets_count else None,
        "status": status_for(row["show"], row["start_date"], row["end_date"]),
        "source": row["source"],
        "source_tab": row["source_tab"],
    }


def shape_set(row: sqlite3.Row) -> dict:
    artists = json.loads(row["artists_json"] or "[]")
    return {
        "id": row["id"],
        "event_id": row["event_id"],
        "title": row["title"],
        "show": row["show"],
        "venue": row["venue"],
        "city": row["city"],
        "year": row["year"],
        "date": row["date"],
        "artists": artists,
    }


def new_id(*parts: object) -> str:
    import hashlib

    raw = "|".join("" if p is None else str(p) for p in parts)
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:12]


def seed_if_empty(conn: sqlite3.Connection) -> None:
    n = conn.execute("SELECT COUNT(*) AS c FROM events").fetchone()["c"]
    if n:
        return
    events_path = DATA / "events.json"
    sets_path = DATA / "sets.json"
    if not events_path.exists() or not sets_path.exists():
        return
    events = json.loads(events_path.read_text())
    sets = json.loads(sets_path.read_text())
    for e in events:
        conn.execute(
            """INSERT INTO events
               (id, show, venue, city, year, start_date, end_date, date_display,
                ticket, travel, drinks_food_merch, sets_sheet, source, source_tab)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                e["id"],
                e["show"],
                e.get("venue"),
                e.get("city"),
                e.get("year"),
                e.get("start_date"),
                e.get("end_date"),
                e.get("date_display"),
                e.get("ticket") or 0,
                e.get("travel") or 0,
                e.get("drinks_food_merch") or 0,
                e.get("sets_sheet") or 0,
                e.get("source"),
                e.get("source_tab"),
            ),
        )
    for s in sets:
        conn.execute(
            """INSERT INTO sets
               (id, event_id, title, show, venue, city, year, date, sheet_row, artists_json)
               VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (
                s["id"],
                s["event_id"],
                s.get("title") or "",
                s.get("show"),
                s.get("venue"),
                s.get("city"),
                s.get("year"),
                s.get("date"),
                s.get("sheet_row"),
                json.dumps(s.get("artists") or []),
            ),
        )


class EventIn(BaseModel):
    show: str
    venue: str | None = None
    city: str | None = None
    year: int | None = None
    start_date: str | None = None
    end_date: str | None = None
    date_display: str | None = None
    ticket: float = 0
    travel: float = 0
    drinks_food_merch: float = 0


class EventPatch(BaseModel):
    show: str | None = None
    venue: str | None = None
    city: str | None = None
    year: int | None = None
    start_date: str | None = None
    end_date: str | None = None
    date_display: str | None = None


class SpendIn(BaseModel):
    ticket: float | None = None
    travel: float | None = None
    drinks_food_merch: float | None = Field(default=None, alias="drinks_food_merch")

    model_config = {"populate_by_name": True}


class SetIn(BaseModel):
    title: str
    artists: list[str] = []
    date: str | None = None
    year: int | None = None


def event_with_count(conn: sqlite3.Connection, event_id: str) -> dict:
    row = conn.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
    if not row:
        raise HTTPException(404, "event not found")
    n = conn.execute("SELECT COUNT(*) AS c FROM sets WHERE event_id = ?", (event_id,)).fetchone()["c"]
    return shape_event(row, n)


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.get("/events")
def list_events(status: str | None = None, year: int | None = None) -> list[dict]:
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM events ORDER BY start_date DESC, show COLLATE NOCASE"
        ).fetchall()
        counts = {
            r["event_id"]: r["c"]
            for r in conn.execute("SELECT event_id, COUNT(*) AS c FROM sets GROUP BY event_id")
        }
        out = [shape_event(r, counts.get(r["id"], 0)) for r in rows]
    if year is not None:
        out = [e for e in out if e.get("year") == year]
    if status:
        out = [e for e in out if e.get("status") == status]
    return out


@app.get("/events/{event_id}")
def get_event(event_id: str) -> dict:
    with db() as conn:
        event = event_with_count(conn, event_id)
        sets = [
            shape_set(r)
            for r in conn.execute(
                f"SELECT * FROM sets WHERE event_id = ? ORDER BY date, {SET_ORDER}", (event_id,)
            )
        ]
        event["sets"] = sets
        return event


@app.post("/events", status_code=201)
def create_event(body: EventIn) -> dict:
    eid = new_id("evt", body.show, body.start_date, body.venue)
    display = body.date_display or body.start_date or ""
    year = body.year
    if year is None and body.start_date:
        year = int(body.start_date[:4])
    with db() as conn:
        conn.execute(
            """INSERT INTO events
               (id, show, venue, city, year, start_date, end_date, date_display,
                ticket, travel, drinks_food_merch, source, source_tab)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                eid,
                body.show.strip(),
                body.venue,
                body.city,
                year,
                body.start_date,
                body.end_date or body.start_date,
                display,
                money(body.ticket),
                money(body.travel),
                money(body.drinks_food_merch),
                "user",
                None,
            ),
        )
        return event_with_count(conn, eid)


@app.patch("/events/{event_id}")
def patch_event(event_id: str, body: EventPatch) -> dict:
    data = body.model_dump(exclude_unset=True)
    if not data:
        with db() as conn:
            return event_with_count(conn, event_id)
    fields = []
    values: list[Any] = []
    for key, val in data.items():
        fields.append(f"{key} = ?")
        values.append(val.strip() if isinstance(val, str) else val)
    values.append(event_id)
    with db() as conn:
        cur = conn.execute(f"UPDATE events SET {', '.join(fields)} WHERE id = ?", values)
        if cur.rowcount == 0:
            raise HTTPException(404, "event not found")
        return event_with_count(conn, event_id)


@app.patch("/events/{event_id}/spend")
def log_spend(event_id: str, body: SpendIn) -> dict:
    with db() as conn:
        row = conn.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
        if not row:
            raise HTTPException(404, "event not found")
        ticket = money(row["ticket"] if body.ticket is None else body.ticket)
        travel = money(row["travel"] if body.travel is None else body.travel)
        merch = money(row["drinks_food_merch"] if body.drinks_food_merch is None else body.drinks_food_merch)
        conn.execute(
            "UPDATE events SET ticket = ?, travel = ?, drinks_food_merch = ? WHERE id = ?",
            (ticket, travel, merch, event_id),
        )
        return event_with_count(conn, event_id)


@app.post("/events/{event_id}/sets", status_code=201)
def log_set(event_id: str, body: SetIn) -> dict:
    with db() as conn:
        event = conn.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
        if not event:
            raise HTTPException(404, "event not found")
        artists = body.artists or [body.title]
        artists = [a.strip() for a in artists if a and a.strip()]
        sid = new_id("set", event_id, body.title, body.date, len(artists))
        conn.execute(
            """INSERT INTO sets
               (id, event_id, title, show, venue, city, year, date, artists_json)
               VALUES (?,?,?,?,?,?,?,?,?)""",
            (
                sid,
                event_id,
                body.title.strip(),
                event["show"],
                event["venue"],
                event["city"],
                body.year or event["year"],
                body.date or event["start_date"],
                json.dumps(artists),
            ),
        )
        row = conn.execute("SELECT * FROM sets WHERE id = ?", (sid,)).fetchone()
        return shape_set(row)


@app.get("/sets")
def list_sets(event_id: str | None = None) -> list[dict]:
    with db() as conn:
        if event_id:
            rows = conn.execute(
                f"SELECT * FROM sets WHERE event_id = ? ORDER BY date DESC, {SET_ORDER}", (event_id,)
            ).fetchall()
        else:
            rows = conn.execute(f"SELECT * FROM sets ORDER BY date DESC, {SET_ORDER}").fetchall()
        return [shape_set(r) for r in rows]


def rank(pairs: list[tuple[str, object]]) -> list[dict]:
    """pairs are (display name, thing counted). Groups case-insensitively, keeps first casing."""
    seen: dict[str, set] = {}
    display: dict[str, str] = {}
    for name, item in pairs:
        key = " ".join((name or "").split()).lower()
        if not key:
            continue
        seen.setdefault(key, set()).add(item)
        display.setdefault(key, name.strip())
    counts = [{"name": display[k], "count": len(v)} for k, v in seen.items()]
    return sorted(counts, key=lambda c: (-c["count"], c["name"].lower()))


@app.get("/stats")
def stats() -> dict:
    """Artist / venue / city rankings, matching the sheet's ArtistsVenues tab.

    The sheet counts a venue or city by distinct dates in the Sets tab, not by event
    (COUNTUNIQUEIFS over Sets[Date]), so a two-day festival at one venue is two visits
    and a venue with no logged sets does not appear at all.
    """
    with db() as conn:
        rows = conn.execute("SELECT venue, city, date, artists_json FROM sets").fetchall()

    artists: list[tuple[str, object]] = []
    venues: list[tuple[str, object]] = []
    cities: list[tuple[str, object]] = []
    for i, r in enumerate(rows):
        # A set is counted once per artist, so the unit is the row itself, not the date.
        for a in json.loads(r["artists_json"] or "[]"):
            if a and a.strip():
                artists.append((a, i))
        if r["venue"]:
            venues.append((r["venue"], r["date"]))
        if r["city"]:
            cities.append((r["city"], r["date"]))

    return {"artists": rank(artists), "venues": rank(venues), "cities": rank(cities)}


@app.get("/recap")
def recap() -> dict:
    with db() as conn:
        events = conn.execute("SELECT * FROM events").fetchall()
        sets = conn.execute("SELECT * FROM sets").fetchall()

    shaped_sets = [shape_set(s) for s in sets]
    counts = {}
    for s in shaped_sets:
        counts[s["event_id"]] = counts.get(s["event_id"], 0) + 1
    shaped_events = [shape_event(e, counts.get(e["id"], 0)) for e in events]

    def recap_for(evs, sts):
        names: list[str] = []
        for s in sts:
            names.extend(s.get("artists") or [])
        return {
            "sets": len(sts),
            "artists": len({n.strip().lower() for n in names if n.strip()}),
            "set_titles": len({s["title"] for s in sts if s.get("title")}),
            "shows": len({s["show"] for s in sts if s.get("show")}),
            "events": len(evs),
            "venues": len({e["venue"] for e in evs if e.get("venue")}),
            "cities": len({e["city"] for e in evs if e.get("city")}),
            "spend": round(sum(e["total"] for e in evs), 2),
        }

    years = sorted({e.get("year") for e in shaped_events if e.get("year")})
    by_year = {
        str(y): recap_for(
            [e for e in shaped_events if e.get("year") == y],
            [s for s in shaped_sets if s.get("year") == y],
        )
        for y in years
    }
    return {
        "as_of": date.today().isoformat(),
        "all_time": recap_for(shaped_events, shaped_sets),
        "by_year": by_year,
        "counts": {"events": len(shaped_events), "sets": len(shaped_sets)},
    }


def rows_not_in_snapshot(conn: sqlite3.Connection) -> int:
    """Rows the snapshot cannot regenerate, i.e. anything entered in the app."""
    snapshot = set()
    for name in ("events.json", "sets.json"):
        path = DATA / name
        if path.exists():
            snapshot |= {r["id"] for r in json.loads(path.read_text())}
    return sum(
        1
        for table in ("events", "sets")
        for row in conn.execute(f"SELECT id FROM {table}")
        if row["id"] not in snapshot
    )


@app.post("/admin/reload-snapshot")
def reload_snapshot(force: bool = False) -> dict:
    """Drop and re-seed from data/*.json. Dev helper, not a migration tool."""
    if DB_PATH.exists() and not force:
        with db() as conn:
            extra = rows_not_in_snapshot(conn)
        if extra:
            raise HTTPException(
                409,
                f"{extra} rows are not in the snapshot and would be lost. "
                "Re-send with ?force=true to drop them anyway.",
            )
    if DB_PATH.exists():
        DB_PATH.unlink()
    with db() as conn:
        init_schema(conn)
        seed_if_empty(conn)
        events = conn.execute("SELECT COUNT(*) AS c FROM events").fetchone()["c"]
        sets = conn.execute("SELECT COUNT(*) AS c FROM sets").fetchone()["c"]
    return {"events": events, "sets": sets}
