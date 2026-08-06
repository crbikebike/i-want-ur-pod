"""A record of the long jobs: what ran, over what, and what it did.

The `runs` table has existed since the first migration and nothing has ever written to it.
That was fine while every change came from a person tapping a card. Phase 3 changes that:
a single pass touches 28,773 episodes, and "what happened last Tuesday" stops being
answerable from memory.

Workbench-owned, like `feed_proposals`. No catalog entity lives here, so it is written
directly rather than through `edits.apply()` -- and the distinction matters. A run is
bookkeeping *about* work. The work itself still goes through the one door, so every
description this module's callers change is separately logged and separately undoable.

A run is deliberately not a lock. Two passes over the same shows would be wasteful but not
harmful, and a lock that outlives a crashed process is worse than the waste it prevents.
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field
from datetime import datetime, timezone


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


@dataclass
class Run:
    id: int
    kind: str
    args: dict = field(default_factory=dict)

    # Counters the caller adds to as it goes. Kept here rather than in the caller so a
    # run's summary is written the same way whoever is running it.
    tallies: dict = field(default_factory=dict)
    problems: list[str] = field(default_factory=list)

    def tally(self, key: str, n: int = 1) -> None:
        self.tallies[key] = self.tallies.get(key, 0) + n

    def problem(self, what: str) -> None:
        """Something went wrong for one item. Never fatal on its own.

        A feed that 404s is a fact about that feed, not a reason to abandon 287 others --
        but it has to be reported rather than swallowed, because "0 failures" and "we
        stopped counting" look identical in a summary.
        """
        self.problems.append(what)

    def summary(self) -> str:
        parts = [f"{k} {v}" for k, v in sorted(self.tallies.items())]
        if self.problems:
            parts.append(f"problems {len(self.problems)}")
        return ", ".join(parts) or "nothing to do"


def start(conn: sqlite3.Connection, kind: str, args: dict | None = None) -> Run:
    cur = conn.execute(
        "INSERT INTO runs (kind, status, started_at, args) VALUES (?, 'running', ?, ?)",
        (kind, _now(), json.dumps(args or {}, ensure_ascii=False)))
    conn.commit()
    return Run(cur.lastrowid, kind, args or {})


def finish(conn: sqlite3.Connection, run: Run, *, status: str = "done") -> None:
    """Close a run. `problems` ride along in the summary rather than in a side file.

    A run that touched nothing still gets closed as `done` -- "it ran and there was
    nothing to do" is an answer, and leaving it `running` forever would make the surface
    unreadable within a week.
    """
    detail = run.summary()
    if run.problems:
        # First few inline. The rest are countable but not worth carrying in a summary
        # column -- the per-item failures are already in the caller's own output.
        shown = "; ".join(run.problems[:5])
        detail += f" — {shown}"
        if len(run.problems) > 5:
            detail += f" (+{len(run.problems) - 5} more)"
    conn.execute(
        "UPDATE runs SET status = ?, finished_at = ?, summary = ? WHERE id = ?",
        (status, _now(), detail[:1000], run.id))
    conn.commit()


def fail(conn: sqlite3.Connection, run: Run, why: str) -> None:
    """The run itself broke, as distinct from an item inside it failing."""
    run.problem(why)
    finish(conn, run, status="failed")


def recent(conn: sqlite3.Connection, limit: int = 20) -> list[dict]:
    return [
        {"id": r[0], "kind": r[1], "status": r[2], "startedAt": r[3], "finishedAt": r[4],
         "args": json.loads(r[5] or "{}"), "summary": r[6], "approval": r[7]}
        for r in conn.execute(
            "SELECT id, kind, status, started_at, finished_at, args, summary, approval "
            "FROM runs ORDER BY id DESC LIMIT ?", (limit,))
    ]
