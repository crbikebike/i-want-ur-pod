"""The Phase 1 gate. Exits non-zero if the catalog is not fit to build on.

    python -m catalog.build.verify [--db PATH]

Seven checks run automatically. The eighth is a human one: this script prints the real
output of the three named queries, and Chris decides whether the rows are defensible.
No script can do that part, and pretending otherwise is how a catalog full of plausible
nonsense ships.

Counts are computed from curation/source/ every run, never hardcoded, so this stays a
check on the migration rather than a check on my memory of it.
"""

from __future__ import annotations

import argparse
import glob
import json
import sqlite3
import sys
import time
from pathlib import Path

from catalog.build import fingerprint, migrate
from catalog.build.labels import CURRENT_RUN

ROOT = Path(__file__).resolve().parents[2]
QUERIES = ROOT / "catalog/build/queries"

TRAVERSAL_BUDGET_MS = 50


class Gate:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.notes: list[str] = []

    def check(self, label: str, ok: bool, detail: str = "") -> bool:
        mark = "ok  " if ok else "FAIL"
        print(f"  [{mark}] {label}{(' -- ' + detail) if detail else ''}")
        if not ok:
            self.failures.append(f"{label}: {detail}")
        return ok

    def note(self, text: str) -> None:
        print(f"         {text}")
        self.notes.append(text)


# --- source truth ----------------------------------------------------------------


def source_counts(source: Path) -> dict[str, int]:
    catalog = json.loads((source / "catalog.json").read_text())
    themes = json.loads((source / "themes.json").read_text())
    added_path = ROOT / "catalog/build/added-themes.json"
    if added_path.is_file():
        themes = themes + json.loads(added_path.read_text())["themes"]
    subjects = json.loads((source / "episode-themes/_vocabulary.json").read_text())["themes"]

    labelled_shows = 0
    episodes = 0
    unique_episodes = 0
    for path in sorted(glob.glob(str(source / "episode-themes/*.json"))):
        if Path(path).name.startswith("_"):
            continue
        data = json.loads(Path(path).read_text())
        eps = data.get("episodes") or []
        labelled_shows += 1
        episodes += len(eps)
        unique_episodes += len({e["guid"] for e in eps})

    # Episodes the theming run never saw, recovered into a tracked file. Unlabelled, so
    # they raise the episode count without raising the labelled count.
    recovered_path = source / "recovered-episodes.json"
    recovered = 0
    if recovered_path.is_file():
        payload = json.loads(recovered_path.read_text())
        recovered = sum(len(v) for v in (payload.get("recovered") or {}).values())

    return {
        "shows": len(catalog),
        "themes": len(themes),
        "subjects": len(subjects),
        "labelled_shows": labelled_shows,
        "episodes": episodes,
        "unique_episodes": unique_episodes,
        "recovered": recovered,
        "expected_episodes": unique_episodes + recovered,
    }


# --- checks ----------------------------------------------------------------------


def check_counts(conn, gate: Gate, src: dict) -> None:
    print("\n1. Counts match the source")
    got = fingerprint.table_counts(conn)

    gate.check(
        f"shows: {got.get('shows')} (source {src['shows']})",
        got.get("shows") == src["shows"],
    )
    # Episode rows can legitimately be fewer than raw source rows: a repeated guid
    # inside one show is skipped. Unique guids is the number that must match.
    gate.check(
        f"episodes: {got.get('episodes')} "
        f"(labelled {src['unique_episodes']} + recovered {src['recovered']})",
        got.get("episodes") == src["expected_episodes"],
        f"raw labelled rows {src['episodes']}, "
        f"{src['episodes'] - src['unique_episodes']} repeated guid(s) skipped",
    )
    nt = conn.execute("SELECT count(*) FROM themes").fetchone()[0]
    ns = conn.execute("SELECT count(*) FROM subjects").fetchone()[0]
    gate.check(f"themes: {nt} (source {src['themes']})", nt == src["themes"])
    gate.check(f"subjects: {ns} (source {src['subjects']})", ns == src["subjects"])

    shows_with_eps = conn.execute("SELECT count(DISTINCT show_id) FROM episodes").fetchone()[0]
    gate.check(
        f"every show carries at least one episode: {shows_with_eps} of {src['shows']}",
        shows_with_eps == src["shows"],
    )
    with_subjects = conn.execute(
        "SELECT count(DISTINCT e.show_id) FROM episodes e "
        "JOIN episode_labels el ON el.episode_id = e.id AND el.run_id = ?",
        (CURRENT_RUN,)
    ).fetchone()[0]
    gate.check(
        f"shows with labelled episodes: {with_subjects} (source {src['labelled_shows']})",
        with_subjects == src["labelled_shows"],
    )
    unlabelled = conn.execute(
        "SELECT count(*) FROM episodes e WHERE e.deleted_at IS NULL AND NOT EXISTS "
        "(SELECT 1 FROM episode_labels el WHERE el.episode_id = e.id AND el.run_id = ?)",
        (CURRENT_RUN,)
    ).fetchone()[0]
    gate.note(f"{unlabelled} episodes carry no subject yet -- Phase 3 labels them")


