"""Escalation: three independent votes on every doubtful label, tallied into agreement.

PROGRAM.md line 35: *"escalate to 3 votes only on doubt."* The relabel produced
`confidence`, which is the model's opinion of itself. `agreement` is different evidence:
independent reads that either converge or do not. This module fills it, for exactly the
doubt set and nothing else.

Doubt is two shapes, frozen into a manifest before any vote is cast:

- **low-confidence primaries** -- the model said it was guessing (3,228).
- **once-used (show, subject) pairs** -- PROGRAM.md's noise rule says a subject
  appearing once in a show is suspect. Escalation is that rule with evidence instead of
  deletion: an outvoted one-off dies as noise, a 3-0 one-off has earned its place.

The manifest is deterministic (ordered by episode id, sliced by `id % 8`) so three
voters serve themselves *identical* pages -- independence lives in the reading, not the
sampling. Votes are one slug per episode; the tally is plurality with ties kept by the
incumbent, agreement = the winner's vote count, confidence mapped 3->high 2->medium
1->low. An outvoted primary is demoted to secondary rather than erased -- it was one
model's considered read, and the row records that.

Writes go through `edits.label_episodes`, the same door as everything else, under the
same run id. INSERT OR REPLACE on (episode, subject, run) means a re-tally is
idempotent and nothing is ever double-counted.

    python -m admin.api.escalate manifest /path/to/manifest.json
    python -m admin.api.escalate status /path/to/manifest.json --votes /path/to/votes
    python -m admin.api.escalate page /path/to/manifest.json --slice 3 --page 0
    python -m admin.api.escalate tally /path/to/manifest.json --votes /path/to/votes
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path

from admin.api import edits

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "catalog/catalog.db"
RUN_ID = "2026-07-relabel-v176"
PAGE_SIZE = 20
VOTERS = 3

DOUBT_SQL = """
WITH lows AS (
  SELECT l.episode_id FROM episode_labels l
  JOIN episodes e ON e.id=l.episode_id JOIN shows sh ON sh.id=e.show_id
  WHERE l.run_id=? AND l.role='primary' AND l.confidence='low'
    AND e.deleted_at IS NULL AND sh.deleted_at IS NULL AND sh.include_verdict='keep'),
once AS (
  SELECT min(l.episode_id) episode_id FROM episode_labels l
  JOIN episodes e ON e.id=l.episode_id JOIN shows sh ON sh.id=e.show_id
  WHERE l.run_id=? AND l.role='primary'
    AND e.deleted_at IS NULL AND sh.deleted_at IS NULL AND sh.include_verdict='keep'
  GROUP BY e.show_id, l.subject_id HAVING count(*)=1)
