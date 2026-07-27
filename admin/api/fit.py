"""Is this show the kind of thing the catalog is for?

The catalog's premise is narrow: story-driven, investigative, produced. Not a host and a
guest talking. Around 300 shows were imported from an earlier list and never checked
against that, which made "never reviewed" both the most common card in the queue and the
least interesting one -- the same question 300 times, and most of them have an obvious
answer.

This is the read/write contract the fit-analyst agent works through. It deliberately does
not let the agent near the database: it gets a batch of shows as JSON, and hands back
verdicts as JSON. Everything is written through edits.apply(), so a model's judgement is
logged, attributed to `agent:fit`, visible in decisions.jsonl and undoable exactly like a
human's.

    python -m admin.api.fit next --limit 25 > batch.json
    python -m admin.api.fit record verdicts.json

An assessment is not a verdict. include_verdict stays the human's call; this fills
fit_verdict, and auto.py decides which of those are confident enough to settle
themselves.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

from admin.api import edits

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "catalog/catalog.db"

VERDICTS = {"narrative", "talk", "mixed", "unclear"}
CONFIDENCE = {"high", "medium", "low"}

# How many episode titles to show. Enough to see the shape of a run -- a numbered
# multi-part story reads differently from a stream of guest names -- without turning the
# batch into a wall of text.
EPISODE_SAMPLE = 12


def pending(conn: sqlite3.Connection, limit: int = 25, slice_of: tuple[int, int] | None = None
            ) -> list[dict]:
    """Shows that have never been assessed.

    `slice_of` is (i, n): take only shows where id % n == i. That lets several agents work
    at once without racing. An OFFSET would not: the set shrinks as verdicts land, so
    every agent's window would slide over the same shows. Slicing on id is stable no
    matter what anyone else records.
    """
    where, args = "", []
    if slice_of:
        i, n = slice_of
        where, args = "AND s.id % ? = ?", [n, i]

    rows = conn.execute(
        f"""
        SELECT s.id, s.slug, s.title, s.description, s.why, s.apple_category, s.years,
               n.name AS network,
               (SELECT count(*) FROM episodes WHERE show_id = s.id AND deleted_at IS NULL)
        FROM shows s LEFT JOIN networks n ON n.id = s.network_id
        WHERE s.deleted_at IS NULL
          AND s.fit_checked_at IS NULL
          AND s.include_verdict IN ('unreviewed', 'suspect')
          {where}
        ORDER BY s.id
        LIMIT ?
        """,
        (*args, limit),
    ).fetchall()

    out = []
    for sid, slug, title, description, why, category, years, network, eps in rows:
        titles = [
            r[0] for r in conn.execute(
                "SELECT title FROM episodes WHERE show_id = ? AND deleted_at IS NULL "
                "ORDER BY published_at DESC LIMIT ?", (sid, EPISODE_SAMPLE))
        ]
        out.append({
            "id": sid,
            "slug": slug,
            "title": title,
            "network": network,
            "category": category,
            "years": years,
            "episodeCount": eps,
            "description": description,
            "curatorNote": why,
            "recentEpisodes": titles,
        })
    return out


def remaining(conn: sqlite3.Connection) -> int:
    return conn.execute(
        "SELECT count(*) FROM shows WHERE deleted_at IS NULL AND fit_checked_at IS NULL "
        "AND include_verdict IN ('unreviewed', 'suspect')"
    ).fetchone()[0]


def record(conn: sqlite3.Connection, verdicts: list[dict], *, model: str,
           decisions_path: Path | None = None) -> dict:
    """Write a batch of assessments. One edit each, so each is separately undoable."""
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    written, skipped = 0, []

    for v in verdicts:
        sid, verdict = v.get("id"), v.get("verdict")
        confidence, reason = v.get("confidence"), (v.get("reason") or "").strip()

        if verdict not in VERDICTS:
            skipped.append(f"{sid}: verdict {verdict!r} not in {sorted(VERDICTS)}")
            continue
        if confidence not in CONFIDENCE:
            skipped.append(f"{sid}: confidence {confidence!r} not in {sorted(CONFIDENCE)}")
            continue
        if not reason:
            # A verdict with no reason cannot be reviewed, only trusted.
            skipped.append(f"{sid}: no reason given")
            continue
        if len(reason) > 240:
            reason = reason[:237].rstrip() + "…"

        # Only "already that value" is survivable. Anything else means the write was
        # refused, and counting a refused write as done is how 25 assessments got
        # reported as saved while nothing reached the database.
        failed = None
        for field, value in (("fit_verdict", verdict), ("fit_confidence", confidence),
                             ("fit_reason", reason), ("fit_model", model),
                             ("fit_checked_at", now)):
            try:
                edits.apply(conn, entity_type="show", entity_id=sid, field=field,
                            after=value, actor="agent:fit",
                            note=reason if field == "fit_verdict" else None,
                            decisions_path=decisions_path)
            except edits.EditError as e:
                if "already" in str(e):
                    continue
                failed = f"{sid}: {field} refused — {e}"
                break
        if failed:
            skipped.append(failed)
            continue
        written += 1

    return {"written": written, "skipped": skipped, "remaining": remaining(conn)}


def _open() -> sqlite3.Connection:
    conn = sqlite3.connect(DB, timeout=20)
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    nxt = sub.add_parser("next", help="a batch of shows needing assessment, as JSON")
    nxt.add_argument("--limit", type=int, default=25)
    nxt.add_argument("--slice", help="i/n -- take only shows where id %% n == i, so "
                                     "several agents can run at once")

    rec = sub.add_parser("record", help="write a batch of verdicts back")
    rec.add_argument("file", type=Path, help="JSON: a list of {id, verdict, confidence, reason}")
    rec.add_argument("--model", default="claude-sonnet-5")

    sub.add_parser("status", help="how many are left")

    args = ap.parse_args(argv)
    conn = _open()

    if args.cmd == "next":
        sl = None
        if getattr(args, "slice", None):
            i, n = (int(x) for x in args.slice.split("/"))
            sl = (i, n)
        batch = pending(conn, args.limit, sl)
        print(json.dumps({"remaining": remaining(conn), "shows": batch}, indent=1))
    elif args.cmd == "record":
        payload = json.loads(args.file.read_text())
        verdicts = payload["verdicts"] if isinstance(payload, dict) else payload
        result = record(conn, verdicts, model=args.model)
        print(json.dumps(result, indent=1))
        if result["skipped"]:
            return 1
    else:
        conn_counts = conn.execute(
            "SELECT fit_verdict, count(*) FROM shows WHERE deleted_at IS NULL "
            "GROUP BY fit_verdict").fetchall()
        print(json.dumps({"remaining": remaining(conn), "byVerdict": dict(conn_counts)}, indent=1))

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
