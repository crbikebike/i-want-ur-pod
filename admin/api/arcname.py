"""Give an arc a name that says which story it is.

The detector groups episodes well and names them only as well as the publisher did. When
a show puts the subject in the title -- "Hunting Season | Part 2" -- the name comes out
right. When it numbers everything, the detector has nothing to work with and produces
"Season 1", which tells a listener nothing about whether they want it. 146 of 1,688 arcs
are in that state.

Three ways a name fails, and they are one failure -- after reading it you still do not
know which story you are looking at:

    a position, not a subject      "Season 1", "Part 3", "Bonus"
    just the show's own name       "Legal Docket" inside Legal Docket
    already used in this show      two arcs both called "Presidential Assassinations"

This is the read/write contract the arc-namer agent works through, shaped like
`admin/api/fit.py`. The agent never touches the database: it gets arcs and their episodes
as JSON and hands back names as JSON.

    python -m admin.api.arcname next --limit 20
    python -m admin.api.arcname record names.json

Keep the ordinal, add the subject: "Season 1" becomes "Season 1 — The Vanishing at
Kolmanskop". Position is real information; it is just not enough on its own.

**A name the agent cannot write is a finding, not a failure.** If a run of episodes has no
common subject, the grouping is probably wrong, and saying so routes it to review instead
of decorating a bad arc with a plausible name.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

from admin.api import edits, feeds
from admin.api.arcbuild import says_nothing
from catalog.build.normalize import slugify

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "catalog/catalog.db"

# Enough description to recognise a story without turning a batch into a wall of text.
# The whole point of Job 0 was to have this text at all; 600 characters of it is plenty to
# see that six episodes are about one shipwreck.
DESC_CHARS = 600


def _duplicated(conn: sqlite3.Connection) -> set[int]:
    """Arc ids whose name is used by another live arc in the same show."""
    rows = conn.execute(
        "SELECT id, show_id, name FROM arcs WHERE deleted_at IS NULL").fetchall()
    seen: dict[tuple, list[int]] = {}
    for aid, show_id, name in rows:
        seen.setdefault((show_id, slugify(name or "x")), []).append(aid)
    return {aid for ids in seen.values() if len(ids) > 1 for aid in ids}


def pending(conn: sqlite3.Connection, limit: int = 20,
            slice_of: tuple[int, int] | None = None) -> list[dict]:
    """Arcs whose name says nothing, with the episodes needed to write a better one.

    `slice_of` is (i, n): only arcs where id % n == i, so several agents can run at once
    without racing. Not an OFFSET -- the set shrinks as names land, so every agent's
    window would slide over the same arcs.
    """
    dup = _duplicated(conn)
    where, args = "", []
    if slice_of:
        i, n = slice_of
        where, args = "AND a.id % ? = ?", [n, i]

    rows = conn.execute(
        f"""
        SELECT a.id, a.slug, a.name, a.source, s.id, s.title, s.description
        FROM arcs a JOIN shows s ON s.id = a.show_id
        WHERE a.deleted_at IS NULL AND s.deleted_at IS NULL
          AND a.name IS NOT NULL {where}
        ORDER BY a.id
        """,
        args,
    ).fetchall()

    out = []
    for arc_id, slug, name, source, show_id, show_title, show_desc in rows:
        why = says_nothing(name, show_title=show_title, duplicate=arc_id in dup)
        if not why:
            continue
        eps = [
            {"title": t, "published": (p or "")[:10],
             "description": feeds.plain_text(d, DESC_CHARS)}
            for t, p, d in conn.execute(
                "SELECT title, published_at, description FROM episodes "
                "WHERE arc_id = ? AND deleted_at IS NULL ORDER BY published_at",
                (arc_id,))
        ]
        if len(eps) < 2:
            continue
        out.append({
            "arcId": arc_id,
            "currentName": name,
            "why": why,
            "show": show_title,
            "showAbout": (show_desc or "")[:300],
            "episodes": eps,
        })
        if len(out) >= limit:
            break
    return out


def remaining(conn: sqlite3.Connection) -> int:
    return len(pending(conn, limit=10 ** 6))


def record(conn: sqlite3.Connection, names: list[dict], *,
           decisions_path: Path | None = None) -> dict:
    """Write new names. One edit each, so each is separately undoable."""
    written, flagged, skipped = 0, 0, []

    for item in names:
        arc_id, name = item.get("arcId"), (item.get("name") or "").strip()
        unnameable = bool(item.get("noCommonSubject"))

        row = conn.execute(
            "SELECT a.name, s.title FROM arcs a JOIN shows s ON s.id = a.show_id "
            "WHERE a.id = ?", (arc_id,)).fetchone()
        if not row:
            skipped.append(f"{arc_id}: no such arc")
            continue
        current, show_title = row

        if unnameable:
            # The episodes do not tell one story. Dropping the confidence is what puts it
            # at the front of the review queue, which orders on lowest first.
            try:
                edits.apply(conn, entity_type="arc", entity_id=arc_id, field="confidence",
                            after="low", actor="agent:arcname",
                            note=item.get("reason") or "no common subject across these episodes",
                            decisions_path=decisions_path)
            except edits.EditError as e:
                if "already" not in str(e):
                    skipped.append(f"{arc_id}: {e}")
                    continue
            flagged += 1
            continue

        if not name:
            skipped.append(f"{arc_id}: no name and not flagged as unnameable")
            continue
        if len(name) > 120:
            name = name[:117].rstrip() + "…"

        # The new name has to survive the test the old one failed. Otherwise a model that
        # answers "Season 1" is taken at its word and nothing improves.
        still = says_nothing(name, show_title=show_title)
        if still:
            skipped.append(f"{arc_id}: {name!r} still {still}")
            continue

        try:
            edits.apply(conn, entity_type="arc", entity_id=arc_id, field="name", after=name,
                        actor="agent:arcname",
                        note=f"was {current!r} — {item.get('reason') or 'read from its episodes'}",
                        decisions_path=decisions_path)
        except edits.EditError as e:
            if "already" in str(e):
                continue
            skipped.append(f"{arc_id}: {e}")
            continue
        written += 1

    return {"named": written, "flagged": flagged, "skipped": skipped,
            "remaining": remaining(conn)}


def _open() -> sqlite3.Connection:
    conn = sqlite3.connect(DB, timeout=30)
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    nxt = sub.add_parser("next", help="arcs needing a name, as JSON")
    nxt.add_argument("--limit", type=int, default=20)
    nxt.add_argument("--slice", help="i/n -- only arcs where id %% n == i")

    rec = sub.add_parser("record", help="write names back")
    rec.add_argument("file", type=Path,
                     help="JSON: a list of {arcId, name, reason} or "
                          "{arcId, noCommonSubject: true, reason}")

    sub.add_parser("status", help="how many are left")

    args = ap.parse_args(argv)
    conn = _open()

    if args.cmd == "next":
        sl = None
        if getattr(args, "slice", None):
            i, n = (int(x) for x in args.slice.split("/"))
            sl = (i, n)
        print(json.dumps({"remaining": remaining(conn),
                          "arcs": pending(conn, args.limit, sl)}, indent=1))
    elif args.cmd == "record":
        payload = json.loads(args.file.read_text())
        items = payload["names"] if isinstance(payload, dict) else payload
        result = record(conn, items)
        print(json.dumps(result, indent=1))
        if result["skipped"]:
            return 1
    else:
        print(json.dumps({"remaining": remaining(conn)}, indent=1))

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
