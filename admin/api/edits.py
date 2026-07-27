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
#
# `deleted_at` is editable everywhere because deletion is soft throughout: setting it
# hides the row, clearing it brings the row back, and both are just edits with the same
# audit trail and undo as any other.
WRITABLE: dict[str, tuple[str, set[str]]] = {
    "show":    ("shows",    {"include_verdict", "depth", "lang", "title", "why", "description",
                             "deleted_at", "deleted_reason",
                             # the fit assessment: a model's opinion, not a verdict
                             "fit_verdict", "fit_confidence", "fit_reason",
                             "fit_checked_at", "fit_model",
                             # when a show was last read for story arcs, and by what
                             "arcs_checked_at", "arcs_checked_by", "arcs_checked_eps",
                             # Re-matching a show that was pointed at the wrong podcast
                             # has to change these. Unlike slug and guid, nothing else
                             # references them, and the partial unique index still
                             # prevents two live shows landing on one feed.
                             "feed_url", "home_url", "artwork_url"}),
    "theme":   ("themes",   {"name", "description", "deleted_at"}),
    "subject": ("subjects", {"name", "description", "theme_id", "deleted_at"}),
    "arc":     ("arcs",     {"name", "description", "confidence", "kind",
                             "deleted_at", "deleted_reason"}),
    "episode": ("episodes", {"title", "description", "available", "duration_s",
                             "deleted_at", "deleted_reason"}),
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


def apply_to_many(
    conn: sqlite3.Connection,
    *,
    entity_type: str,
    scope_sql: str,
    scope_args: tuple,
    field: str,
    after,
    actor: str,
    note: str,
    entity_key: str,
    decisions_path: Path | None = None,
) -> int:
    """Set one field across many rows, logged once.

    Merging a duplicate hides 623 episodes at a stroke. Routing that through apply() row
    by row would put 623 entries in the log for a single decision, which buries the
    decisions that matter -- so this writes one entry describing the sweep, with the
    count in it.

    Still the same door: the rows change, `edits` gets an entry, decisions.jsonl gets a
    line, all in one transaction. `scope_sql` is a WHERE clause, never interpolated with
    caller data.
    """
    if entity_type not in WRITABLE:
        raise EditError(f"{entity_type!r} is not editable")
    table, allowed = WRITABLE[entity_type]
    if field not in allowed:
        raise EditError(f"{entity_type}.{field} is not editable")

    at = _now()
    try:
        cur = conn.execute(
            f'UPDATE "{table}" SET "{field}" = ? WHERE {scope_sql}', (after, *scope_args)
        )
        n = cur.rowcount
        if n == 0:
            conn.rollback()
            return 0
        conn.execute(
            "INSERT INTO edits (at, actor, entity_type, entity_key, field, before, after, note) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (at, actor, entity_type, entity_key, field, None, after, f"{note} ({n} rows)"),
        )
        path = decisions_path or DECISIONS
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "at": at, "actor": actor, "entity": entity_type, "key": entity_key,
                "field": field, "after": after, "rows": n, "note": note,
            }, ensure_ascii=False) + "\n")
            fh.flush()
    except Exception:
        conn.rollback()
        raise
    conn.commit()
    return n