def check_integrity(conn, gate: Gate) -> None:
    print("\n2. No orphans")
    violations = conn.execute("PRAGMA foreign_key_check").fetchall()
    gate.check("foreign keys intact", not violations, f"{len(violations)} violation(s)")

    orphan_subjects = conn.execute(
        "SELECT count(*) FROM subjects s LEFT JOIN themes t ON t.id = s.theme_id "
        "WHERE t.id IS NULL"
    ).fetchone()[0]
    gate.check("every subject belongs to a real theme", orphan_subjects == 0)

    orphan_eps = conn.execute(
        "SELECT count(*) FROM episodes e LEFT JOIN shows s ON s.id = e.show_id WHERE s.id IS NULL"
    ).fetchone()[0]
    gate.check("every episode has a show", orphan_eps == 0)

    orphan_links = conn.execute(
        "SELECT count(*) FROM episode_labels el LEFT JOIN subjects s ON s.id = el.subject_id "
        "WHERE s.id IS NULL"
    ).fetchone()[0]
    gate.check("every episode-subject link resolves", orphan_links == 0)

    dangling_arcs = conn.execute(
        "SELECT count(*) FROM episodes WHERE arc_id IS NOT NULL AND arc_id NOT IN "
        "(SELECT id FROM arcs)"
    ).fetchone()[0]
    gate.check("no episode points at a missing arc", dangling_arcs == 0)


def check_joins(conn, gate: Gate, src: dict) -> None:
    print("\n3. Every catalog row is accounted for")
    depth1 = [
        slug for (slug,) in conn.execute("SELECT slug FROM shows WHERE depth = 1 ORDER BY slug")
    ]
    expected_depth1 = src["shows"] - src["labelled_shows"]
    gate.check(
        f"shows with no labelled episodes held at depth 1: {len(depth1)}",
        len(depth1) == expected_depth1,
        f"expected {expected_depth1}",
    )
    gate.note(f"depth-1 shows (browsable, not yet labelled): {', '.join(depth1)}")

    empty_feed = conn.execute(
        "SELECT count(*) FROM shows WHERE feed_url IS NULL OR trim(feed_url) = ''"
    ).fetchone()[0]
    gate.check("every show has a feed url", empty_feed == 0)

    # At most one reviewed show per feed. The partial index enforces this on write; this
    # asserts it independently, and reports the flagged duplicates either way.
    dupes = conn.execute(
        "SELECT feed_url, count(*) FROM shows WHERE include_verdict <> 'suspect' "
        "GROUP BY feed_url HAVING count(*) > 1"
    ).fetchall()
    gate.check("at most one reviewed show per feed", not dupes, f"{len(dupes)} feed(s) shared")

    suspects = conn.execute(
        "SELECT slug FROM shows WHERE include_verdict = 'suspect' ORDER BY slug"
    ).fetchall()
    gate.note(f"{len(suspects)} shows flagged for the Phase 2 inclusion queue")


def check_edges(conn, gate: Gate) -> None:
    print("\n4. The graph is pruned and can explain itself")
    from catalog.build.edges import MIN_SIMILARITY, TOP_N_PER_SHOW

    silent = conn.execute("SELECT count(*) FROM edges WHERE why IS NULL OR trim(why) = ''").fetchone()[0]
    gate.check("every edge carries a readable reason", silent == 0, f"{silent} silent")

    weak = conn.execute(
        "SELECT count(*) FROM edges WHERE kind LIKE 'shares%' AND weight < ?",
        (MIN_SIMILARITY,),
    ).fetchone()[0]
    gate.check(f"no similarity edge below {MIN_SIMILARITY}", weak == 0, f"{weak} too weak")

    over = conn.execute(
        "SELECT count(*) FROM (SELECT src_id, kind, count(*) n FROM edges "
        "WHERE kind LIKE 'shares%' GROUP BY src_id, kind HAVING n > ?)",
        (TOP_N_PER_SHOW,),
    ).fetchone()[0]
    gate.check(f"no show keeps more than {TOP_N_PER_SHOW} similar shows per kind", over == 0)

    self_edges = conn.execute(
        "SELECT count(*) FROM edges WHERE src_type = dst_type AND src_id = dst_id"
    ).fetchone()[0]
    gate.check("nothing is related to itself", self_edges == 0)

    kinds = dict(conn.execute("SELECT kind, count(*) FROM edges GROUP BY kind").fetchall())
    gate.note(f"edge kinds: {kinds}")

    no_entry = conn.execute(
        "SELECT count(*) FROM shows s WHERE EXISTS (SELECT 1 FROM episodes WHERE show_id = s.id) "
        "AND NOT EXISTS (SELECT 1 FROM edges e WHERE e.src_type='show' AND e.src_id=s.id "
        "AND e.kind='entry_point')"
    ).fetchone()[0]
    gate.check("every show with episodes has an entry point", no_entry == 0, f"{no_entry} without")


