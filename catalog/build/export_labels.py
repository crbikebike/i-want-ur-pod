"""Write the current run's labels back out to `curation/source/`, one file per show.

CLAUDE.md states the rule this exists to keep: *"The `.db` is a build output — never commit
one, always be able to rebuild it from `curation/source/`."*

The second half had quietly stopped being true. `catalog.db` is gitignored, and the Phase 3
relabel wrote **46,625 labels and 14,339 entities** into it and nowhere else.
`decisions.jsonl` does not save you: `edits.label_episodes()` logs one line per *batch* with
counts, on purpose --

    {"field": "label", "episodes": 20, "subjects": 24, "entities": 15, ...}

-- which records that twenty episodes were labelled, not which subject went on which
episode. 43,818 individual log lines would have buried every human decision in the same
file, and that trade was right. It just means the log is not a backup.

So for two days the only copy of the run lived in one untracked file on one machine, and
`git status` said "clean".

The July run already had this solved: `curation/source/episode-themes/<slug>.json`, one file
per show, tracked. This writes the same shape to `episode-labels/<slug>.json`, keyed on
**show slug plus episode guid** rather than integer ids, because ids are assigned at import
and would land on different rows in a rebuilt database.

    python -m catalog.build.export_labels
    python -m catalog.build.export_labels --run 2026-07-theming

Per show, not one big file: a 46,000-row JSON blob produces a diff nobody can read, and the
point of keeping this in git is that a person can see what a run changed.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

from catalog.build.labels import CURRENT_RUN

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "catalog/catalog.db"
OUT = ROOT / "curation/source/episode-labels"


def export(conn: sqlite3.Connection, out_dir: Path, run_id: str = CURRENT_RUN) -> dict:
    """One JSON file per show carrying every label and entity from `run_id`."""
    out_dir.mkdir(parents=True, exist_ok=True)

    labels: dict[str, dict[str, list]] = defaultdict(lambda: defaultdict(list))
    for slug, guid, sub, role, conf, agree, votes, model in conn.execute(
        """SELECT sh.slug, e.guid, s.slug, l.role, l.confidence, l.agreement, l.votes, l.model
           FROM episode_labels l
           JOIN episodes e ON e.id = l.episode_id
           JOIN shows sh ON sh.id = e.show_id
           JOIN subjects s ON s.id = l.subject_id
           WHERE l.run_id = ? AND e.deleted_at IS NULL
           ORDER BY sh.slug, e.published_at, l.role DESC, s.slug""", (run_id,)):
        row = {"subject": sub, "role": role, "confidence": conf}
        if agree is not None:
            row["agreement"] = agree
        if votes is not None:
            row["votes"] = votes
        if model:
            row["model"] = model
        labels[slug][guid].append(row)

    ents: dict[str, dict[str, list]] = defaultdict(lambda: defaultdict(list))
    for slug, guid, name, kind, conf in conn.execute(
        """SELECT sh.slug, e.guid, en.name, en.kind, ee.confidence
           FROM episode_entities ee
           JOIN episodes e ON e.id = ee.episode_id
           JOIN shows sh ON sh.id = e.show_id
           JOIN entities en ON en.id = ee.entity_id
           WHERE ee.run_id = ? AND e.deleted_at IS NULL
           ORDER BY sh.slug, e.published_at, en.name""", (run_id,)):
        ents[slug][guid].append({"name": name, "kind": kind, "confidence": conf})

    titles = dict(conn.execute("SELECT slug, title FROM shows"))
    written, episodes, rows = 0, 0, 0

    for slug in sorted(labels):
        used: dict[str, int] = defaultdict(int)
        eps = []
        for guid, subs in labels[slug].items():
            for s in subs:
                if s["role"] == "primary":
                    used[s["subject"]] += 1
            eps.append({"guid": guid, "subjects": subs,
                        **({"entities": ents[slug][guid]} if ents[slug].get(guid) else {})})
            rows += len(subs)
        episodes += len(eps)

        payload = {
            "slug": slug,
            "title": titles.get(slug, slug),
            "run": run_id,
            # Counts of *primary* labels only -- a secondary says an episode also touches
            # something, which is not the same as the show being about it.
            "subjectsUsed": [{"slug": s, "count": n}
                             for s, n in sorted(used.items(), key=lambda kv: (-kv[1], kv[0]))],
            "episodes": eps,
        }
        path = out_dir / f"{slug}.json"
        text = json.dumps(payload, ensure_ascii=False, indent=1) + "\n"
        # Only rewrite on change, so a re-export leaves git quiet and a real diff stands out.
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            path.write_text(text, encoding="utf-8")
            written += 1

    return {"shows": len(labels), "filesWritten": written,
            "episodes": episodes, "labelRows": rows}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run", default=CURRENT_RUN)
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args(argv)

    conn = sqlite3.connect(DB, timeout=30)
    got = export(conn, args.out, args.run)
    conn.close()
    print(json.dumps(got, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
