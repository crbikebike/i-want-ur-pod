"""How far a show has been worked, on a scale the app reads.

    1  nothing has labelled its episodes
    2  labelled, but no story arc
    3  has at least one arc, or has been read for arcs and correctly has none
    4  as 3, and every episode is labelled at medium confidence or better

Recomputed from the data, never incremented. Depth used to be nudged forward at seed time
by `UPDATE shows SET depth = 3 WHERE depth = 2 AND id IN (SELECT show_id FROM arcs)`, and
that `depth = 2` guard is exactly the kind of bug a derived value invites: Broken Record
gained seven arcs and stayed at depth 1 forever, because it had never passed through 2.
Deriving the whole ladder in one place costs a few hundred milliseconds and cannot drift.

**Depth 3 counts a read, not an arc.** 23 kept shows are anthologies -- This American Life,
Swindled, Bodies -- where each episode stands alone and no arc will ever exist. Requiring a
row in `arcs` would hold them at 2 permanently and would restate PROGRAM.md's gate as
something unreachable. `shows.arcs_checked_at` records that a pass read the show and found
nothing, which is a finished job, not an unfinished one.

**Depth 4 is a quality claim and can go down.** It says the labels on this show are ones
you would defend, not merely that they exist -- so a re-read that finds a show thinner than
believed drops it back to 3, which is the point. `low` is the signal the labelling pass was
built to record truthfully, and this is what reads it.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass

from catalog.build.labels import CURRENT_RUN


@dataclass
class DepthReport:
    at: dict[int, int]
    moved: int

    def lines(self) -> list[str]:
        return [
            "Depth",
            *(f"  depth {d}: {self.at.get(d, 0):>4}" for d in (1, 2, 3, 4)),
            f"  moved this rebuild: {self.moved}",
        ]


def rebuild(conn: sqlite3.Connection, *, run_id: str = CURRENT_RUN) -> DepthReport:
    """Set every kept show's depth from what is actually in the catalog.

    Four grouped scans and one `executemany`, rather than correlated subqueries per show.
    The obvious version -- `UPDATE shows SET depth = (SELECT CASE ... )` with an EXISTS
    over `episode_labels` inside -- reads as clearer SQL and runs the label table once per
    show. On 275 shows, 30k episodes and 46k labels that took over four minutes and held
    the write lock the whole time, which matters here because a second session is working
    the same database.
    """
    eps = dict(conn.execute(
        "SELECT show_id, count(*) FROM episodes WHERE deleted_at IS NULL GROUP BY show_id"))
    labelled = dict(conn.execute(
        "SELECT e.show_id, count(DISTINCT e.id) FROM episodes e "
        "JOIN episode_labels l ON l.episode_id = e.id AND l.run_id = ? "
        "WHERE e.deleted_at IS NULL GROUP BY e.show_id", (run_id,)))
    solid = dict(conn.execute(
        "SELECT e.show_id, count(DISTINCT e.id) FROM episodes e "
        "JOIN episode_labels l ON l.episode_id = e.id AND l.run_id = ? "
        "WHERE e.deleted_at IS NULL AND l.role = 'primary' "
        "  AND l.confidence IN ('medium', 'high') GROUP BY e.show_id", (run_id,)))
    arcs = dict(conn.execute(
        "SELECT show_id, count(*) FROM arcs WHERE deleted_at IS NULL GROUP BY show_id"))

    rows, moved = [], 0
    for sid, checked, was in conn.execute(
            "SELECT id, arcs_checked_at, depth FROM shows WHERE deleted_at IS NULL"):
        n = eps.get(sid, 0)
        if not labelled.get(sid, 0):
            d = 1
        elif not arcs.get(sid, 0) and checked is None:
            d = 2
        elif n and solid.get(sid, 0) == n:
            d = 4
        else:
            d = 3
        moved += d != was
        rows.append((d, sid))

    conn.executemany("UPDATE shows SET depth = ? WHERE id = ?", rows)

    after = dict(conn.execute(
        "SELECT depth, count(*) FROM shows WHERE deleted_at IS NULL GROUP BY depth"))
    # Counted per row, not by differencing the distribution -- a show going 2 -> 3 while
    # another goes 3 -> 2 nets to zero, and "moved: 0" would then be a false all-clear.
    return DepthReport(at=after, moved=moved)
