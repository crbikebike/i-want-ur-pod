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


def _votes(n: int) -> str:
    return f"{n} vote" if n == 1 else f"{n} votes"


def _likely(conn: sqlite3.Connection, episode_id: int, show_slug: str,
            current_slug: str, current_name: str, agreement: int) -> list[dict]:
    """Up to 5 quick picks for the change sheet, most-likely-first.

    The current primary leads -- it is still probably right, just under-agreed. Next,
    any secondary this episode carries in this run with a non-NULL `agreement`: those are
    not the model's leftover guesses, they are escalation's *other* votes -- a reader
    reached for that shelf and lost the tally, which makes them real contenders. Only
    then does the list fall back to the show's own habits, because a shelf this show
    reaches for often is a better guess than the alphabet.
    """
    picks = [{"slug": current_slug, "name": current_name,
              "note": f"{_votes(agreement)} · the current label"}]
    seen = {current_slug}

    for slug, name, sec_agreement in _voting_secondaries(conn, episode_id):
        if slug in seen:
            continue
        picks.append({"slug": slug, "name": name, "note": _votes(sec_agreement)})
        seen.add(slug)

    need = 5 - len(picks)
    if need > 0:
        exclude = f"AND sub.slug NOT IN ({','.join('?' * len(seen))})" if seen else ""
        for slug, name, n in conn.execute(
            f"""
            SELECT sub.slug, sub.name, count(*) AS n
            FROM episode_labels l
            JOIN subjects sub ON sub.id = l.subject_id
            JOIN episodes e ON e.id = l.episode_id
            JOIN shows s ON s.id = e.show_id
            WHERE s.slug = ? AND l.run_id = ? AND l.role = 'primary'
              AND sub.deleted_at IS NULL
              {exclude}
            GROUP BY sub.id
            ORDER BY n DESC, sub.slug
            LIMIT ?
            """, (show_slug, RUN_ID, *seen, need)):
            picks.append({"slug": slug, "name": name, "note": f"this show ×{n}"})

    return picks[:5]


def _voting_secondaries(conn: sqlite3.Connection, episode_id: int) -> list[tuple]:
    """Secondaries this run gave a non-NULL `agreement` -- escalation's *other* votes, a
    reader who reached for that shelf and lost the tally. Shared by `_likely` (which pads
    them with show habits) and `scatter` (which is only ever these, nothing padded)."""
    return list(conn.execute(
        """SELECT sub.slug, sub.name, l.agreement
           FROM episode_labels l JOIN subjects sub ON sub.id = l.subject_id
           WHERE l.episode_id = ? AND l.run_id = ? AND l.role = 'secondary'
             AND l.agreement IS NOT NULL
           ORDER BY l.agreement DESC, sub.slug""", (episode_id, RUN_ID)))


def _neighbours(conn: sqlite3.Connection, episode_id: int, show_slug: str) -> list[dict]:
    """Up to 2 episodes either side, by publication order within the show.

    label.py's `pending()` carries the prior art: a numbered part is obvious in context
    ("Chapter 3" sitting after "Chapter 2") and ambiguous alone. The review card needs the
    same context the labeller had. Deleted episodes are excluded -- they were never a real
    neighbour to begin with, just a gap in the run.
    """
    rows = conn.execute(
        """SELECT e.id, e.title, e.published_at FROM episodes e
           JOIN shows s ON s.id = e.show_id
           WHERE s.slug = ? AND e.deleted_at IS NULL
           ORDER BY e.published_at, e.id""", (show_slug,)).fetchall()
    idx = next((i for i, r in enumerate(rows) if r[0] == episode_id), None)
    if idx is None:
        return []
    before = rows[max(0, idx - 2):idx]
    after = rows[idx + 1:idx + 3]
    return (
        [{"title": t, "published": p, "position": "before"} for _, t, p in before]
        + [{"title": t, "published": p, "position": "after"} for _, t, p in after]
    )


def next_card(conn: sqlite3.Connection, skipped: list[int] | None = None) -> dict | None:
    """One doubtful episode: lowest agreement first, random within a band so two
    sessions do not grind the same corner of the same show."""
    skipped = skipped or []
    skip = f"AND e.id NOT IN ({','.join('?' * len(skipped))})" if skipped else ""
    row = conn.execute(
        f"""
        SELECT e.id, e.title, e.published_at, e.description, e.duration_s, e.episode_type,
               s.slug, s.title, s.description, a.name,
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
    (eid, ep_title, published, desc, duration_s, episode_type,
     show_slug, show_title, show_about, arc,
     subj_slug, subj_name, confidence, agreement, votes) = row
    secondaries = [s for (s,) in conn.execute(
        """SELECT sub.slug FROM episode_labels l JOIN subjects sub ON sub.id=l.subject_id
           WHERE l.episode_id = ? AND l.run_id = ? AND l.role = 'secondary'
           ORDER BY sub.slug""", (eid, RUN_ID))]

    # scatter: what the three readers actually reached for. The primary leads even though
    # it is under-agreed -- it is still the model's best single read -- then every
    # secondary that carried a vote in this run, votes descending. Distinct from `likely`,
    # which pads the list with the show's habits; this is only ever real reads.
    scatter = [{"slug": subj_slug, "name": subj_name, "votes": agreement}]
    scatter += [{"slug": s, "name": n, "votes": v}
                for s, n, v in _voting_secondaries(conn, eid)]

    # entities: real-world things (case, company, person, place, era, work) this run tied
    # to the episode. Filtered to RUN_ID like everything else here -- three runs coexist in
    # episode_entities and only this run's reads belong on this run's review card.
    entities = [{"name": n, "kind": k} for n, k in conn.execute(
        """SELECT en.name, en.kind FROM episode_entities ee
           JOIN entities en ON en.id = ee.entity_id
           WHERE ee.episode_id = ? AND ee.run_id = ?
           ORDER BY en.name""", (eid, RUN_ID))]

    return {
        "episodeId": eid, "title": ep_title, "published": published,
        # Full text, not the old [:1600] clip -- the reviewer said the card doesn't carry
        # enough to judge, and a clipped description mid-sentence is exactly that. The
        # client clamps and offers "expand"; truncation policy belongs at the edge that
        # renders it, not baked into what the API hands back.
        "description": desc or "",
        "show": show_title, "showSlug": show_slug, "arc": arc,
        "showAbout": show_about or "",
        "durationS": duration_s, "episodeType": episode_type,
        "primary": {"slug": subj_slug, "name": subj_name,
                    "confidence": confidence, "agreement": agreement, "votes": votes},
        "secondaries": secondaries,
        "likely": _likely(conn, eid, show_slug, subj_slug, subj_name, agreement),
        "neighbours": _neighbours(conn, eid, show_slug),
        "scatter": scatter,
        "entities": entities,
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
