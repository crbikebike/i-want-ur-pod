"""What each episode is about.

Every episode carries subjects from a fixed list of 148 -- "The Scandal That Broke", "A
Person Who Vanished". Those labels drive what the app recommends: `shares_subject` is the
dominant signal in the next-thing query, and for anthology shows like This American Life
and Swindled, which have no story arcs and never will, subjects are the *only* way in.

The catalog has been labelled once. In July, 27,444 episodes were read by Haiku shown
**150 characters** of each description, truncated in the prompt on top of a 299-character
storage cap. Every subject in this catalog was chosen from a sentence and a half. The run
also never asked twice, so `agreement` is NULL on all 43,818 rows -- the schema comment
says outright, "Phase 3's relabel populates it."

Job 0 fixed the input: descriptions now average 990 characters and run to 3,499.

This is the read/write contract the episode-labeller agent works through, shaped like
`admin/api/fit.py`.

    python -m admin.api.label next --limit 20
    python -m admin.api.label record labels.json

Two things the last run did that this one does not. Subjects outside the 148 are
**refused, not aliased** -- the old pipeline kept a hand-maintained near-miss map with one
entry that silently dropped the row, so a real answer and a repaired typo were
indistinguishable. And a subject used exactly once across a whole show is dropped as
noise, which is the confidence gate PROGRAM.md asked for and the last run never applied.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

from admin.api import edits, feeds

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "catalog/catalog.db"

# The vocabulary size is in the name because it is the thing that changed. The 200-episode
# pilot ran against 148 subjects and its answers are preserved under the old id -- but they
# were chosen from a vocabulary that had one word for the built environment, which is the
# gap the pilot itself found, so those episodes are labelled again here rather than kept.
RUN_ID = "2026-07-relabel-v176"

ROLES = {"primary", "secondary"}
CONFIDENCE = {"low", "medium", "high"}
ENTITY_KINDS = {"case", "company", "person", "place", "era", "work"}

# A guard, not an economy. Behind the Bastards carries one description of 81,700
# characters; on a batch of 20 that alone would swamp the other nineteen. Clipping 434
# episodes costs 0.4M tokens across the corpus and stops one pathological entry blowing a
# batch's context.
DESC_CHARS = 4000


def vocabulary(conn: sqlite3.Connection) -> list[dict]:
    """The 148 subjects, with the definition that says what belongs and what does not.

    Sent with every batch. The definition is doing real work: it was written to be the
    thing a labelling pass reads, and vagueness there becomes noise everywhere.
    """
    return [
        {"slug": slug, "name": name, "definition": definition, "theme": theme}
        for slug, name, definition, theme in conn.execute(
            "SELECT sub.slug, sub.name, sub.description, t.name FROM subjects sub "
            "JOIN themes t ON t.id = sub.theme_id WHERE sub.deleted_at IS NULL "
            "ORDER BY t.name, sub.name")
    ]


def pending(conn: sqlite3.Connection, limit: int = 20,
            slice_of: tuple[int, int] | None = None,
            show: str | None = None) -> list[dict]:
    """Episodes this run has not labelled yet, newest-show-first within a show.

    Grouped by show and kept in publication order, because an episode is easier to place
    when you can see what came before it -- a numbered part of a series is obvious in
    context and ambiguous alone.

    `slice_of` is (i, n): only episodes where id % n == i, so several agents run at once.
    Not an OFFSET; the set shrinks as labels land and every window would slide over the
    same episodes.
    """
    where, args = "", []
    if slice_of:
        i, n = slice_of
        where, args = "AND e.id % ? = ?", [n, i]
    # One show at a time, for a pilot: the only way to compare this run against the last
    # one is to label the same shows it labelled and read both.
    if show:
        where += " AND s.slug = ?"
        args.append(show)

    rows = conn.execute(
        f"""
        SELECT e.id, e.title, e.published_at, e.description, e.episode_type,
               s.title, s.description, a.name
        FROM episodes e
        JOIN shows s ON s.id = e.show_id
        LEFT JOIN arcs a ON a.id = e.arc_id AND a.deleted_at IS NULL
        WHERE e.deleted_at IS NULL AND s.deleted_at IS NULL
          AND s.include_verdict = 'keep'
          AND NOT EXISTS (SELECT 1 FROM episode_labels l
                          WHERE l.episode_id = e.id AND l.run_id = ?)
          {where}
        -- Arcless shows first. For an anthology, subjects are the only way anyone
        -- navigates 800 episodes -- there is no "start with the 6-part story" to fall
        -- back on -- so a label there is worth more than the same label on a show that
        -- already has arcs. Then biggest show first, because a half-labelled show is
        -- less useful than a whole small one, and then publication order within a show
        -- so an episode is placed with its neighbours visible.
        ORDER BY (SELECT count(*) FROM arcs a2
                  WHERE a2.show_id = s.id AND a2.deleted_at IS NULL) = 0 DESC,
                 (SELECT count(*) FROM episodes e2
                  WHERE e2.show_id = s.id AND e2.deleted_at IS NULL) DESC,
                 s.id, e.published_at
        LIMIT ?
        """,
        (RUN_ID, *args, limit),
    ).fetchall()

    return [
        {
            "episodeId": eid,
            "title": title,
            "published": (published or "")[:10],
            "kind": kind or "full",
            # The arc this episode belongs to, when it has one. A model placing "Part 3 of
            # The Alabama Murders" should know it is part three of something named.
            "arc": arc,
            "show": show_title,
            "showAbout": (show_about or "")[:240],
            "description": feeds.plain_text(description, DESC_CHARS),
        }
        for eid, title, published, description, kind, show_title, show_about, arc in rows
    ]


def remaining(conn: sqlite3.Connection) -> int:
    return conn.execute(
        """SELECT count(*) FROM episodes e JOIN shows s ON s.id = e.show_id
           WHERE e.deleted_at IS NULL AND s.deleted_at IS NULL
             AND s.include_verdict = 'keep'
             AND NOT EXISTS (SELECT 1 FROM episode_labels l
                             WHERE l.episode_id = e.id AND l.run_id = ?)""",
        (RUN_ID,)).fetchone()[0]


def _validate(item: dict, known: set[str]) -> tuple[dict | None, list[str]]:
    """Check one episode's answer. Returns the cleaned item, or None with the reasons."""
    problems: list[str] = []
    subs, primaries = [], 0

    for s in item.get("subjects") or []:
        slug, role = s.get("slug"), s.get("role", "secondary")
        conf = s.get("confidence", "low")
        if slug not in known:
            problems.append(f"{slug!r} is not one of the 148")
            continue
        if role not in ROLES:
            problems.append(f"role {role!r} not in {sorted(ROLES)}")
            continue
        if conf not in CONFIDENCE:
            problems.append(f"confidence {conf!r} not in {sorted(CONFIDENCE)}")
            continue
        primaries += role == "primary"
        subs.append({"slug": slug, "role": role, "confidence": conf,
                     "agreement": s.get("agreement"), "votes": s.get("votes")})

    if primaries != 1:
        problems.append(f"needs exactly one primary subject, got {primaries}")
    if len(subs) > 3:
        problems.append(f"{len(subs)} subjects; one primary and up to two secondary")

    ents = []
    for e in item.get("entities") or []:
        if e.get("kind") not in ENTITY_KINDS:
            problems.append(f"entity kind {e.get('kind')!r} not in {sorted(ENTITY_KINDS)}")
            continue
        if not (e.get("name") or "").strip():
            continue
        ents.append({"name": e["name"].strip(), "kind": e["kind"],
                     "confidence": e.get("confidence", "low")})

    if problems:
        return None, problems
    return {"episode_id": item.get("episodeId"), "subjects": subs, "entities": ents}, []


