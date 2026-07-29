"""Where the vocabulary is too coarse to browse, and what to split.

Two pilots measured the problem rather than guessing at it.

99% Invisible put **82 of 100 episodes on one subject**. Not a labelling failure -- the
pass ran at 69% high confidence with zero refused slugs. There is simply one slug in the
whole 148 aimed at the built environment, so urban planning, product design, typography,
sound design and structural engineering share a bucket while true crime has a dozen.

Swindled, working a well-served part of the vocabulary, used ~30 distinct subjects across
100 episodes and found one specific hole: nothing fits *a trusted employee quietly
embezzling from a private employer*, which is one of that show's most common plots. It
landed as forced, low-confidence `corporate-fraud` every time.

So the vocabulary is not bad, it is **unevenly deep**. Some themes carry 300+ episodes per
available subject; others carry 120. This module finds the first kind and gathers the
evidence a split has to be argued from.

    python -m admin.api.vocab crowded
    python -m admin.api.vocab sample --subject design-and-architecture
    python -m admin.api.vocab propose new.json
    python -m admin.api.vocab accept --all

Nothing here creates a subject on its own. The browsable vocabulary is a finite menu and
growing it is a decision about the product, so a pass proposes and a person accepts.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

from admin.api import edits, feeds
from catalog.build.normalize import slugify

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "catalog/catalog.db"

RUN_ID = "2026-07-vocab-split"

# The labelling run a split is measured against. Runs coexist by `run_id`, so this has to
# be named rather than left open -- see sample().
CURRENT_RUN = "2026-07-relabel-v176"

# Above this many episodes on one subject, browsing it means scrolling an undifferentiated
# list. The measure is per *subject*, not per theme -- a theme-level ratio hides exactly
# the case both pilots found. "Media & Internet Culture" holds 18 subjects and looks
# healthy, while one of them, "Why It Looks Like That", carries 424 episodes on its own
# and is the reason 99% Invisible collapsed onto a single label.
CROWDED = 350


def crowded(conn: sqlite3.Connection, *, run_id: str = CURRENT_RUN) -> list[dict]:
    """Subjects carrying more episodes than anyone can browse.

    Ranked by how many, because that is the order in which splitting helps -- and reported
    with the shows that lean on each, since a subject used by twenty shows is a genuine
    category while one used by two is usually those shows' beat needing its own word.

    Counted within one run. Three label runs coexist, so an unfiltered count sums a subject
    across all of them and reports roughly double -- which would flag subjects as too
    crowded to browse when they are not, and set the whole splitting effort chasing noise.
    """
    rows = conn.execute(
        """
        SELECT sub.id, sub.slug, sub.name, sub.description, t.id, t.slug, t.name,
               count(*) AS eps, count(DISTINCT e.show_id) AS shows
        FROM episode_labels l
        JOIN subjects sub ON sub.id = l.subject_id
        JOIN themes t ON t.id = sub.theme_id
        JOIN episodes e ON e.id = l.episode_id
        WHERE l.role = 'primary' AND l.run_id = ?
          AND sub.deleted_at IS NULL AND e.deleted_at IS NULL
        GROUP BY sub.id
        HAVING eps >= ?
        ORDER BY eps DESC
        """, (run_id, CROWDED,)
    ).fetchall()

    return [
        {"subjectId": sid, "slug": slug, "name": name, "definition": definition,
         "themeId": tid, "theme": theme_name, "themeSlug": theme_slug,
         "episodes": eps, "shows": shows,
         "leanedOnBy": _top_shows(conn, sid, run_id)}
        for sid, slug, name, definition, tid, theme_slug, theme_name, eps, shows in rows
    ]


def _top_shows(conn: sqlite3.Connection, subject_id: int,
               run_id: str = CURRENT_RUN) -> list[dict]:
    return [
        {"show": t, "episodes": n}
        for t, n in conn.execute(
            """SELECT s.title, count(*) n FROM episode_labels l
               JOIN episodes e ON e.id = l.episode_id JOIN shows s ON s.id = e.show_id
               WHERE l.subject_id = ? AND l.role = 'primary' AND l.run_id = ?
                 AND e.deleted_at IS NULL
               GROUP BY s.id ORDER BY n DESC LIMIT 4""", (subject_id, run_id))
    ]


def sample(conn: sqlite3.Connection, subject_slug: str, limit: int = 60,
           *, run_id: str = CURRENT_RUN) -> dict:
    """Episodes currently carrying one subject, spread across the shows that use it.

    Spread, not the first 60. A subject's problem is usually that it spans several kinds
    of story, and taking a prefix would show one show's worth of them -- which is exactly
    how you conclude a split is unnecessary.

    One run and primaries only. Label runs coexist by `run_id`, so an unfiltered query
    returns the same episode once per run that labelled it, and a splitter measuring "what
    fraction of this subject is really X" divides by a padded denominator. A secondary label
    is also the wrong evidence for a split: the question is what a subject is the *main*
    home for. A splitter caught this by hand-drawing its own sample; it should not have had
    to.
    """
    row = conn.execute(
        "SELECT sub.id, sub.name, sub.description, t.id, t.name FROM subjects sub "
        "JOIN themes t ON t.id = sub.theme_id WHERE sub.slug = ?", (subject_slug,)).fetchone()
    if not row:
        raise SystemExit(f"no subject with slug {subject_slug!r}")
    sid, name, definition, theme_id, theme_name = row

    episodes = [
        {"title": t, "show": show, "description": feeds.plain_text(d, 400)}
        for t, show, d in conn.execute(
            """SELECT e.title, s.title, e.description
               FROM episode_labels l
               JOIN episodes e ON e.id = l.episode_id
               JOIN shows s ON s.id = e.show_id
               WHERE l.subject_id = ? AND e.deleted_at IS NULL
                 AND l.run_id = ? AND l.role = 'primary'
               ORDER BY (e.id * 2654435761) % 1000003
               LIMIT ?""", (sid, run_id, limit))
    ]
    return {"subjectId": sid, "slug": subject_slug, "name": name,
            "definition": definition, "theme": theme_name, "themeId": theme_id,
            "episodes": episodes}


def propose(conn: sqlite3.Connection, items: list[dict]) -> dict:
    """Record proposed subjects. Creates nothing."""
    made, skipped = 0, []
    existing = {r[0] for r in conn.execute("SELECT slug FROM subjects")}

    for item in items:
        name = (item.get("name") or "").strip()
        definition = (item.get("definition") or "").strip()
        if not name or not definition:
            skipped.append(f"{name or '(unnamed)'}: needs both a name and a definition")
            continue
        # The definition is what a labelling pass reads to decide. Vagueness there becomes
        # noise everywhere, which is why an empty one is refused rather than defaulted.
        slug = item.get("slug") or slugify(name)
        if slug in existing:
            skipped.append(f"{slug}: already a subject")
            continue

        parent = conn.execute("SELECT id FROM subjects WHERE slug = ?",
                              (item.get("splitsFrom"),)).fetchone()
        theme = conn.execute("SELECT id FROM themes WHERE slug = ?",
                             (item.get("theme"),)).fetchone()
        if not theme:
            skipped.append(f"{slug}: theme {item.get('theme')!r} does not exist")
            continue

        conn.execute(
            "INSERT INTO subject_proposals (name, slug, definition, theme_id, splits_from, "
            "run_id, examples, seen) VALUES (?,?,?,?,?,?,?,?) "
            "ON CONFLICT(name, run_id) DO UPDATE SET definition = excluded.definition",
            (name, slug, definition, theme[0], parent[0] if parent else None, RUN_ID,
             json.dumps(item.get("examples") or [], ensure_ascii=False),
             len(item.get("examples") or [])))
        made += 1

    conn.commit()
    return {"proposed": made, "skipped": skipped}


def waiting(conn: sqlite3.Connection) -> list[dict]:
    return [
        {"id": pid, "name": name, "slug": slug, "definition": definition,
         "theme": theme, "splitsFrom": parent,
         "examples": json.loads(examples or "[]")}
        for pid, name, slug, definition, theme, parent, examples in conn.execute(
            """SELECT p.id, p.name, p.slug, p.definition, t.name, sub.name, p.examples
               FROM subject_proposals p
               LEFT JOIN themes t ON t.id = p.theme_id
               LEFT JOIN subjects sub ON sub.id = p.splits_from
               WHERE p.resolved_at IS NULL AND p.slug IS NOT NULL
               ORDER BY p.id""")
    ]


def accept(conn: sqlite3.Connection, proposal_ids: list[int] | None = None,
           *, decisions_path: Path | None = None) -> dict:
    """Turn accepted proposals into real subjects.

    Creating a subject is a catalog write, so it goes through the one door. Each one is a
    separate edit: accepting forty at once should still be forty undoable decisions, not a
    single lump nobody can pick apart later.
    """
    rows = conn.execute(
        "SELECT id, name, slug, definition, theme_id FROM subject_proposals "
        "WHERE resolved_at IS NULL AND slug IS NOT NULL"
        + (" AND id IN (%s)" % ",".join("?" * len(proposal_ids)) if proposal_ids else ""),
        proposal_ids or ()).fetchall()

    made, skipped = 0, []
    for pid, name, slug, definition, theme_id in rows:
        if conn.execute("SELECT 1 FROM subjects WHERE slug = ?", (slug,)).fetchone():
            skipped.append(f"{slug}: already exists")
            continue
        try:
            edits.create_subject(conn, slug=slug, name=name, description=definition,
                                 theme_id=theme_id, actor="agent:vocab",
                                 note="split from an overloaded subject",
                                 decisions_path=decisions_path)
        except Exception as e:
            skipped.append(f"{slug}: {e}")
            continue
        conn.execute("UPDATE subject_proposals SET resolved_at = datetime('now'), "
                     "resolved_as = 'accepted' WHERE id = ?", (pid,))
        made += 1
    conn.commit()
    return {"created": made, "skipped": skipped}


def _open() -> sqlite3.Connection:
    conn = sqlite3.connect(DB, timeout=30)
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    crw = sub.add_parser("crowded",
                         help="subjects carrying more episodes than anyone can browse")
    crw.add_argument("--run", default=CURRENT_RUN)

    smp = sub.add_parser("sample", help="episodes carrying one subject, spread across shows")
    smp.add_argument("--subject", required=True)
    smp.add_argument("--limit", type=int, default=60)
    smp.add_argument("--run", default=CURRENT_RUN)

    pro = sub.add_parser("propose", help="record proposed subjects")
    pro.add_argument("file", type=Path)

    sub.add_parser("waiting", help="proposals awaiting a decision")

    acc = sub.add_parser("accept", help="create subjects from accepted proposals")
    acc.add_argument("--all", action="store_true")
    acc.add_argument("--id", type=int, action="append")

    args = ap.parse_args(argv)
    conn = _open()

    if args.cmd == "crowded":
        print(json.dumps({"subjects": crowded(conn, run_id=args.run)}, indent=1))
    elif args.cmd == "sample":
        print(json.dumps(sample(conn, args.subject, args.limit, run_id=args.run), indent=1))
    elif args.cmd == "propose":
        payload = json.loads(args.file.read_text())
        items = payload["subjects"] if isinstance(payload, dict) else payload
        result = propose(conn, items)
        print(json.dumps(result, indent=1))
        if result["skipped"]:
            return 1
    elif args.cmd == "waiting":
        print(json.dumps({"proposals": waiting(conn)}, indent=1))
    else:
        if not (args.all or args.id):
            raise SystemExit("say --all or --id N; creating vocabulary is not a default")
        print(json.dumps(accept(conn, None if args.all else args.id), indent=1))

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
