"""Find story arcs in the shows whose titles carry no pattern to match.

The text-matching detector reaches 216 of 275 shows. The 66 it cannot read are not a
failure of tuning -- the bakeoff measured this and was blunt about it: **218 of 220 misses
are "zero members detected"**, meaning the parser never clusters those episodes at all.
*"Turning up the risk dial cannot fix a parser that cannot read the title."*

What is left needs reading rather than matching. One show titles its episodes
*Antediluvian*, *The Bridge*, *Exodus*. Nothing in those strings says they are one story;
knowing that takes understanding what they are about.

This is the read/write contract the arc-finder agent works through, shaped like
`admin/api/fit.py` and `admin/api/arcname.py`. The agent never touches the database.

    python -m admin.api.arcfind next --limit 3
    python -m admin.api.arcfind record arcs.json

**"No arcs in this show" is a real answer and is recorded.** Most of these 66 are
anthologies or interview shows where every episode stands alone. Without somewhere to put
that, the next pass reads them all again -- which is the loop the naming queue hit when a
decision that produced no row left nothing to exclude on. `shows.arcs_checked_at` is where
it goes.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

from admin.api import edits, feeds
from admin.api.arcbuild import MAX_MEMBERS, says_nothing
from catalog.build.normalize import slugify

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "catalog/catalog.db"

# Enough to see a story without drowning it. These are shows with no detected structure,
# so the titles alone are rarely enough and the description is doing the work.
DESC_CHARS = 320

# The most episodes to put in one call. Two shows here run past 500, and a story arc is a
# run of consecutive episodes -- so the newest slice is where a reader can still see runs
# whole. What was left out is reported rather than quietly dropped, and recorded on the
# show so a later pass can tell "nothing in all of it" from "nothing in what we read".
EPISODE_CAP = 250

KINDS = {"arc", "series"}
CONFIDENCE = {"low", "medium", "high"}


def pending(conn: sqlite3.Connection, limit: int = 3,
            slice_of: tuple[int, int] | None = None) -> list[dict]:
    """Shows with no arcs that nobody has read yet, with their episodes.

    Smallest first. A 3-episode limited series is one arc and takes one glance; getting
    those out of the way makes the queue visibly shorten, and leaves the genuinely hard
    500-episode anthologies as a known remainder rather than a wall at the front.
    """
    where, args = "", []
    if slice_of:
        i, n = slice_of
        where, args = "AND s.id % ? = ?", [n, i]

    rows = conn.execute(
        f"""
        SELECT s.id, s.slug, s.title, s.description, s.years, n.name,
               (SELECT count(*) FROM episodes e
                WHERE e.show_id = s.id AND e.deleted_at IS NULL) AS eps
        FROM shows s LEFT JOIN networks n ON n.id = s.network_id
        WHERE s.deleted_at IS NULL AND s.include_verdict = 'keep'
          AND s.arcs_checked_at IS NULL
          AND NOT EXISTS (SELECT 1 FROM arcs a
                          WHERE a.show_id = s.id AND a.deleted_at IS NULL)
          {where}
        ORDER BY eps ASC, s.id
        LIMIT ?
        """,
        (*args, limit),
    ).fetchall()

    out = []
    for show_id, slug, title, description, years, network, eps in rows:
        episodes = [
            {"guid": g, "title": t, "published": (p or "")[:10],
             "description": feeds.plain_text(d, DESC_CHARS)}
            for g, t, p, d in conn.execute(
                "SELECT guid, title, published_at, description FROM episodes "
                "WHERE show_id = ? AND deleted_at IS NULL "
                "ORDER BY published_at DESC LIMIT ?", (show_id, EPISODE_CAP))
        ]
        episodes.reverse()  # oldest first: a story reads in the order it was told
        out.append({
            "showId": show_id,
            "slug": slug,
            "title": title,
            "network": network,
            "years": years,
            "about": (description or "")[:400],
            "episodeCount": eps,
            "episodesShown": len(episodes),
            "episodes": episodes,
        })
    return out


def remaining(conn: sqlite3.Connection) -> int:
    return conn.execute(
        """SELECT count(*) FROM shows s WHERE s.deleted_at IS NULL
           AND s.include_verdict = 'keep' AND s.arcs_checked_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM arcs a
                           WHERE a.show_id = s.id AND a.deleted_at IS NULL)"""
    ).fetchone()[0]


def _mark_checked(conn, show_id: int, seen: int, model: str, decisions_path) -> None:
    for field, value in (("arcs_checked_at", feeds.now()),
                         ("arcs_checked_by", model),
                         ("arcs_checked_eps", seen)):
        try:
            edits.apply(conn, entity_type="show", entity_id=show_id, field=field,
                        after=value, actor="agent:arcfind",
                        decisions_path=decisions_path)
        except edits.EditError as e:
            if "already" not in str(e):
                raise


def record(conn: sqlite3.Connection, findings: list[dict], *, model: str = "claude-sonnet-5",
           decisions_path: Path | None = None) -> dict:
    """Write arcs found in a show, or record that there are none.

    One finding per *show*, not per arc, because "I read this show and there are no arcs"
    has to be expressible. A finding with an empty `arcs` list is that answer.
    """
    made = shows = empty = 0
    skipped: list[str] = []

    for f in findings:
        show_id = f.get("showId")
        row = conn.execute(
            "SELECT slug, title FROM shows WHERE id = ? AND deleted_at IS NULL",
            (show_id,)).fetchone()
        if not row:
            skipped.append(f"{show_id}: no such show")
            continue
        show_slug, show_title = row
        seen = int(f.get("episodesRead") or 0)

        ready, refused = [], False
        used = {r[0] for r in conn.execute(
            "SELECT slug FROM arcs WHERE show_id = ?", (show_id,))}

        for a in f.get("arcs") or []:
            name = (a.get("name") or "").strip()
            members = list(dict.fromkeys(a.get("members") or []))
            kind = a.get("kind", "arc")
            conf = a.get("confidence", "medium")

            # The bar Job 2 set: an arc arrives named or it does not arrive. Letting a
            # model hand back "Season 1" here would recreate by hand the exact problem
            # that pass just finished fixing.
            why = says_nothing(name, show_title=show_title)
            if why:
                skipped.append(f"{show_slug}: {name!r} is {why}")
                refused = True
                continue
            if kind not in KINDS:
                skipped.append(f"{show_slug}: kind {kind!r} not in {sorted(KINDS)}")
                refused = True
                continue
            if conf not in CONFIDENCE:
                skipped.append(f"{show_slug}: confidence {conf!r} not in {sorted(CONFIDENCE)}")
                refused = True
                continue
            if len(members) < 2:
                skipped.append(f"{show_slug}: {name!r} has fewer than two episodes")
                refused = True
                continue
            if len(members) > MAX_MEMBERS:
                skipped.append(f"{show_slug}: {name!r} claims {len(members)} episodes; "
                               f"past {MAX_MEMBERS} it is a segment or the whole feed")
                refused = True
                continue

            base, arc_slug, n = slugify(name), slugify(name), 1
            while arc_slug in used:
                n += 1
                arc_slug = f"{base}-{n}"
            used.add(arc_slug)
            ready.append({"slug": arc_slug, "name": name, "kind": kind,
                          "confidence": conf, "source": "llm",
                          "description": (a.get("why") or "")[:400] or None,
                          "members": members})

        if ready:
            got = edits.create_arcs(conn, show_id=show_id, arcs=ready, actor="agent:arcfind",
                                    note="read from the episodes", decisions_path=decisions_path)
            made += got["arcs"]
            if got["skipped"]:
                skipped.append(f"{show_slug}: {got['skipped']} arcs lost their episodes to "
                               f"an existing arc")
        elif not refused:
            empty += 1

        # Marked read either way -- but never when something was refused, or a rejected
        # batch would look like a show with no stories in it and never be offered again.
        if not refused:
            _mark_checked(conn, show_id, seen, model, decisions_path)
            shows += 1

    return {"arcs": made, "showsRead": shows, "showsWithNoArcs": empty,
            "skipped": skipped, "remaining": remaining(conn)}


def _open() -> sqlite3.Connection:
    conn = sqlite3.connect(DB, timeout=30)
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    nxt = sub.add_parser("next", help="shows needing an arc read, as JSON")
    nxt.add_argument("--limit", type=int, default=3)
    nxt.add_argument("--slice", help="i/n -- only shows where id %% n == i")

    rec = sub.add_parser("record", help="write findings back")
    rec.add_argument("file", type=Path,
                     help="JSON: a list of {showId, episodesRead, arcs: [...]}")
    rec.add_argument("--model", default="claude-sonnet-5")

    sub.add_parser("status", help="how many shows are left")

    args = ap.parse_args(argv)
    conn = _open()

    if args.cmd == "next":
        sl = None
        if getattr(args, "slice", None):
            i, n = (int(x) for x in args.slice.split("/"))
            sl = (i, n)
        print(json.dumps({"remaining": remaining(conn),
                          "shows": pending(conn, args.limit, sl)}, indent=1))
    elif args.cmd == "record":
        payload = json.loads(args.file.read_text())
        items = payload["shows"] if isinstance(payload, dict) else payload
        result = record(conn, items, model=args.model)
        print(json.dumps(result, indent=1))
        if result["skipped"]:
            return 1
    else:
        print(json.dumps({"remaining": remaining(conn)}, indent=1))

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