SELECT episode_id FROM lows UNION SELECT episode_id FROM once ORDER BY episode_id
"""


def build_manifest(conn: sqlite3.Connection, out_path: Path,
                   run_id: str = RUN_ID) -> dict:
    """Freeze the doubt set. Votes only count against a frozen list -- a live query
    would shift under the voters as labels change."""
    ids = [r[0] for r in conn.execute(DOUBT_SQL, (run_id, run_id))]

    episodes = {}
    for eid in ids:
        row = conn.execute(
            """SELECT e.title, e.published_at, e.description, sh.title, sh.description,
                      a.name
               FROM episodes e JOIN shows sh ON sh.id=e.show_id
               LEFT JOIN arcs a ON a.id=e.arc_id AND a.deleted_at IS NULL
               WHERE e.id=?""", (eid,)).fetchone()
        labels = conn.execute(
            """SELECT s.slug, l.role, l.confidence FROM episode_labels l
               JOIN subjects s ON s.id=l.subject_id
               WHERE l.episode_id=? AND l.run_id=? ORDER BY l.role DESC, s.slug""",
            (eid, run_id)).fetchall()
        primary = next((s for s, r, _ in labels if r == "primary"), None)
        episodes[str(eid)] = {
            "title": row[0], "published": row[1],
            "description": (row[2] or "")[:1400],
            "show": row[3], "showAbout": (row[4] or "")[:300],
            "arc": row[5],
            "currentPrimary": primary,
            "secondaries": [s for s, r, _ in labels if r == "secondary"],
        }

    slices: dict[str, list[int]] = {str(i): [] for i in range(8)}
    for eid in ids:
        slices[str(eid % 8)].append(eid)

    payload = {"run": run_id, "voters": VOTERS, "pageSize": PAGE_SIZE,
               "slices": slices, "episodes": episodes}
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return {"episodes": len(ids),
            "perSlice": {k: len(v) for k, v in slices.items()},
            "pagesPerSlice": {k: (len(v) + PAGE_SIZE - 1) // PAGE_SIZE
                              for k, v in slices.items()}}


def page(manifest: dict, slice_no: int, page_no: int) -> dict:
    """What a voter sees. `currentPrimary` and `secondaries` are deliberately withheld:
    a voter shown the incumbent stops being an independent read and starts being a
    confirmation. The tally knows the incumbent; the voters must not."""
    ids = manifest["slices"][str(slice_no)][page_no * PAGE_SIZE:(page_no + 1) * PAGE_SIZE]
    hidden = {"currentPrimary", "secondaries"}
    out = []
    for eid in ids:
        ep = {k: v for k, v in manifest["episodes"][str(eid)].items()
              if k not in hidden}
        # 1,000 chars, down from the manifest's 1,400. Descriptions are ~70% of what a
        # voter reads; 1,000 keeps the story visible while cutting the bill. The floor
        # this must never approach is 299 -- the truncation the whole relabel existed
        # to undo.
        ep["description"] = (ep.get("description") or "")[:1000]
        out.append({"episodeId": eid, **ep})
    return {"slice": slice_no, "page": page_no, "episodes": out}


def collect_votes(votes_dir: Path, slice_no: int) -> dict[int, list[str]]:
    """Read every voter file for a slice: v<slice>-<voter>-p<page>.json holding
    {"votes": {"<episodeId>": "<subject slug>"}}."""
    out: dict[int, list[str]] = {}
    for path in sorted(votes_dir.glob(f"v{slice_no}-*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for eid, slug in (data.get("votes") or {}).items():
            if slug:
                out.setdefault(int(eid), []).append(slug)
    return out


def decide(current: str | None, votes: list[str]) -> dict | None:
    """Plurality with ties kept by the incumbent. Pure, so it is testable.

    Returns {winner, agreement, votes, confidence, demoted} or None when there are no
    votes to count."""
    if not votes:
        return None
    counts = Counter(votes)
    top = max(counts.values())
    leaders = sorted(s for s, n in counts.items() if n == top)
    winner = current if current in leaders else leaders[0]
    agreement = counts[winner] if winner in counts else 0
    confidence = {3: "high", 2: "medium"}.get(agreement, "low")
    demoted = current if (current and current != winner) else None
    return {"winner": winner, "agreement": agreement, "votes": len(votes),
            "confidence": confidence, "demoted": demoted}


def thirds_manifest(manifest: dict, votes_dir: Path, known: set[str]) -> dict:
    """A manifest-shaped file holding only the episodes whose two votes disagree --
    what the tie-break wave reads. Same slicing, same page(), same blindness."""
    slices: dict[str, list[int]] = {str(i): [] for i in range(8)}
    episodes = {}
    for slice_no in range(8):
        votes_by_ep = collect_votes(votes_dir, slice_no)
        for eid in manifest["slices"][str(slice_no)]:
            votes = [v for v in votes_by_ep.get(eid, []) if v in known]
            if len(votes) == 2 and votes[0] != votes[1]:
                slices[str(eid % 8)].append(eid)
                episodes[str(eid)] = manifest["episodes"][str(eid)]
    return {"run": manifest["run"], "voters": VOTERS, "pageSize": PAGE_SIZE,
            "slices": slices, "episodes": episodes}


def tally(conn: sqlite3.Connection, manifest: dict, votes_dir: Path,
          run_id: str = RUN_ID, decisions_path: Path | None = None) -> dict:
    """Count every fully-voted episode and write the result through the one door."""
    known = {r[0] for r in conn.execute(
        "SELECT slug FROM subjects WHERE deleted_at IS NULL")}
    already = {r[0] for r in conn.execute(
        "SELECT episode_id FROM episode_labels WHERE run_id=? "
        "AND role='primary' AND agreement IS NOT NULL", (run_id,))}

    items, skipped_short, skipped_done, bad_votes = [], 0, 0, 0
    for slice_no in range(8):
        votes_by_ep = collect_votes(votes_dir, slice_no)
        for eid in manifest["slices"][str(slice_no)]:
            if eid in already:
                skipped_done += 1
                continue
            votes = [v for v in votes_by_ep.get(eid, []) if v in known]
            bad_votes += len(votes_by_ep.get(eid, [])) - len(votes)
            # Adaptive third vote (the "gold" scheme, 2026-08-04): two independent
            # readers agreeing is a verdict -- recorded as agreement 2 of votes 2, so
            # the provenance says exactly what happened. Two readers disagreeing is
            # precisely the case the third read exists for, so those wait for it.
            decidable = (len(votes) >= VOTERS
                         or (len(votes) == 2 and votes[0] == votes[1]))
            if not decidable:
                skipped_short += 1
                continue
            current = manifest["episodes"][str(eid)]["currentPrimary"]
            got = decide(current, votes)
            subjects = [{"slug": got["winner"], "role": "primary",
                         "confidence": got["confidence"],
                         "agreement": got["agreement"], "votes": got["votes"]}]
            if got["demoted"]:
                subjects.append({"slug": got["demoted"], "role": "secondary",
                                 "confidence": "low",
                                 "agreement": Counter(votes)[got["demoted"]],
                                 "votes": got["votes"]})
            items.append({"episode_id": eid, "subjects": subjects})

    written = 0
    for i in range(0, len(items), PAGE_SIZE):
        got = edits.label_episodes(
            conn, labels=items[i:i + PAGE_SIZE], run_id=run_id,
            model="claude-sonnet-5", actor="agent:escalate",
            note="escalation: 3 independent votes tallied into agreement",
            decisions_path=decisions_path)
        written += got.get("subjects", 0)
    return {"episodesTallied": len(items), "subjectRows": written,
            "awaitingVotes": skipped_short, "alreadyTallied": skipped_done,
            "votesOnUnknownSubjects": bad_votes}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("manifest", "status", "page", "tally", "thirds"):
        p = sub.add_parser(name)
        p.add_argument("manifest_path", type=Path)
        if name == "page":
            p.add_argument("--slice", type=int, required=True)
            p.add_argument("--page", type=int, required=True)
        if name in ("status", "tally", "thirds"):
            p.add_argument("--votes", type=Path, required=True)
        if name == "thirds":
            p.add_argument("--out", type=Path, required=True)
    args = ap.parse_args(argv)

    conn = sqlite3.connect(DB, timeout=30)
    if args.cmd == "manifest":
        print(json.dumps(build_manifest(conn, args.manifest_path), indent=1))
        return 0
    manifest = json.loads(args.manifest_path.read_text(encoding="utf-8"))
    if args.cmd == "page":
        print(json.dumps(page(manifest, args.slice, args.page),
                         ensure_ascii=False, indent=1))
    elif args.cmd == "status":
        done = {r[0] for r in conn.execute(
            "SELECT episode_id FROM episode_labels WHERE run_id=? "
            "AND role='primary' AND agreement IS NOT NULL", (manifest["run"],))}
        per = {}
        for s in range(8):
            ids = manifest["slices"][str(s)]
            voted = collect_votes(args.votes, s)
            per[str(s)] = {"episodes": len(ids),
                           "fullyVoted": sum(1 for e in ids
                                             if len(voted.get(e, [])) >= VOTERS),
                           "tallied": sum(1 for e in ids if e in done)}
        print(json.dumps(per, indent=1))
    elif args.cmd == "tally":
        print(json.dumps(tally(conn, manifest, args.votes), indent=1))
    elif args.cmd == "thirds":
        known = {r[0] for r in conn.execute(
            "SELECT slug FROM subjects WHERE deleted_at IS NULL")}
        third = thirds_manifest(manifest, args.votes, known)
        args.out.write_text(json.dumps(third, ensure_ascii=False), encoding="utf-8")
        print(json.dumps({"episodes": len(third["episodes"]),
                          "perSlice": {k: len(v) for k, v in third["slices"].items()}},
                         indent=1))
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