def check_traversal_speed(conn, gate: Gate) -> None:
    print("\n5. Traversal is fast enough to run while a screen draws")
    sql = (QUERIES / "explain.sql").read_text()
    pairs = [
        ("revisionist-history", "throughline"),
        ("radiolab", "99-invisible"),
        ("slow-burn", "fiasco"),
    ]
    worst = 0.0
    for a, b in pairs:
        start = time.perf_counter()
        conn.execute(sql, {"from_slug": a, "to_slug": b}).fetchall()
        elapsed = (time.perf_counter() - start) * 1000
        worst = max(worst, elapsed)
        gate.note(f"{a} -> {b}: {elapsed:.1f} ms")
    gate.check(
        f"worst 3-hop explain: {worst:.1f} ms (budget {TRAVERSAL_BUDGET_MS} ms)",
        worst < TRAVERSAL_BUDGET_MS,
    )


def check_reproducible(conn, gate: Gate, db_path: Path, source: Path) -> None:
    print("\n6. A rebuild reproduces the same data")
    recorded = conn.execute(
        "SELECT content_hash, built_at, version FROM releases ORDER BY rowid DESC LIMIT 1"
    ).fetchone()
    if not recorded:
        gate.check("a release row exists", False, "none recorded")
        return
    recorded_hash, built_at, version = recorded

    live = fingerprint.content_hash(conn)
    gate.check("stored hash still matches the data", live == recorded_hash)

    scratch = db_path.parent / "_verify-rebuild.db"
    rebuilt = migrate.build(
        out=scratch, source=source, version=version, built_at=built_at, quiet=True
    )
    gate.check(
        "rebuilding from scratch gives the same hash",
        rebuilt == recorded_hash,
        f"{rebuilt[:12]} vs {recorded_hash[:12]}",
    )
    scratch.unlink(missing_ok=True)
    gate.note(f"content hash {recorded_hash}")


def check_edits_replay(conn, gate: Gate, db_path: Path, source: Path) -> None:
    print("\n7. A correction survives a rebuild")
    from catalog.build import replay

    slug = conn.execute(
        "SELECT slug FROM shows WHERE depth >= 2 ORDER BY slug LIMIT 1"
    ).fetchone()[0]
    before = conn.execute("SELECT why FROM shows WHERE slug = ?", (slug,)).fetchone()[0]
    marker = "VERIFY-MARKER: this correction was applied by verify.py"

    scratch = db_path.parent / "_verify-edits.db"
    migrate.build(out=scratch, source=source, version="verify", built_at="x", quiet=True)
    probe = sqlite3.connect(scratch)
    replay.record(
        probe,
        at="2026-07-26",
        actor="agent:verify",
        entity_type="show",
        entity_key=slug,
        field_name="why",
        before=before,
        after=marker,
        note="gate check 7",
    )
    probe.close()

    scratch2 = db_path.parent / "_verify-edits-2.db"
    migrate.build(
        out=scratch2, source=source, carry_edits_from=scratch, version="verify",
        built_at="x", quiet=True,
    )
    after_conn = sqlite3.connect(scratch2)
    landed = after_conn.execute("SELECT why FROM shows WHERE slug = ?", (slug,)).fetchone()[0]
    kept = after_conn.execute(
        "SELECT count(*) FROM edits WHERE actor = 'agent:verify'"
    ).fetchone()[0]
    after_conn.close()

    gate.check(f"edit to '{slug}' survived the rebuild", landed == marker)
    gate.check("the edit itself is still in the log", kept == 1)
    scratch.unlink(missing_ok=True)
    scratch2.unlink(missing_ok=True)


# --- the human gate --------------------------------------------------------------


