"""On-disk contract for ios/Rave/Services/LastReadStore.swift.

Envelope: {"saved_at": ISO-8601, "payload": ...}
Keys: events.json, sets.json, recap.json, stats.json, event-<id>.json
Id sanitization: "/" and ":" become "_".
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


def filename(key: str, event_id: str | None = None) -> str:
    if key == "event":
        if not event_id:
            raise ValueError("event id required")
        safe = event_id.replace("/", "_").replace(":", "_")
        return f"event-{safe}.json"
    return f"{key}.json"


def save(directory: Path, key: str, payload: object, event_id: str | None = None) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / filename(key, event_id)
    envelope = {
        "saved_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "payload": payload,
    }
    path.write_text(json.dumps(envelope), encoding="utf-8")
    return path


def load(directory: Path, key: str, event_id: str | None = None) -> dict | None:
    path = directory / filename(key, event_id)
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))