def record(conn: sqlite3.Connection, items: list[dict], *, model: str = "claude-sonnet-5",
           decisions_path: Path | None = None) -> dict:
    """Write a batch of labels. Anything malformed is reported, never quietly repaired."""
    known = {r[0] for r in conn.execute(
        "SELECT slug FROM subjects WHERE deleted_at IS NULL")}

    ready, skipped, proposals = [], [], {}
    for item in items:
        clean, problems = _validate(item, known)
        if problems:
            skipped.append(f"{item.get('episodeId')}: {'; '.join(problems)}")
            for s in item.get("subjects") or []:
                if s.get("slug") and s["slug"] not in known:
                    proposals.setdefault(s["slug"], []).append(item.get("episodeId"))
            continue
        ready.append(clean)

    got = {"episodes": 0, "subjects": 0, "entities": 0, "unknown": {}}
    if ready:
        got = edits.label_episodes(
            conn, labels=ready, run_id=RUN_ID, model=model, actor="agent:label",
            note="relabelled at full description length", decisions_path=decisions_path)

    for slug, eids in proposals.items():
        _propose_subject(conn, slug, eids)

    return {"labelled": got["episodes"], "subjects": got["subjects"],
            "entities": got["entities"], "proposed": sorted(proposals),
            "skipped": skipped, "remaining": remaining(conn)}


