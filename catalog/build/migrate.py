"""Import the catalog from curation/source/. A one-time tool, not a build step.

    python -m catalog.build.migrate --out catalog/catalog.db [--force]

This ran once, in Phase 1, and produced the catalog. It is kept because starting over
from source should always be possible -- but it is no longer how the catalog is *built*,
because the catalog is no longer derived.

The moment a human makes a judgement call, the database holds something no source file
does. So this **refuses to overwrite an existing database** unless you pass --force, and
`--force` prints what it is about to destroy. Ordinary schema changes go through
catalog/migrations/ instead, which are additive and never touch data.

Order matters in exactly two places: the vocabulary must exist before episodes can link
to subjects, and edges are derived last from everything else.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

from catalog.build import (arcs, depth, edges, fingerprint, fts, load_arcs,
                           load_labels, load_source, migrations, replay, vocabulary)

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = ROOT / "curation/source"
DEFAULT_OUT = ROOT / "catalog/catalog.db"
SCHEMA = ROOT / "catalog/schema.sql"
SUBJECT_THEMES = ROOT / "catalog/build/subject-themes.json"
ADDED_THEMES = ROOT / "catalog/build/added-themes.json"


class WouldDestroyWork(Exception):
    """Raised rather than overwrite a database holding human decisions."""


def guard(out: Path) -> None:
    """Refuse to clobber an existing catalog.

    An import is not idempotent any more: the database accumulates judgement calls that
    exist nowhere else. Running this by muscle memory should not be able to erase an
    afternoon of review.
    """
    if not out.exists():
        return
    try:
        old = sqlite3.connect(f"file:{out}?mode=ro", uri=True)
        human_edits = old.execute(
            "SELECT count(*) FROM edits WHERE actor NOT LIKE 'agent:%'"
        ).fetchone()[0]
        shows = old.execute("SELECT count(*) FROM shows").fetchone()[0]
        old.close()
    except sqlite3.Error:
        human_edits, shows = "?", "?"
    raise WouldDestroyWork(
        f"{out} already exists ({shows} shows, {human_edits} human decisions).\n"
        f"Importing would destroy it. Schema changes belong in catalog/migrations/, "
        f"which are additive.\nIf you really mean to start over: --force"
    )


def build(
    out: Path,
    source: Path = DEFAULT_SOURCE,
    carry_edits_from: Path | None = None,
    version: str = "dev",
    built_at: str | None = None,
    quiet: bool = False,
    force: bool = False,
) -> str:
    """Import the catalog to `out`. Returns the content hash."""

    def say(*args):
        if not quiet:
            print(*args)

    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        if not force:
            guard(out)
        out.unlink()

    conn = sqlite3.connect(out)
    conn.executescript(SCHEMA.read_text())
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")

    for line in migrations.apply_all(conn).lines():
        say(line)

    carried = _carry_edits(conn, carry_edits_from, source / "decisions.jsonl")
    if carried:
        say(f"carried {carried} edits forward from {carry_edits_from}")

    say("-- vocabulary")
    for line in vocabulary.build(conn, source, SUBJECT_THEMES, ADDED_THEMES).lines():
        say(line)

    say("-- source")
    for line in load_source.load(conn, source).lines():
        say(line)

    say("-- arcs")
    for line in arcs.seed(conn, source).lines():
        say(line)
    for line in load_arcs.load(conn, source).lines():
        say(line)

    say("-- edges")
    for line in edges.build(conn).lines():
        say(line)

    say("-- search")
    say(f"search index: {fts.build(conn)} episodes")

    say("-- edits")
    for line in replay.apply_all(conn).lines():
        say(line)

    # After replay: labels are guid-keyed so replayed episode corrections cannot move
    # them, but keeping the one-directional order (sources, then corrections, then the
    # current run's labels) means nothing loaded here is ever overwritten by an older
    # record of itself.
    say("-- labels")
    for line in load_labels.load(conn, source).lines():
        say(line)

    # Depth is derived from labels, arcs and verdicts, all of which have now reached
    # their final state -- arcs.seed computed it before labels existed, which left every
    # show at 1. Then edges: derived from everything, rebuilt last, kept honest.
    depth.rebuild(conn)
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


def _carry_edits(conn: sqlite3.Connection, previous: Path | None,
                 decisions: Path | None = None) -> int:
    """Bring the audit log into the new database, so replay has something to replay.

    Preferred source is a previous database's edits table. On a clean checkout there is
    no previous database -- but `decisions.jsonl` is the tracked mirror of that table,
    written line-for-line by `edits.apply`, so it serves as the fallback. Without this,
    replay reads an empty table, no fit verdict or human correction survives a rebuild,
    and every show comes back `unreviewed` at depth 1.
    """
    rows: list[tuple] = []
    if previous and previous.exists():
        old = sqlite3.connect(previous)
        try:
            rows = old.execute(
                "SELECT at, actor, entity_type, entity_key, field, before, after, note "
                "FROM edits ORDER BY id"
            ).fetchall()
        except sqlite3.OperationalError:
            rows = []
        finally:
            old.close()
    if not rows and decisions and decisions.exists():
        for line in decisions.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            # Batch records (field "label", "refresh", ...) carry counts rather than an
            # entity to touch; replay skips their fields, but they stay in the table
            # because they are audit, and audit that survives a rebuild is the point.
            rows.append((r.get("at"), r.get("actor"), r.get("entity"), r.get("key"),
                         r.get("field"), _as_text(r.get("before")),
                         _as_text(r.get("after")), r.get("note")))
    if not rows:
        return 0
    conn.executemany(
        "INSERT INTO edits (at, actor, entity_type, entity_key, field, before, after, note) "
        "VALUES (?,?,?,?,?,?,?,?)",
        rows,
    )
    conn.commit()
    return len(rows)


def _as_text(value):
    """JSONL before/after may hold structured values; the edits table stores text."""
    if value is None or isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False)


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
    parser.add_argument(
        "--force", action="store_true",
        help="overwrite an existing catalog, destroying any decisions recorded in it",
    )
    args = parser.parse_args(argv)

    try:
        build(
            out=args.out,
            source=args.source,
            carry_edits_from=args.carry_edits,
            version=args.version,
            built_at=args.built_at,
            quiet=args.quiet,
            force=args.force,
        )
    except WouldDestroyWork as e:
        print(f"\nrefusing to import:\n{e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
