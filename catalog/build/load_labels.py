"""Read `curation/source/episode-labels/` back into `episode_labels` and `episode_entities`.

The mirror of `export_labels.py`, and the half that was missing. CLAUDE.md promises the
`.db` can always be rebuilt from `curation/source/`. Export alone does not deliver that:
it protects the data from being lost with the machine, but a rebuild from a clean checkout
still produced the *July* labels, because `load_source.py` reads `episode-themes/` into
`episode_subjects` and nothing read the newer directory at all.

Two tables, not one. The July run is `episode_subjects`; Phase 3 onward is
`episode_labels`, keyed by `run_id` so runs coexist and none overwrites another. This
loads the second and leaves the first alone.

**Keyed on show slug plus episode guid**, never on integer ids, which are assigned at
import and land on different rows in a rebuilt database. That pairing is unique: 1,264
guids repeat across the catalog because shows share feeds, but zero repeat *within* a
show.

`at` is loaded from the file rather than stamped now. It is inside the content hash, so
stamping a fresh time per row would make every rebuild differ from the last for a reason
that has nothing to do with the catalog changing.

    python -m catalog.build.load_labels          # into catalog/catalog.db
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from dataclasses import dataclass, field
from pathlib import Path

from admin.api.edits import _entity_slug

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "catalog/catalog.db"
SOURCE = ROOT / "curation/source"


@dataclass
class LoadLabelsReport:
    files: int = 0
    shows: int = 0
    episodes: int = 0
    label_rows: int = 0
    entity_rows: int = 0
    entities_created: int = 0
    runs: dict[str, int] = field(default_factory=dict)
    unknown_shows: list[str] = field(default_factory=list)
    unknown_subjects: dict[str, int] = field(default_factory=dict)
    unmatched_guids: dict[str, int] = field(default_factory=dict)
    missing_dir: bool = False

    def lines(self) -> list[str]:
        if self.missing_dir:
            return ["episode-labels/ is not present -- no run to load"]
        out = [
            f"labels: {self.shows} shows, {self.episodes} episodes, "
            f"{self.label_rows} label rows, {self.entity_rows} entity links",
            f"  entities created    : {self.entities_created}",
        ]
        for run, n in sorted(self.runs.items()):
            out.append(f"  run {run}: {n} rows")
        if self.unknown_shows:
            out.append(f"  !! show slug not in catalog: {', '.join(self.unknown_shows[:5])}"
                       + (f" (+{len(self.unknown_shows) - 5} more)"
                          if len(self.unknown_shows) > 5 else ""))
        if self.unknown_subjects:
            worst = sorted(self.unknown_subjects.items(), key=lambda kv: -kv[1])[:5]
            out.append("  !! subject slug not in vocabulary: "
                       + ", ".join(f"{s} x{n}" for s, n in worst))
        if self.unmatched_guids:
            worst = sorted(self.unmatched_guids.items(), key=lambda kv: -kv[1])[:5]
            out.append("  !! guid not found in show: "
                       + ", ".join(f"{s} x{n}" for s, n in worst))
        return out


def _read(source: Path) -> list[dict]:
    """One record per show. Underscore files are run scratch, same rule as episode-themes."""
    directory = source / "episode-labels"
    if not directory.is_dir():
        return []
    out = []
    for path in sorted(directory.glob("*.json")):
        if path.name.startswith("_"):
            continue
        out.append(json.loads(path.read_text(encoding="utf-8")))
    return out


def load(conn: sqlite3.Connection, source: Path = SOURCE) -> LoadLabelsReport:
    """Insert every exported label and entity link. Runs after load_source and vocabulary."""
    report = LoadLabelsReport()
    records = _read(source)
    if not records:
        report.missing_dir = True
        return report
    report.files = len(records)

    show_ids = dict(conn.execute("SELECT slug, id FROM shows"))
    subject_ids = dict(conn.execute("SELECT slug, id FROM subjects"))
    entity_ids = dict(conn.execute("SELECT slug, id FROM entities"))

    labels: list[tuple] = []
    links: list[tuple] = []

    for data in records:
        slug = data.get("slug")
        show_id = show_ids.get(slug)
        if show_id is None:
            report.unknown_shows.append(slug or "(unnamed)")
            continue
        run_id = data.get("run")
        if not run_id:
            report.unknown_shows.append(f"{slug} (no run id)")
            continue

        # guid -> episode id, for this show only. Guids repeat across shows that share a
        # feed, so a catalog-wide map would attach a label to the wrong programme.
        episode_ids = dict(conn.execute(
            "SELECT guid, id FROM episodes WHERE show_id = ? AND deleted_at IS NULL",
            (show_id,)))

        report.shows += 1
        for ep in data.get("episodes") or []:
            guid = ep.get("guid")
            episode_id = episode_ids.get(guid)
            if episode_id is None:
                report.unmatched_guids[slug] = report.unmatched_guids.get(slug, 0) + 1
                continue
            report.episodes += 1

            for entry in ep.get("subjects") or []:
                subject_slug = entry.get("subject")
                sid = subject_ids.get(subject_slug)
                if sid is None:
                    report.unknown_subjects[subject_slug] = (
                        report.unknown_subjects.get(subject_slug, 0) + 1)
                    continue
                labels.append((
                    episode_id, sid, run_id,
                    entry.get("role") or "secondary",
                    entry.get("confidence") or "low",
                    entry.get("agreement"), entry.get("votes"),
                    entry.get("model"), entry.get("at"),
                ))
                report.runs[run_id] = report.runs.get(run_id, 0) + 1

            for entry in ep.get("entities") or []:
                name, kind = entry.get("name"), entry.get("kind")
                if not name or not kind:
                    continue
                key = _entity_slug(name, kind)
                eid = entity_ids.get(key)
                if eid is None:
                    cur = conn.execute(
                        "INSERT OR IGNORE INTO entities (slug, name, kind) VALUES (?,?,?)",
                        (key, name, kind))
                    eid = cur.lastrowid if cur.rowcount else conn.execute(
                        "SELECT id FROM entities WHERE slug = ?", (key,)).fetchone()[0]
                    entity_ids[key] = eid
                    report.entities_created += 1
                links.append((episode_id, eid, run_id, entry.get("confidence"),
                              entry.get("at")))

    # OR IGNORE on both: re-running the loader over a catalog that already carries the run
    # should be a no-op, not a primary-key error.
    conn.executemany(
        "INSERT OR IGNORE INTO episode_labels (episode_id, subject_id, run_id, role, "
        "confidence, agreement, votes, model, at) VALUES (?,?,?,?,?,?,?,?,?)", labels)
    report.label_rows = len(labels)
    conn.executemany(
        "INSERT OR IGNORE INTO episode_entities (episode_id, entity_id, run_id, "
        "confidence, at) VALUES (?,?,?,?,?)", links)
    report.entity_rows = len(links)
    conn.commit()
    return report


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", type=Path, default=DB)
    ap.add_argument("--source", type=Path, default=SOURCE)
    args = ap.parse_args(argv)

    conn = sqlite3.connect(args.db, timeout=30)
    got = load(conn, args.source)
    conn.close()
    for line in got.lines():
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