def _propose_subject(conn: sqlite3.Connection, slug: str, episode_ids: list[int]) -> None:
    """A subject the run wanted and could not use.

    Recorded rather than granted. The browsable vocabulary is a finite menu -- 148 is
    already a lot to navigate -- so a run proposes and a human decides. Examples ride
    along, because a proposal with no evidence is an opinion and one with five episode
    titles is an argument.
    """
    titles = [
        r[0] for r in conn.execute(
            "SELECT title FROM episodes WHERE id IN (%s) LIMIT 5"
            % ",".join("?" * len(episode_ids)), episode_ids)
    ] if episode_ids else []
    conn.execute(
        "INSERT INTO subject_proposals (name, definition, run_id, examples, seen) "
        "VALUES (?, NULL, ?, ?, ?) "
        "ON CONFLICT(name, run_id) DO UPDATE SET seen = seen + excluded.seen",
        (slug, RUN_ID, json.dumps(titles, ensure_ascii=False), len(episode_ids)))
    conn.commit()


def _open() -> sqlite3.Connection:
    conn = sqlite3.connect(DB, timeout=30)
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    nxt = sub.add_parser("next", help="a batch of episodes to label, as JSON")
    nxt.add_argument("--limit", type=int, default=20)
    nxt.add_argument("--slice", help="i/n -- only episodes where id %% n == i")
    nxt.add_argument("--show", help="one show's slug, for a pilot")

    sub.add_parser("vocab", help="the 148 subjects with their definitions")

    rec = sub.add_parser("record", help="write labels back")
    rec.add_argument("file", type=Path)
    rec.add_argument("--model", default="claude-sonnet-5")

    sub.add_parser("status", help="how many episodes are left")

    args = ap.parse_args(argv)
    conn = _open()

    if args.cmd == "next":
        sl = None
        if getattr(args, "slice", None):
            i, n = (int(x) for x in args.slice.split("/"))
            sl = (i, n)
        print(json.dumps({"remaining": remaining(conn),
                          "episodes": pending(conn, args.limit, sl,
                                              getattr(args, "show", None))}, indent=1))
    elif args.cmd == "vocab":
        print(json.dumps({"subjects": vocabulary(conn)}, indent=1))
    elif args.cmd == "record":
        payload = json.loads(args.file.read_text())
        items = payload["episodes"] if isinstance(payload, dict) else payload
        result = record(conn, items, model=args.model)
        print(json.dumps(result, indent=1))
        if result["skipped"]:
            return 1
    else:
        by = dict(conn.execute(
            "SELECT confidence, count(*) FROM episode_labels WHERE run_id = ? GROUP BY 1",
            (RUN_ID,)))
        print(json.dumps({"remaining": remaining(conn), "byConfidence": by}, indent=1))

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