def ingest_episodes(
    conn: sqlite3.Connection,
    *,
    show_id: int,
    episodes: list,
    actor: str,
    note: str,
    decisions_path: Path | None = None,
) -> dict:
    """Add episodes read from a feed. The insert door.

    `apply()` cannot do this: it changes one field on a row that already exists, and there
    is no row yet. But the same promise has to hold -- the database changes, `edits` gets
    an entry, decisions.jsonl gets a line, one transaction -- or the single-write-path
    rule is true only for the writes that happen to be convenient.

    Logged once with a count rather than once per episode, for the reason apply_to_many
    exists: repointing Empire brings back 658 episodes, and 658 log lines would bury the
    one decision that mattered.

    This is not a judgement, so it is never attributed to a human. It is what a publisher
    says is in their feed, and re-reading the feed later should converge on the same
    answer: existing GUIDs are left alone rather than overwritten, because the catalog's
    own work -- arcs, subjects, verdicts -- hangs off those rows.
    """
    at = _now()
    key = entity_key(conn, "show", show_id)
    added, existing = 0, 0
    try:
        for ep in episodes:
            already = conn.execute(
                "SELECT id, deleted_at FROM episodes WHERE show_id = ? AND guid = ?",
                (show_id, ep.guid)).fetchone()
            if already:
                # Un-hide one that a bad re-match had swept away, but never rewrite its
                # fields -- anything attached to it was our work, not the publisher's.
                if already[1] is not None:
                    conn.execute("UPDATE episodes SET deleted_at = NULL, deleted_reason = NULL "
                                 "WHERE id = ?", (already[0],))
                existing += 1
                continue
            conn.execute(
                "INSERT INTO episodes (show_id, guid, title, published_at, description, "
                "season, episode_number, episode_type, duration_s) VALUES (?,?,?,?,?,?,?,?,?)",
                (show_id, ep.guid, ep.title, ep.published_at, ep.description,
                 ep.season, ep.episode_number, ep.episode_type, ep.duration_s))
            added += 1

        if added == 0 and existing == 0:
            conn.rollback()
            return {"added": 0, "existing": 0}

        conn.execute(
            "INSERT INTO edits (at, actor, entity_type, entity_key, field, before, after, note) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (at, actor, "episode", f"{key}/*", "ingest", None, str(added),
             f"{note} ({added} added, {existing} already present)"))
        path = decisions_path or DECISIONS
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "at": at, "actor": actor, "entity": "episode", "key": f"{key}/*",
                "field": "ingest", "added": added, "existing": existing, "note": note,
            }, ensure_ascii=False) + "\n")
            fh.flush()
    except Exception:
        conn.rollback()
        raise
    conn.commit()
    return {"added": added, "existing": existing}


def create_arcs(
    conn: sqlite3.Connection,
    *,
    show_id: int,
    arcs: list[dict],
    actor: str,
    note: str,
    decisions_path: Path | None = None,
) -> dict:
    """Create arcs and attach their episodes. The third insert door.

    `apply()` can rename an arc but cannot make one, and `episodes.arc_id` is not editable
    through it at all, so grouping episodes into a story has had no way in. Each arc is
    `{slug, name, kind, confidence, source, members: [guid, ...]}`.

    An episode belongs to at most one arc -- `episodes.arc_id` is a single nullable
    foreign key -- so an episode already claimed is left where it is. That is what makes
    the ordering matter: hand-adjudicated `gold` arcs are written first and a detector's
    guess can never take an episode off one.

    An arc that ends up with fewer than two members is dropped rather than stored. A
    "story" of one episode is a title that happened to match a pattern, and 799 of those
    would bury the real ones.
    """
    at = _now()
    key = entity_key(conn, "show", show_id)
    made, attached, skipped = 0, 0, 0
    try:
        for arc in arcs:
            free = [
                r[0] for r in conn.execute(
                    "SELECT id FROM episodes WHERE show_id = ? AND guid IN (%s) "
                    "AND arc_id IS NULL AND deleted_at IS NULL"
                    % ",".join("?" * len(arc["members"])),
                    (show_id, *arc["members"]))
            ] if arc["members"] else []

            if len(free) < 2:
                skipped += 1
                continue

            cur = conn.execute(
                "INSERT INTO arcs (show_id, slug, kind, name, description, confidence, source) "
                "VALUES (?,?,?,?,?,?,?)",
                (show_id, arc["slug"], arc.get("kind", "arc"), arc["name"],
                 arc.get("description"), arc.get("confidence", "low"), arc["source"]))
            arc_id = cur.lastrowid
            conn.executemany("UPDATE episodes SET arc_id = ? WHERE id = ?",
                             [(arc_id, eid) for eid in free])
            made += 1
            attached += len(free)

        if not made:
            conn.rollback()
            return {"arcs": 0, "episodes": 0, "skipped": skipped}

        conn.execute(
            "INSERT INTO edits (at, actor, entity_type, entity_key, field, before, after, note) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (at, actor, "arc", f"{key}/*", "create", None, str(made),
             f"{note} ({made} arcs over {attached} episodes, {skipped} too small to keep)"))
        path = decisions_path or DECISIONS
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "at": at, "actor": actor, "entity": "arc", "key": f"{key}/*",
                "field": "create", "arcs": made, "episodes": attached,
                "skipped": skipped, "note": note,
            }, ensure_ascii=False) + "\n")
            fh.flush()
    except Exception:
        conn.rollback()
        raise
    conn.commit()
    return {"arcs": made, "episodes": attached, "skipped": skipped}


def refresh_episodes(
    conn: sqlite3.Connection,
    *,
    show_id: int,
    episodes: list,
    actor: str,
    note: str,
    decisions_path: Path | None = None,
) -> dict:
    """Replace description and duration on episodes we already hold, from the feed.

    Deliberately not `ingest_episodes`, which never overwrites an existing row. That rule
    is right for what it guards -- arcs, subjects and verdicts hang off those rows and
    they are our work, not the publisher's. These two fields are the opposite: they are
    the publisher's own words about their own episode, and ours are a bad copy. The
    2026-07 import truncated every description at 299 characters, so 24,000 episodes are
    carrying a third of the text the feed actually offers.

    Title is left alone on purpose. A title can be corrected by hand and a re-read would
    silently undo that; a description cannot be corrected by hand because nobody is
    rewriting 28,000 blurbs.

    Nothing is overwritten with less than we already have. A publisher who shortens a
    description, or a feed that serves a summary in place of the full text, must not cost
    us the longer version -- that would turn a refresh into data loss, quietly, at scale.
    """
    at = _now()
    key = entity_key(conn, "show", show_id)
    longer = filled = unchanged = 0
    try:
        for ep in episodes:
            row = conn.execute(
                "SELECT id, description, duration_s FROM episodes "
                "WHERE show_id = ? AND guid = ?", (show_id, ep.guid)).fetchone()
            if not row:
                continue
            eid, have_desc, have_dur = row

            touched = False

            new_desc = (ep.description or "").strip()
            if new_desc and len(new_desc) > len(have_desc or ""):
                conn.execute("UPDATE episodes SET description = ? WHERE id = ?",
                             (new_desc, eid))
                longer += 1
                touched = True

            if ep.duration_s and have_dur is None:
                conn.execute("UPDATE episodes SET duration_s = ? WHERE id = ?",
                             (ep.duration_s, eid))
                filled += 1
                touched = True

            if not touched:
                unchanged += 1

        if not (longer or filled):
            conn.rollback()
            return {"longer": 0, "durations": 0, "unchanged": unchanged}

        conn.execute(
            "INSERT INTO edits (at, actor, entity_type, entity_key, field, before, after, note) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (at, actor, "episode", f"{key}/*", "refresh", None, str(longer),
             f"{note} ({longer} descriptions lengthened, {filled} durations filled)"))
        path = decisions_path or DECISIONS
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "at": at, "actor": actor, "entity": "episode", "key": f"{key}/*",
                "field": "refresh", "descriptions": longer, "durations": filled,
                "note": note,
            }, ensure_ascii=False) + "\n")
            fh.flush()
    except Exception:
        conn.rollback()
        raise
    conn.commit()
    return {"longer": longer, "durations": filled, "unchanged": unchanged}


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
