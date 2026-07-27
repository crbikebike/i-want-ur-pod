"""Decisions the workbench already knows the answer to.

Chris, after reviewing a stretch of the queue: *"keep both they are both real shows" is
now the most common. I agree and these don't need my manual review.*

He is right, and the principle generalises past the case that prompted it: **if the
workbench can state the conclusion confidently, it should not be spending a human's
attention on a card.** A queue earns its keep by holding real questions. Padding it with
items whose answer is printed on them teaches you to tap through without reading, which
is exactly how the one card that mattered gets missed.

So a note may declare `auto`, and anything carrying one is settled here rather than
queued. Today that is only cross-promotion -- a show ran a sibling series in its feed,
both are real, keep both -- and it matters going forward because the comber will keep
finding new ones.

Wrong-feed cases are deliberately *not* automated. "The feed serves a different show"
means something is broken, and the right response might be cutting the row or might be
fixing the feed. That is a judgement, so it stays a card.

Everything here goes through the same logged, undoable write path. An automatic decision
that cannot be seen or reversed is just a silent one.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass, field

from admin.api import edits, queues


@dataclass
class AutoReport:
    settled: list[tuple[str, str, str]] = field(default_factory=list)  # title, verdict, why

    def lines(self) -> list[str]:
        if not self.settled:
            return ["auto: nothing to settle"]
        out = [f"auto: settled {len(self.settled)} without asking"]
        out += [f"  {v:<5} {t} — {w}" for t, v, w in self.settled]
        return out


def resolve(conn: sqlite3.Connection, *, decisions_path=None) -> AutoReport:
    report = AutoReport()
    rows = conn.execute(
        "SELECT id, title FROM shows "
        "WHERE include_verdict = 'suspect' AND deleted_at IS NULL ORDER BY title"
    ).fetchall()

    for show_id, title in rows:
        note = queues._note(conn, show_id)
        verdict = (note or {}).get("auto")
        if verdict not in queues.VERDICTS:
            continue
        edits.apply(
            conn, entity_type="show", entity_id=show_id, field="include_verdict",
            after=verdict, actor="agent:auto",
            note=f"{note['kind']}: {note['meaning']}",
            decisions_path=decisions_path,
        )
        report.settled.append((title, verdict, note["kind"]))
    return report
