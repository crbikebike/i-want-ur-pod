#!/usr/bin/env python3
"""Diagnose one approach vs gold: list the arcs it MISSED (false negatives) and the
JUNK arcs it invented (false positives), with example episode titles, so we can see
exactly what patterns to add/tighten in a refine round.

Usage: python3 diagnose.py <approach-name>   (default A2-prefix)
Writes curation/arc-bakeoff/diagnosis-<name>.json and prints a summary.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import approaches as AP  # noqa: E402
import score as SC  # noqa: E402

NAME = sys.argv[1] if len(sys.argv) > 1 else "A2-prefix"


def titles_for(eps_by_guid, guids, k=4):
    out = []
    for g in guids[:k]:
        e = eps_by_guid.get(g)
        if e:
            out.append(e["title"])
    return out


def main():
    gold = json.loads((HERE / "gold.json").read_text())
    fn = AP.CONTENDERS[NAME]
    misses, junk = [], []
    for slug, truth in gold.items():
        if not truth:
            continue
        eps = SC.load_feed(slug)
        if not eps:
            continue
        by_guid = {e["guid"]: e for e in eps}
        detected = fn(eps)
        matches = SC.align(detected, truth)
        matched_true = {ti for _, ti, _, _ in matches}
        matched_det = {di for di, _, _, _ in matches}
        for ti, t in enumerate(truth):
            if ti not in matched_true:
                misses.append({"slug": slug, "arc": t["name"], "n": len(t["members"]),
                               "examples": titles_for(by_guid, t["members"])})
        for di, d in enumerate(detected):
            if di not in matched_det:
                junk.append({"slug": slug, "arc": d["name"], "n": len(d["members"]),
                             "members": d["members"],
                             "titles": [by_guid[g]["title"] for g in d["members"] if g in by_guid],
                             "examples": titles_for(by_guid, d["members"])})
    out = {"approach": NAME, "missed_arcs": misses, "junk_arcs": junk,
           "counts": {"missed": len(misses), "junk": len(junk)}}
    (HERE / f"diagnosis-{NAME}.json").write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n")
    print(f"{NAME}: {len(misses)} missed arcs, {len(junk)} junk arcs")
    print("\n--- sample MISSED arcs (real arcs it failed to detect) ---")
    for m in misses[:25]:
        print(f"  [{m['slug']}] {m['arc']!r} ({m['n']} eps)  e.g. {m['examples'][:2]}")
    print("\n--- sample JUNK arcs (detected but not real) ---")
    for j in junk[:15]:
        print(f"  [{j['slug']}] {j['arc']!r} ({j['n']} eps)  e.g. {j['examples'][:2]}")


if __name__ == "__main__":
    main()
