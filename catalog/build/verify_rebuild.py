"""Prove the catalog rebuilds from `curation/source/`. CLAUDE.md's promise, executable.

Builds a scratch database from source and compares seven slug-keyed layers against the
live one -- labels, entity links, subjects, episodes, shows, arcs, arc membership.
Slug-and-guid keyed rather than integer-keyed, because ids are assigned at import and
differ between builds without the data differing.

Exits 0 on a full match. On mismatch, prints which layer drifted; the fix is almost
always a stale export -- re-run the exporters and look at the diff:

    python -m catalog.build.export_labels
    python -m catalog.build.export_vocabulary
    python -m catalog.build.export_episodes
    python -m catalog.build.export_tombstones
    python -m catalog.build.export_arcs

Known, accepted degradations -- outside the comparison on purpose:
- description/duration enrichment on pre-comb episodes: the publisher's own text,
  re-fetched by re-running the comb against live feeds, not snapshotted into git.
- the edits table's batch records: jsonl and table represent them differently; every
  *replayable* record survives, the counters drift in shape.
- the 319-row 2026-07-relabel pilot run: never exported, kept only in the live file.

    python -m catalog.build.verify_rebuild
"""

from __future__ import annotations

import argparse
import hashlib
import sqlite3
import sys
import tempfile
from pathlib import Path

from catalog.build import migrate

ROOT = Path(__file__).resolve().parents[2]
LIVE = ROOT / "catalog/catalog.db"

LAYERS = {
    "labels v176": """SELECT sh.slug,e.guid,s.slug,l.run_id,l.role,l.confidence,
        l.agreement,l.votes,l.model,l.at
        FROM episode_labels l JOIN episodes e ON e.id=l.episode_id
        JOIN shows sh ON sh.id=e.show_id JOIN subjects s ON s.id=l.subject_id
        WHERE l.run_id='2026-07-relabel-v176' ORDER BY 1,2,3""",
    "entities v176": """SELECT sh.slug,e.guid,en.slug,en.name,en.kind,ee.run_id,
        ee.confidence,ee.at
        FROM episode_entities ee JOIN episodes e ON e.id=ee.episode_id
        JOIN shows sh ON sh.id=e.show_id JOIN entities en ON en.id=ee.entity_id
        WHERE ee.run_id='2026-07-relabel-v176' ORDER BY 1,2,3""",
    "subjects": """SELECT s.slug,s.name,s.description,t.slug,s.deleted_at,
        s.deleted_reason FROM subjects s JOIN themes t ON t.id=s.theme_id ORDER BY 1""",
    "episodes": """SELECT sh.slug,e.guid,e.title,e.season,e.episode_number,
        e.episode_type,e.published_at,e.available,e.deleted_at,e.deleted_reason
        FROM episodes e JOIN shows sh ON sh.id=e.show_id ORDER BY 1,2""",
    "shows": """SELECT slug,title,include_verdict,depth,arcs_checked_at,deleted_at,
        deleted_reason FROM shows WHERE deleted_at IS NULL ORDER BY 1""",
    "arcs": """SELECT sh.slug,a.slug,a.name,a.kind,a.confidence,a.source,
        a.description,a.deleted_at FROM arcs a JOIN shows sh ON sh.id=a.show_id
        WHERE sh.deleted_at IS NULL ORDER BY 1,2""",
    "arc membership": """SELECT sh.slug,e.guid,a.slug FROM episodes e
        JOIN shows sh ON sh.id=e.show_id LEFT JOIN arcs a ON a.id=e.arc_id
        WHERE e.deleted_at IS NULL AND sh.deleted_at IS NULL ORDER BY 1,2""",
}


def layer_hash(db: Path, sql: str) -> tuple[str, int]:
    conn = sqlite3.connect(db)
    digest, rows = hashlib.sha256(), 0
    for row in conn.execute(sql):
        digest.update(
            ("\x1f".join("\x00" if v is None else str(v) for v in row) + "\n").encode())
        rows += 1
    conn.close()
    return digest.hexdigest()[:16], rows


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--live", type=Path, default=LIVE)
    ap.add_argument("--keep", type=Path, help="keep the scratch build at this path")
    args = ap.parse_args(argv)

    with tempfile.TemporaryDirectory() as tmp:
        scratch = args.keep or Path(tmp) / "rebuild.db"
        migrate.build(scratch, quiet=True, force=True)

        ok = True
        for name, sql in LAYERS.items():
            a, na = layer_hash(args.live, sql)
            b, nb = layer_hash(scratch, sql)
            match = a == b
            ok = ok and match
            print(f"{name:16s}: live {a} ({na}) | rebuilt {b} ({nb}) | "
                  f"{'MATCH' if match else 'MISMATCH'}")

    print("\nrebuild proven" if ok else "\nMISMATCH -- a source export is stale")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