def show_query_output(conn) -> None:
    print("\n" + "=" * 78)
    print("8. HUMAN CHECK -- these rows have to be defensible, not merely present")
    print("=" * 78)

    next_thing = (QUERIES / "next-thing.sql").read_text()
    print("\n--- next-thing: 'I liked X, what else?' ---")
    for slug in ["revisionist-history", "slow-burn", "radiolab", "bear-grease"]:
        seed = conn.execute("SELECT title FROM shows WHERE slug = ?", (slug,)).fetchone()
        if not seed:
            continue
        print(f"\n  After {seed[0]}:")
        rows = conn.execute(next_thing, {"slug": slug}).fetchall()
        if not rows:
            print("     (nothing)")
        for r in rows:
            print(f"     {r[1]}  [score {r[3]}]")
            print(f"        because: {r[4]}")
            if r[2]:
                print(f"        pitch  : {r[2][:110]}")

    explain = (QUERIES / "explain.sql").read_text()
    print("\n--- explain: 'how are these two related?' ---")
    for a, b in [
        ("revisionist-history", "throughline"),
        ("bear-grease", "slow-burn"),
        ("radiolab", "casefile-true-crime"),
        ("s-town", "business-wars"),
        ("this-is-actually-happening", "song-exploder"),
    ]:
        ta = conn.execute("SELECT title FROM shows WHERE slug = ?", (a,)).fetchone()
        tb = conn.execute("SELECT title FROM shows WHERE slug = ?", (b,)).fetchone()
        if not (ta and tb):
            continue
        row = conn.execute(explain, {"from_slug": a, "to_slug": b}).fetchone()
        if row:
            print(f"\n  {ta[0]} {row[1]} -> {tb[0]}")
            print(f"     [{row[0]} hop(s), strength {row[2]}]")
        else:
            print(f"\n  {ta[0]} -> {tb[0]}: no path within 3 hops")

    entry = (QUERIES / "entry-point.sql").read_text()
    print("\n--- entry-point: 'where do I start on a huge show?' ---")
    # Suspect shows are excluded: their episode lists belong to a different programme, so
    # any entry point computed from them is meaningless. They are listed separately below.
    biggest = conn.execute(
        "SELECT s.slug FROM shows s JOIN episodes e ON e.show_id = s.id "
        "WHERE s.include_verdict <> 'suspect' "
        "GROUP BY s.id ORDER BY count(e.id) DESC LIMIT 10"
    ).fetchall()
    for (slug,) in biggest:
        row = conn.execute(entry, {"slug": slug}).fetchone()
        if not row:
            continue
        print(f"\n  {row[0]} ({row[1]} episodes)")
        print(f"     {row[3]}")
        print(f"     -> {row[2]}: {row[4]} ({row[5]} ep, confidence {row[6] or 'n/a'})")

    print("\n--- flagged for the Phase 2 inclusion queue (excluded above) ---")
    for slug, title, n in conn.execute(
        "SELECT s.slug, s.title, count(e.id) FROM shows s "
        "LEFT JOIN episodes e ON e.show_id = s.id "
        "WHERE s.include_verdict = 'suspect' GROUP BY s.id ORDER BY count(e.id) DESC"
    ):
        note = conn.execute(
            "SELECT after FROM edits WHERE entity_type = 'catalog' LIMIT 1"
        ).fetchone()
        print(f"  {title[:52]:<54} {n:>4} eps")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=migrate.DEFAULT_OUT)
    parser.add_argument("--source", type=Path, default=migrate.DEFAULT_SOURCE)
    parser.add_argument(
        "--skip-rebuild",
        action="store_true",
        help="skip checks 6 and 7, which rebuild the catalog three times",
    )
    args = parser.parse_args(argv)

    if not args.db.exists():
        print(f"no catalog at {args.db}. Run: python -m catalog.build.migrate")
        return 2

    conn = sqlite3.connect(args.db)
    conn.execute("PRAGMA foreign_keys = ON")
    gate = Gate()
    src = source_counts(args.source)

    print(f"verifying {args.db}  ({args.db.stat().st_size / 1e6:.1f} MB)")

    check_counts(conn, gate, src)
    check_integrity(conn, gate)
    check_joins(conn, gate, src)
    check_edges(conn, gate)
    check_traversal_speed(conn, gate)
    if args.skip_rebuild:
        print("\n6-7. skipped (--skip-rebuild)")
    else:
        check_reproducible(conn, gate, args.db, args.source)
        check_edits_replay(conn, gate, args.db, args.source)

    show_query_output(conn)
    conn.close()

    print("\n" + "=" * 78)
    if gate.failures:
        print(f"GATE FAILED -- {len(gate.failures)} check(s):")
        for f in gate.failures:
            print(f"  - {f}")
        return 1
    print("All automated checks passed.")
    print("Phase 1 is NOT done until Chris says the query rows above are defensible.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
