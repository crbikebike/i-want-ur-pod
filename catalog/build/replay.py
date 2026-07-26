"""Replay recorded corrections onto a freshly built catalog.

This is the mechanism that lets the database be the source of truth without a build step
losing your work. Every build starts from curation/source/, which knows nothing about
corrections; replay applies them last, in the order they were made.

Edits key on a stable entity_key rather than an internal integer id, because every build
regenerates those integers. See the schema comment on `edits`.

Only a conservative set of fields is replayable. An edit naming anything else is carried
forward in the log but not applied -- silently ignoring it would be worse, so it is
reported.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass, field

# entity_type -> the fields a correction may set. Kept narrow on purpose: these are the
# ones a human edits in the admin tool. Nothing here can change an identity (a slug, a
# guid, a foreign key), because that would make the edit itself unreplayable next time.
REPLAYABLE = {
    "show": {"title", "why", "description", "lang", "depth", "include_verdict", "artwork_url"},
    "theme": {"name", "description"},
    "arc": {"name", "description", "confidence", "kind"},
    "episode": {"title", "subject", "description", "available", "duration_s"},
}


@dataclass
class ReplayReport:
    applied: int = 0
    skipped_unknown_field: list[str] = field(default_factory=list)
    skipped_missing_entity: list[str] = field(default_factory=list)
    informational: int = 0

    def lines(self) -> list[str]:
        out = [f"edits replayed: {self.applied} applied, {self.informational} informational"]
        if self.skipped_unknown_field:
            out.append(f"  WARN not a replayable field: {self.skipped_unknown_field}")
        if self.skipped_missing_entity:
            out.append(f"  WARN entity no longer exists: {self.skipped_missing_entity}")
        return out


def apply_all(conn: sqlite3.Connection) -> ReplayReport:
    report = ReplayReport()

    rows = conn.execute(
        "SELECT id, entity_type, entity_key, field, after FROM edits ORDER BY id"
    ).fetchall()

    for edit_id, entity_type, entity_key, field_name, after in rows:
        if entity_type == "catalog":
            # Build-wide notes such as the duplicate-feed record. Nothing to apply.
            report.informational += 1
            continue

        allowed = REPLAYABLE.get(entity_type)
        if not allowed or field_name not in allowed:
            report.skipped_unknown_field.append(f"#{edit_id} {entity_type}.{field_name}")
            continue

        target = _resolve(conn, entity_type, entity_key)
        if target is None:
            report.skipped_missing_entity.append(f"#{edit_id} {entity_type} {entity_key}")
            continue

        table = {"show": "shows", "theme": "themes", "arc": "arcs", "episode": "episodes"}[
            entity_type
        ]
        conn.execute(f'UPDATE "{table}" SET "{field_name}" = ? WHERE id = ?', (after, target))
        report.applied += 1

    conn.commit()
    return report


def _resolve(conn: sqlite3.Connection, entity_type: str, key: str) -> int | None:
    """Turn a stable entity_key back into this build's integer id."""
    if entity_type == "show":
        row = conn.execute("SELECT id FROM shows WHERE slug = ?", (key,)).fetchone()
    elif entity_type == "theme":
        tier, _, slug = key.partition(":")
        if not slug or not tier.isdigit():
            return None
        row = conn.execute(
            "SELECT id FROM themes WHERE tier = ? AND slug = ?", (int(tier), slug)
        ).fetchone()
    elif entity_type == "arc":
        show_slug, _, arc_slug = key.partition("/")
        row = conn.execute(
            "SELECT a.id FROM arcs a JOIN shows s ON s.id = a.show_id "
            "WHERE s.slug = ? AND a.slug = ?",
            (show_slug, arc_slug),
        ).fetchone()
    elif entity_type == "episode":
        show_slug, _, guid = key.partition("/")
        row = conn.execute(
            "SELECT e.id FROM episodes e JOIN shows s ON s.id = e.show_id "
            "WHERE s.slug = ? AND e.guid = ?",
            (show_slug, guid),
        ).fetchone()
    else:
        return None
    return row[0] if row else None


def record(
    conn: sqlite3.Connection,
    *,
    at: str,
    actor: str,
    entity_type: str,
    entity_key: str,
    field_name: str,
    before: str | None,
    after: str | None,
    note: str | None = None,
) -> None:
    """Append a correction. The admin tool's only write path in Phase 2."""
    conn.execute(
        "INSERT INTO edits (at, actor, entity_type, entity_key, field, before, after, note) "
        "VALUES (?,?,?,?,?,?,?,?)",
        (at, actor, entity_type, entity_key, field_name, before, after, note),
    )
    conn.commit()
