"""The one place the catalog is written.

Every judgement call in the workbench comes through `apply()`. Nothing else in the API
touches a table, and a test asserts it. That single door is what makes three promises
true at once:

  the row changes          so the screen is correct immediately
  `edits` gets an entry    so there is an audit trail and an undo
  decisions.jsonl grows    so the decisions live in git, not just on this disk

All three happen in one transaction. If the JSONL write fails the database rolls back,
because a decision that exists in only one of the three places is worse than one that
never happened.

Why the JSONL at all: catalog.db is 30 MB of binary that changes on every tap, which is
wrong for version control. But the judgement calls inside it are the only irreplaceable
thing in this project -- everything else can be rebuilt from feeds and re-run by a model.
So the derived data stays out of git and the decisions go in.
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DECISIONS = ROOT / "curation/source/decisions.jsonl"

# entity type -> (table, the fields a human may set)
#
# Deliberately narrow. Slugs, GUIDs and feed URLs are absent because everything in the
# catalog references them; renaming one silently orphans whatever points at it. Renaming
# a *slug* is a merge, which is its own explicit action with its own confirmation.
WRITABLE: dict[str, tuple[str, set[str]]] = {
    "show":    ("shows",    {"include_verdict", "depth", "lang", "title", "why", "description"}),
    "theme":   ("themes",   {"name", "description"}),
    "subject": ("subjects", {"name", "description", "theme_id"}),
    "arc":     ("arcs",     {"name", "description", "confidence", "kind"}),
    "episode": ("episodes", {"title", "description", "available", "duration_s"}),
}

# How an entity's stable key is built. Never the integer id: those are assigned at import
# and an edit recorded against id 42 would land on a different row in a rebuilt database.
KEY_SQL = {
    "show":    "SELECT slug FROM shows WHERE id = ?",
    "theme":   "SELECT slug FROM themes WHERE id = ?",
    "subject": "SELECT slug FROM subjects WHERE id = ?",
    "arc":     "SELECT s.slug || '/' || a.slug FROM arcs a JOIN shows s ON s.id = a.show_id"
               " WHERE a.id = ?",
    "episode": "SELECT s.slug || '/' || e.guid FROM episodes e JOIN shows s ON s.id = e.show_id"
               " WHERE e.id = ?",
}


class EditError(ValueError):
    """A rejected edit. The message is shown to the person who tried to make it."""


@dataclass
class Edit:
    edit_id: int
    entity_type: str
    entity_key: str
    field: str
    before: str | None
    after: str | None


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def entity_key(conn: sqlite3.Connection, entity_type: str, entity_id: int) -> str:
    sql = KEY_SQL.get(entity_type)
    if not sql:
        raise EditError(f"{entity_type!r} is not an editable kind of thing")
    row = conn.execute(sql, (entity_id,)).fetchone()
    if not row:
        raise EditError(f"no {entity_type} with id {entity_id}")
    return row[0]


def apply(
    conn: sqlite3.Connection,
    *,
    entity_type: str,
    entity_id: int,
    field: str,
    after,
    actor: str = "human",
    note: str | None = None,
    decisions_path: Path | None = None,
) -> Edit:
    """Change one field on one thing. The only write path in the API."""
    if entity_type not in WRITABLE:
        raise EditError(f"{entity_type!r} is not editable")
    table, allowed = WRITABLE[entity_type]
    if field not in allowed:
        raise EditError(
            f"{entity_type}.{field} is not editable. Editable here: {', '.join(sorted(allowed))}"
        )

    key = entity_key(conn, entity_type, entity_id)
    before_row = conn.execute(f'SELECT "{field}" FROM "{table}" WHERE id = ?', (entity_id,)).fetchone()
    before = before_row[0] if before_row else None

    if before == after:
        raise EditError(f"{field} is already {after!r}")

    path = decisions_path or DECISIONS
    at = _now()

    try:
        # One transaction across all three. sqlite3 opens one implicitly on the first
        # write; the explicit rollback below covers the JSONL failing afterwards.
        conn.execute(f'UPDATE "{table}" SET "{field}" = ? WHERE id = ?', (after, entity_id))
        cur = conn.execute(
            "INSERT INTO edits (at, actor, entity_type, entity_key, field, before, after, note) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (at, actor, entity_type, key, field, before, after, note),
        )
        edit_id = cur.lastrowid

        record = {
            "id": edit_id, "at": at, "actor": actor, "entity": entity_type, "key": key,
            "field": field, "before": before, "after": after,
        }
        if note:
            record["note"] = note
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
            fh.flush()
    except Exception:
        conn.rollback()
        raise

    conn.commit()
    return Edit(edit_id, entity_type, key, field, before, after)


def undo(conn: sqlite3.Connection, edit_id: int, *, decisions_path: Path | None = None) -> Edit:
    """Put a field back the way it was.

    Recorded as a new edit rather than by deleting the old one -- `edits` is append-only,
    and a log you can rewrite is not a log. Undoing an undo therefore works too.
    """
    row = conn.execute(
        "SELECT entity_type, entity_key, field, before, after FROM edits WHERE id = ?",
        (edit_id,),
    ).fetchone()
    if not row:
        raise EditError(f"no edit {edit_id}")
    entity_type, key, field, before, _after = row

    entity_id = _id_for_key(conn, entity_type, key)
    if entity_id is None:
        raise EditError(f"the {entity_type} this edit changed is gone: {key}")

    return apply(
        conn, entity_type=entity_type, entity_id=entity_id, field=field, after=before,
        actor="human", note=f"undo of edit {edit_id}", decisions_path=decisions_path,
    )


def _id_for_key(conn: sqlite3.Connection, entity_type: str, key: str) -> int | None:
    if entity_type in ("show", "theme", "subject"):
        table = WRITABLE[entity_type][0]
        row = conn.execute(f'SELECT id FROM "{table}" WHERE slug = ?', (key,)).fetchone()
    elif entity_type == "arc":
        show_slug, _, arc_slug = key.partition("/")
        row = conn.execute(
            "SELECT a.id FROM arcs a JOIN shows s ON s.id = a.show_id "
            "WHERE s.slug = ? AND a.slug = ?", (show_slug, arc_slug)).fetchone()
    elif entity_type == "episode":
        show_slug, _, guid = key.partition("/")
        row = conn.execute(
            "SELECT e.id FROM episodes e JOIN shows s ON s.id = e.show_id "
            "WHERE s.slug = ? AND e.guid = ?", (show_slug, guid)).fetchone()
    else:
        return None
    return row[0] if row else None


def recent(conn: sqlite3.Connection, limit: int = 20) -> list[dict]:
    return [
        {"id": r[0], "at": r[1], "actor": r[2], "entity": r[3], "key": r[4],
         "field": r[5], "before": r[6], "after": r[7], "note": r[8]}
        for r in conn.execute(
            "SELECT id, at, actor, entity_type, entity_key, field, before, after, note "
            "FROM edits WHERE entity_type != 'catalog' ORDER BY id DESC LIMIT ?", (limit,))
    ]
