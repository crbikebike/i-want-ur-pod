"""The label review queue: doubtful labels, sampled worst-first, one card at a time.

PROGRAM.md:153 -- labels are *"reviewed through the phase-2 queue, lowest confidence
first."* After escalation, "lowest confidence" has a better measurement: `agreement`,
the count of independent votes behind the primary. This serves the scatter -- one vote
out of three means three readers reached for three different shelves -- before the
merely-uncertain twos.

**Sampled, never a backlog.** The Phase 2 handoff records what a 15,000-item queue with
a counter does to a person: nothing, forever. `counts` here deliberately reports no
total. A card is dealt, decided, and the next one is dealt; there is no bottom to reach.
Every card decided is one more correct label and one more line of evidence for the next
run, and that is worth having at card 1 and card 4,000 equally.

Verdicts write through the doors that already exist -- `edits.label_episodes` for the
label itself, so it is audited, undoable, and lands in decisions.jsonl -- and every
confirm/change appends to `docs/briefs/corrections.md`, the artifact the second half of
the Phase 3 gate names: corrections from review, feeding back into run prompts.
"""

from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from admin.api import edits

ROOT = Path(__file__).resolve().parents[2]
CORRECTIONS = ROOT / "docs/briefs/corrections.md"
RUN_ID = "2026-07-relabel-v176"

_HEADER = """# Corrections From Review

Appended by the label queue, one line per human verdict. **Every labelling brief must
cite this file** -- it is the feedback half of the Phase 3 gate. A correction here means
a person looked at the machine's read and overrode or confirmed it; patterns in the
overrides are the next run's prompt fixes and the vocabulary's next gaps.

Format: `date · show · episode · was -> is · agreement at review`

"""


def counts(conn: sqlite3.Connection) -> dict:
    """Deliberately no total and no remaining. Reviewed-today is the only number a
    sampled queue should show -- progress a person made, not progress they owe."""
    today = conn.execute(
        "SELECT count(*) FROM edits WHERE actor = 'human:labelqueue' "
        "AND date(at) = date('now')").fetchone()[0]
    return {"reviewedToday": today, "sampled": True}


def next_card(conn: sqlite3.Connection, skipped: list[int] | None = None) -> dict | None:
    """One doubtful episode: lowest agreement first, random within a band so two
    sessions do not grind the same corner of the same show."""
    skipped = skipped or []
    skip = f"AND e.id NOT IN ({','.join('?' * len(skipped))})" if skipped else ""
    row = conn.execute(
        f"""
        SELECT e.id, e.title, e.published_at, e.description,
               s.slug, s.title, a.name,
               sub.slug, sub.name, l.confidence, l.agreement, l.votes
        FROM episode_labels l
        JOIN episodes e ON e.id = l.episode_id AND e.deleted_at IS NULL
        JOIN shows s ON s.id = e.show_id AND s.deleted_at IS NULL
          AND s.include_verdict = 'keep'
        JOIN subjects sub ON sub.id = l.subject_id
        LEFT JOIN arcs a ON a.id = e.arc_id AND a.deleted_at IS NULL
        WHERE l.run_id = ? AND l.role = 'primary'
          AND l.agreement IS NOT NULL AND l.agreement < 3
          -- A decided card's primary carries model='human'; that is the reviewed marker.
          AND l.model != 'human'
          {skip}
        ORDER BY l.agreement ASC, random()
        LIMIT 1
        """, (RUN_ID, *skipped)).fetchone()
    if not row:
        return None
    (eid, ep_title, published, desc, show_slug, show_title, arc,
     subj_slug, subj_name, confidence, agreement, votes) = row
    secondaries = [s for (s,) in conn.execute(
        """SELECT sub.slug FROM episode_labels l JOIN subjects sub ON sub.id=l.subject_id
           WHERE l.episode_id = ? AND l.run_id = ? AND l.role = 'secondary'
           ORDER BY sub.slug""", (eid, RUN_ID))]
    return {
        "episodeId": eid, "title": ep_title, "published": published,
        "description": (desc or "")[:1600],
        "show": show_title, "showSlug": show_slug, "arc": arc,
        "primary": {"slug": subj_slug, "name": subj_name,
                    "confidence": confidence, "agreement": agreement, "votes": votes},
        "secondaries": secondaries,
    }


def decide(conn: sqlite3.Connection, episode_id: int, action: str,
           subject_slug: str | None = None,
           decisions_path: Path | None = None,
           corrections_path: Path | None = None) -> dict:
    """confirm: the label stands, a person said so -- confidence becomes high.
    change: the person picked the right subject -- it becomes primary, the machine's
    pick demotes to secondary. Both append to corrections.md."""
    if action not in ("confirm", "change"):
        raise ValueError("action must be 'confirm' or 'change'")

    row = conn.execute(
        """SELECT sub.slug, l.agreement, l.votes, sh.slug, sh.title, e.title, e.guid
           FROM episode_labels l
           JOIN subjects sub ON sub.id = l.subject_id
           JOIN episodes e ON e.id = l.episode_id
           JOIN shows sh ON sh.id = e.show_id
           WHERE l.episode_id = ? AND l.run_id = ? AND l.role = 'primary'""",
        (episode_id, RUN_ID)).fetchone()
    if not row:
        raise ValueError(f"episode {episode_id} has no primary in {RUN_ID}")
    current, agreement, votes, show_slug, show_title, ep_title, guid = row

    if action == "confirm":
        subjects = [{"slug": current, "role": "primary", "confidence": "high",
                     "agreement": agreement, "votes": votes}]
        line = f"{current} -> confirmed"
    else:
        if not subject_slug:
            raise ValueError("change requires a subject slug")
        if not conn.execute("SELECT 1 FROM subjects WHERE slug = ? AND deleted_at IS NULL",
                            (subject_slug,)).fetchone():
            raise ValueError(f"{subject_slug!r} is not a live subject")
        subjects = [{"slug": subject_slug, "role": "primary", "confidence": "high",
                     "agreement": agreement, "votes": votes}]
        if subject_slug != current:
            subjects.append({"slug": current, "role": "secondary",
                             "confidence": "low", "agreement": agreement,
                             "votes": votes})
        line = f"{current} -> {subject_slug}"

    edits.label_episodes(
        conn, labels=[{"episode_id": episode_id, "subjects": subjects}],
        run_id=RUN_ID, model="human", actor="human:labelqueue",
        note=f"label queue: {line}", decisions_path=decisions_path)

    path = corrections_path or CORRECTIONS
    stamp = datetime.now(timezone.utc).date().isoformat()
    entry = (f"- {stamp} · {show_title} · {ep_title[:60]} · {line} · "
             f"agreement {agreement}/{votes}\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_text(_HEADER, encoding="utf-8")
    with path.open("a", encoding="utf-8") as fh:
        fh.write(entry)

    return {"episodeId": episode_id, "action": action, "recorded": line}
