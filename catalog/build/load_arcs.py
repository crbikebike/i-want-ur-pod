"""Apply `arcs-current.json` over what `arcs.seed` built. The mirror of `export_arcs`.

Upsert by (show slug, arc slug), membership by episode guid, `arcs_checked_at` stamped
per show. Runs after `arcs.seed` so the atlas baseline exists, before depth is derived
so the ladder sees the full 1,809 rather than the seeded 799.
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "curation/source"


@dataclass
class LoadArcsReport:
    shows: int = 0
    arcs_updated: int = 0
    arcs_created: int = 0
    memberships: int = 0
    unknown_shows: int = 0
    unmatched_guids: int = 0
    missing_file: bool = False

    def lines(self) -> list[str]:
        if self.missing_file:
            return ["arcs-current.json is not present -- keeping seeded arcs"]
        out = [f"arcs applied: {self.arcs_created} created, {self.arcs_updated} updated, "
               f"{self.memberships} episode memberships across {self.shows} shows"]
        if self.unknown_shows:
            out.append(f"  !! shows not in catalog: {self.unknown_shows}")
        if self.unmatched_guids:
            out.append(f"  !! member guids not found: {self.unmatched_guids}")
        return out


def load(conn: sqlite3.Connection, source: Path = SOURCE) -> LoadArcsReport:
    report = LoadArcsReport()
    path = source / "arcs-current.json"
    if not path.is_file():
        report.missing_file = True
        return report
    data = json.loads(path.read_text(encoding="utf-8"))

    for show_slug, entry in (data.get("shows") or {}).items():
        show = conn.execute("SELECT id FROM shows WHERE slug = ?",
                            (show_slug,)).fetchone()
        if not show:
            report.unknown_shows += 1
            continue
        show_id = show[0]
        report.shows += 1

        if entry.get("arcsCheckedAt"):
            conn.execute("UPDATE shows SET arcs_checked_at = ? WHERE id = ?",
                         (entry["arcsCheckedAt"], show_id))

        episode_ids = dict(conn.execute(
            "SELECT guid, id FROM episodes WHERE show_id = ?", (show_id,)))

        for arc in entry.get("arcs") or []:
            row = conn.execute(
                "SELECT id FROM arcs WHERE show_id = ? AND slug = ?",
                (show_id, arc["slug"])).fetchone()
            values = (arc["name"], arc.get("kind"), arc.get("confidence"),
                      arc.get("source") or "llm", arc.get("description"),
                      arc.get("deletedAt"), arc.get("deletedReason"))
            if row:
                conn.execute(
                    "UPDATE arcs SET name = ?, kind = ?, confidence = ?, source = ?, "
                    "description = ?, deleted_at = ?, deleted_reason = ? WHERE id = ?",
                    (*values, row[0]))
                arc_id = row[0]
                report.arcs_updated += 1
            else:
                cur = conn.execute(
                    "INSERT INTO arcs (show_id, slug, name, kind, confidence, source, "
                    "description, deleted_at, deleted_reason) VALUES (?,?,?,?,?,?,?,?,?)",
                    (show_id, arc["slug"], *values))
                arc_id = cur.lastrowid
                report.arcs_created += 1

            for guid in arc.get("episodes") or []:
                eid = episode_ids.get(guid)
                if eid is None:
                    report.unmatched_guids += 1
                    continue
                conn.execute("UPDATE episodes SET arc_id = ? WHERE id = ?",
                             (arc_id, eid))
                report.memberships += 1

    conn.commit()
    return report
