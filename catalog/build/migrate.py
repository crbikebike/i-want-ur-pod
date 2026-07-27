"""Build the catalog. The only entry point.

    python -m catalog.build.migrate [--out PATH] [--carry-edits FROM.db] [--version V]

Always builds a fresh database from curation/source/. Never migrates an existing one --
there is no upgrade path to get wrong, and a rebuild is under five seconds.

Corrections are not lost by that. The `edits` table is carried over from the previous
build and replayed as the last step, which is what makes "SQLite is the source of truth"
survive a rebuild. See replay.py.

Order matters in exactly two places: the vocabulary must exist before episodes can link
to subjects, and edges are derived last from everything else.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

from catalog.build import arcs, edges, fingerprint, fts, load_source, replay, vocabulary

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = ROOT / "curation/source"
DEFAULT_OUT = ROOT / "catalog/releases/catalog.db"
SCHEMA = ROOT / "catalog/schema.sql"
SUBJECT_THEMES = ROOT / "catalog/build/subject-themes.json"


def build(
    out: Path,
    source: Path = DEFAULT_SOURCE,
    carry_edits_from: Path | None = None,
    version: str = "dev",
    built_at: str | None = None,
    quiet: bool = False,
) -> str:
    """Build the catalog at `out`. Returns the content hash."""

    def say(*args):
        if not quiet:
            print(*args)

    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()

    conn = sqlite3.connect(out)
    conn.executescript(SCHEMA.read_text())
    conn.execute("PRAGMA foreign_keys = ON")

    carried = _carry_edits(conn, carry_edits_from)
    if carried:
        say(f"carried {carried} edits forward from {carry_edits_from}")

    say("-- vocabulary")
    for line in vocabulary.build(conn, source, SUBJECT_THEMES).lines():
        say(line)

    say("-- source")
    for line in load_source.load(conn, source).lines():
        say(line)

    say("-- arcs")
    for line in arcs.seed(conn, source).lines():
        say(line)

    say("-- edges")
    for line in edges.build(conn).lines():
        say(line)

    say("-- search")
    say(f"search index: {fts.build(conn)} episodes")

    say("-- edits")
    for line in replay.apply_all(conn).lines():
        say(line)

    # Edges are derived from the tables, so a replayed correction can change them.
    # Rebuilding here is cheap and keeps the graph honest.
    edges.build(conn)
    fts.build(conn)

    digest = fingerprint.content_hash(conn)
    counts = fingerprint.table_counts(conn)
    conn.execute(
        "INSERT INTO releases (version, built_at, show_count, episode_count, content_hash, notes) "
        "VALUES (?,?,?,?,?,?)",
        (
            version,
            built_at or datetime.now(timezone.utc).isoformat(timespec="seconds"),
            counts.get("shows", 0),
            counts.get("episodes", 0),
            digest,
            "Phase 1 build from curation/source/",
        ),
    )
    conn.commit()

    conn.execute("PRAGMA optimize")
    # Every build deletes and rewrites the whole file, so it accumulates free pages the
    # download would otherwise have to carry.
    conn.execute("VACUUM")
    conn.close()

    say(f"\nbuilt {out}  ({out.stat().st_size / 1e6:.1f} MB)")
    say(f"content hash: {digest}")
    return digest


def _carry_edits(conn: sqlite3.Connection, previous: Path | None) -> int:
    if not previous or not previous.exists():
        return 0
    old = sqlite3.connect(previous)
    try:
        rows = old.execute(
            "SELECT at, actor, entity_type, entity_key, field, before, after, note "
            "FROM edits ORDER BY id"
        ).fetchall()
    except sqlite3.OperationalError:
        return 0
    finally:
        old.close()
    conn.executemany(
        "INSERT INTO edits (at, actor, entity_type, entity_key, field, before, after, note) "
        "VALUES (?,?,?,?,?,?,?,?)",
        rows,
    )
    conn.commit()
    return len(rows)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument(
        "--carry-edits",
        type=Path,
        default=None,
        help="a previous .db whose edits should be carried forward and replayed",
    )
    parser.add_argument("--version", default="dev")
    parser.add_argument(
        "--built-at",
        default=None,
        help="fix the release timestamp, for reproducibility checks",
    )
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    build(
        out=args.out,
        source=args.source,
        carry_edits_from=args.carry_edits,
        version=args.version,
        built_at=args.built_at,
        quiet=args.quiet,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
