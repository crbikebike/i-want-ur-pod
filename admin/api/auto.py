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
    _settle_notes(conn, report, decisions_path)
    _settle_confident_fit(conn, report, decisions_path)
    return report


def _settle_notes(conn, report, decisions_path) -> None:
    """Flags whose note carries its own answer -- today, cross-promotion."""
    for show_id, title in conn.execute(
        "SELECT id, title FROM shows "
        "WHERE include_verdict = 'suspect' AND deleted_at IS NULL ORDER BY title"
    ).fetchall():
        note = queues._note(conn, show_id)
        verdict = (note or {}).get("auto")
        if verdict not in queues.VERDICTS:
            continue
        edits.apply(
            conn, entity_type="show", entity_id=show_id, field="include_verdict",
            after=verdict, actor="agent:auto",
            note=f"{note['kind']}: {note['meaning']}", decisions_path=decisions_path,
        )
        report.settled.append((title, verdict, note["kind"]))


def _settle_confident_fit(conn, report, decisions_path) -> None:
    """A confident narrative assessment keeps the show.

    Chris: auto-settle the narrative/high's to keep, saves me for the real judgement
    calls. That is the same trade as cross-promotion -- 222 cards whose answer is
    already printed on them, crowding out the ones that need a person.

    Only narrative and only high. `talk` is not automated in the other direction: cutting
    a show on a model's say-so removes it from the product, and the whole reason the fit
    brief tells the analyst to be stingy with `high` is that a wrong one either admits a
    talk show or throws out something good. Keeping is recoverable in a way that a queue
    nobody revisits is not.
    """
    for show_id, title, reason in conn.execute(
        "SELECT id, title, fit_reason FROM shows "
        "WHERE deleted_at IS NULL AND include_verdict = 'unreviewed' "
        "  AND fit_verdict = 'narrative' AND fit_confidence = 'high' ORDER BY title"
    ).fetchall():
        edits.apply(
            conn, entity_type="show", entity_id=show_id, field="include_verdict",
            after="keep", actor="agent:auto",
            note=f"narrative, high confidence: {reason}", decisions_path=decisions_path,
        )
        report.settled.append((title, "keep", "narrative/high"))
