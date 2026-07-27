"""One feed, one show.

Podcast feeds get retitled. A season ships, the publisher renames the feed after it, and
a catalogue built from two snapshots ends up holding the same programme twice: Slow Burn
and "Slow Burn: Biggie & Tupac", Blindspot and "Blindspot: The Road to 9/11", Deep Cover
and "Deep Cover: Never Seen Again". All eight duplicate pairs in this catalogue are that,
and none of them is a judgement call -- they were wasting review time on a question with
no opinion in it.

Chris's rule: take the most recent title as the feed's name and keep no history of what
it used to be called.

One refinement on top, because the literal rule misfires twice. Pushkin decorates the
Revisionist History feed with its current season, so today the feed is called
"Revisionist History: The Staten Island Problem" and next season it will be called
something else. Adopting that would mean chasing season names forever. So: when the live
feed title *contains* a shorter title the catalogue already holds, prefer the shorter
one. The base name is the durable identity; the decoration is this season's.

Everything here goes through edits.apply(), so a merge is logged, appears in
decisions.jsonl, and can be undone one field at a time like anything else.
"""

from __future__ import annotations

import re
import sqlite3
import urllib.request
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone

from admin.api import edits

_TITLE = re.compile(r"<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>", re.S)
_UA = {"User-Agent": "Mozilla/5.0 (i-want-ur-pod catalog workbench)"}


@dataclass
class MergePlan:
    feed_url: str
    keep_id: int
    keep_title: str
    retitle_to: str | None
    absorb: list[tuple[int, str]] = field(default_factory=list)
    live_title: str | None = None

    def describe(self) -> str:
        lines = [f"{self.keep_title}"]
        if self.retitle_to:
            lines.append(f"    rename to {self.retitle_to!r} (feed says {self.live_title!r})")
        for _, title in self.absorb:
            lines.append(f"    absorb    {title!r}")
        return "\n".join(lines)


def live_feed_title(feed_url: str, timeout: int = 25) -> str | None:
    """What the publisher calls this feed today. The only authority on the question."""
    try:
        raw = urllib.request.urlopen(
            urllib.request.Request(feed_url, headers=_UA), timeout=timeout
        ).read(200_000).decode("utf-8", "replace")
    except Exception:
        return None
    m = _TITLE.search(raw)
    return m.group(1).strip() if m else None


def choose_title(live: str | None, candidates: list[str]) -> str:
    """The name to keep.

    Prefers a catalogue title the live feed title contains -- "Revisionist History" out of
    "Revisionist History: The Staten Island Problem" -- because that is the show and the
    rest is the season. Falls back to the live title, then to the shortest thing we hold.
    """
    if live:
        contained = [c for c in candidates if c.lower() in live.lower() and c.lower() != live.lower()]
        if contained:
            return min(contained, key=len)
        exact = [c for c in candidates if c.lower() == live.lower()]
        if exact:
            return exact[0]
        return live
    return min(candidates, key=len)


def plan(conn: sqlite3.Connection, *, fetch: bool = True) -> list[MergePlan]:
    groups: dict[str, list[tuple[int, str]]] = defaultdict(list)
    for sid, title, feed in conn.execute(
        "SELECT id, title, feed_url FROM shows WHERE deleted_at IS NULL ORDER BY id"
    ):
        groups[feed].append((sid, title))

    plans = []
    for feed, rows in groups.items():
        if len(rows) < 2:
            continue
        titles = [t for _, t in rows]
        live = live_feed_title(feed) if fetch else None
        winner = choose_title(live, titles)

        # The surviving row is whichever already carries the chosen name, else the one
        # with the most episodes -- it has the most to lose by being absorbed.
        keep = next((r for r in rows if r[1] == winner), None)
        if keep is None:
            keep = max(rows, key=lambda r: conn.execute(
                "SELECT count(*) FROM episodes WHERE show_id = ? AND deleted_at IS NULL",
                (r[0],)).fetchone()[0])

        plans.append(MergePlan(
            feed_url=feed,
            keep_id=keep[0],
            keep_title=keep[1],
            retitle_to=winner if winner != keep[1] else None,
            absorb=[r for r in rows if r[0] != keep[0]],
            live_title=live,
        ))
    return plans


def apply_plan(conn: sqlite3.Connection, p: MergePlan, *, decisions_path=None) -> list[str]:
    """Carry out one merge. Every step is an ordinary logged edit."""
    done = []
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    if p.retitle_to:
        edits.apply(conn, entity_type="show", entity_id=p.keep_id, field="title",
                    after=p.retitle_to, actor="agent:merge",
                    note=f"feed is titled {p.live_title!r}", decisions_path=decisions_path)
        done.append(f"renamed to {p.retitle_to!r}")

    for sid, title in p.absorb:
        # The absorbed row's episodes are the same episodes -- same feed, same guids -- so
        # they are duplicates rather than something to move. Hidden, not destroyed, and
        # logged as one sweep rather than one entry per episode.
        slug = conn.execute("SELECT slug FROM shows WHERE id = ?", (sid,)).fetchone()[0]
        n = edits.apply_to_many(
            conn, entity_type="episode",
            scope_sql="show_id = ? AND deleted_at IS NULL", scope_args=(sid,),
            field="deleted_at", after=now, actor="agent:merge",
            note="duplicate of the same feed", entity_key=f"{slug}/*",
            decisions_path=decisions_path,
        )

        edits.apply(conn, entity_type="show", entity_id=sid, field="deleted_at", after=now,
                    actor="agent:merge",
                    note=f"same feed as {p.retitle_to or p.keep_title!r}; the feed was "
                         f"retitled, this is an older name for it",
                    decisions_path=decisions_path)
        edits.apply(conn, entity_type="show", entity_id=sid, field="deleted_reason",
                    after="merged: one feed, one show", actor="agent:merge",
                    decisions_path=decisions_path)
        done.append(f"absorbed {title!r} ({n} duplicate episodes hidden)")

    # It was only ever flagged because of the duplicate. That question is answered.
    verdict = conn.execute(
        "SELECT include_verdict FROM shows WHERE id = ?", (p.keep_id,)).fetchone()[0]
    if verdict == "suspect":
        edits.apply(conn, entity_type="show", entity_id=p.keep_id, field="include_verdict",
                    after="unreviewed", actor="agent:merge",
                    note="the duplicate it was flagged for has been merged away",
                    decisions_path=decisions_path)
        done.append("unflagged")

    return done
